create table public.device_link_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  owner_auth_uid uuid not null references auth.users (id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  linked_auth_uid uuid references auth.users (id) on delete cascade,
  ephemeral_pubkey text,
  encrypted_payload text
);
create index on public.device_link_codes (owner_auth_uid);

alter table public.device_link_codes enable row level security;
create policy owner_or_linked on public.device_link_codes for select to authenticated
  using (owner_auth_uid = auth.uid() or linked_auth_uid = auth.uid());
create policy owner_seals on public.device_link_codes for update to authenticated
  using (owner_auth_uid = auth.uid() and linked_auth_uid is not null)
  with check (owner_auth_uid = auth.uid());
revoke all on public.device_link_codes from anon, authenticated;
grant select on public.device_link_codes to authenticated;
grant update (encrypted_payload) on public.device_link_codes to authenticated;

alter publication supabase_realtime add table public.device_link_codes;

create table private.link_attempts (
  ip text primary key,
  failures integer not null,
  last_failure timestamptz not null
);

create function private.code_hash(code text) returns text
language sql immutable set search_path = ''
as $$ select encode(sha256(convert_to(upper(code), 'UTF8')), 'hex') $$;

-- Eight characters from 31 without look-alikes (no 0, O, 1, I, L).
create function public.create_device_link_code() returns text
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
  where owner_auth_uid = auth.uid() and linked_auth_uid is null;
  insert into public.device_link_codes (user_id, owner_auth_uid, code_hash, expires_at)
  values (me, auth.uid(), private.code_hash(code), now() + interval '5 minutes');
  return code;
end
$$;

-- Null for a wrong or spent code; raising would roll back the count.
-- Wrong codes back off per IP: three free, then 5 s doubling to an hour.
create function public.link_device_by_code(
  p_code text,
  p_device_id uuid,
  p_ephemeral_pubkey text,
  p_display_name text default null
) returns uuid
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
    and expires_at > now() and linked_auth_uid is null
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
  set linked_auth_uid = auth.uid(), ephemeral_pubkey = p_ephemeral_pubkey
  where id = link.id;
  insert into public.user_devices (auth_uid, user_id, device_id, display_name)
  values (auth.uid(), link.user_id, p_device_id, p_display_name);
  return link.user_id;
end
$$;

revoke execute on function public.create_device_link_code from public, anon;
grant execute on function public.create_device_link_code to authenticated;
revoke execute on function public.link_device_by_code from public, anon;
grant execute on function public.link_device_by_code to authenticated;
revoke execute on function private.code_hash from public, anon, authenticated;
