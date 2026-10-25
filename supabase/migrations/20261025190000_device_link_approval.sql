-- A claimed code waits for the owner's device to allow it. Only then does the
-- new device join the account and receive the sealed Recovery Key.
alter table public.device_link_codes
  add column claimant_device_id uuid,
  add column claimant_name text check (length(claimant_name) <= 60),
  add column claimed_at timestamptz,
  add column status text not null default 'open'
    check (status in ('open', 'claimed', 'allowed', 'refused'));

drop policy owner_or_linked on public.device_link_codes;
drop policy owner_seals on public.device_link_codes;
create policy owner_reads on public.device_link_codes for select to authenticated
  using (owner_auth_uid = auth.uid());
revoke update (encrypted_payload) on public.device_link_codes from authenticated;

create or replace function public.create_device_link_code() returns text
language plpgsql security definer set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  code text := '';
  b integer;
  me uuid := private.my_user_id();
begin
  if me is null then
    raise exception 'not_registered';
  end if;
  while length(code) < 8 loop
    b := get_byte(extensions.gen_random_bytes(1), 0);
    if b < 248 then
      code := code || substr(alphabet, b % 31 + 1, 1);
    end if;
  end loop;
  delete from public.device_link_codes
  where owner_auth_uid = auth.uid() and status <> 'allowed';
  insert into public.device_link_codes (user_id, owner_auth_uid, code_hash, expires_at)
  values (me, auth.uid(), private.code_hash(code), now() + interval '5 minutes');
  return code;
end
$$;

drop function public.link_device_by_code(text, uuid, text, text);

-- Null for a wrong or spent code; raising would roll back the count.
-- Wrong codes back off per IP: three free, then 5 s doubling to an hour.
create function public.link_device_by_code(
  p_code text,
  p_device_id uuid,
  p_ephemeral_pubkey text,
  p_display_name text default null
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  caller_ip text := coalesce(split_part(
    current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1),
    'unknown');
  attempt private.link_attempts;
  link public.device_link_codes;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  if exists (select 1 from public.user_devices where auth_uid = auth.uid()) then
    raise exception 'session_registered_to_another_user';
  end if;

  select * into attempt from private.link_attempts where ip = caller_ip;
  if attempt.failures >= 3 and now() < attempt.last_failure
      + least(interval '5 seconds' * 2 ^ (attempt.failures - 3), interval '1 hour') then
    raise exception 'too_many_attempts';
  end if;

  select * into link from public.device_link_codes
  where code_hash = private.code_hash(p_code)
    and expires_at > now() and status = 'open'
  for update;
  if not found then
    insert into private.link_attempts (ip, failures, last_failure)
    values (caller_ip, 1, now())
    on conflict (ip) do update
      set failures = link_attempts.failures + 1, last_failure = now();
    return null;
  end if;

  delete from private.link_attempts where ip = caller_ip;
  update public.device_link_codes
  set linked_auth_uid = auth.uid(), ephemeral_pubkey = p_ephemeral_pubkey,
      claimant_device_id = p_device_id, claimant_name = left(p_display_name, 60),
      claimed_at = now(), status = 'claimed'
  where id = link.id;
  return true;
end
$$;

-- The caller's latest claim; the account and the sealed key once allowed.
create function public.device_link_claim()
returns table (status text, user_id uuid, encrypted_payload text)
language sql stable security definer set search_path = ''
as $$
  select c.status,
    case when c.status = 'allowed' then c.user_id end,
    case when c.status = 'allowed' then c.encrypted_payload end
  from public.device_link_codes c
  where c.linked_auth_uid = auth.uid()
  order by c.claimed_at desc
  limit 1
$$;

-- The owner allows or refuses a claim within five minutes of it. Allowing adds
-- the device to the account and stores the key sealed to it.
create function public.answer_device_link(
  p_link uuid,
  p_allow boolean,
  p_payload text default null
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  link public.device_link_codes;
begin
  select * into link from public.device_link_codes
  where id = p_link and owner_auth_uid = auth.uid() and status = 'claimed'
    and claimed_at > now() - interval '5 minutes'
  for update;
  if not found then
    return false;
  end if;
  if not p_allow then
    update public.device_link_codes set status = 'refused' where id = p_link;
    return true;
  end if;
  update public.device_link_codes
  set status = 'allowed', encrypted_payload = p_payload
  where id = p_link;
  insert into public.user_devices (auth_uid, user_id, device_id, display_name)
  values (link.linked_auth_uid, link.user_id, link.claimant_device_id,
    link.claimant_name);
  return true;
end
$$;

revoke execute on function public.link_device_by_code from public, anon;
grant execute on function public.link_device_by_code to authenticated;
revoke execute on function public.device_link_claim from public, anon;
grant execute on function public.device_link_claim to authenticated;
revoke execute on function public.answer_device_link from public, anon;
grant execute on function public.answer_device_link to authenticated;
