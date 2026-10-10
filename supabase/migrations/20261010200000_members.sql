create table public.space_invites (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces (id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_by uuid not null
);
create index on public.space_invites (space_id);

alter table public.space_invites enable row level security;
create policy owner_only on public.space_invites for select to authenticated
  using (space_id in (select id from public.spaces
    where owner_id = (select private.my_user_id())));
create policy owner_revokes on public.space_invites for delete to authenticated
  using (space_id in (select id from public.spaces
    where owner_id = (select private.my_user_id())));
revoke all on public.space_invites from anon, authenticated;
grant select, delete on public.space_invites to authenticated;

-- Eight characters from 31 without look-alikes (no 0, O, 1, I, L).
create function private.new_code() returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  code text := '';
  b integer;
begin
  while length(code) < 8 loop
    b := get_byte(extensions.gen_random_bytes(1), 0);
    if b < 248 then
      code := code || substr(alphabet, b % 31 + 1, 1);
    end if;
  end loop;
  return code;
end
$$;

create function private.has_room(p_space_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select s.max_members is null
    or (select count(*) from public.space_members m where m.space_id = s.id)
      < s.max_members
  from public.spaces s where s.id = p_space_id
$$;

create function public.create_space_invite(p_space_id uuid) returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := private.my_user_id();
  code text := private.new_code();
begin
  if not exists (select 1 from public.spaces
      where id = p_space_id and owner_id = me) then
    raise exception 'not_owner';
  end if;
  if not private.has_room(p_space_id) then
    raise exception 'space_full';
  end if;
  insert into public.space_invites (space_id, token_hash, expires_at, created_by)
  values (p_space_id, private.code_hash(code), now() + interval '15 minutes', me);
  return code;
end
$$;

-- Null for a wrong or spent code; raising would roll back the count.
-- Wrong codes back off per IP, as device links do.
create function public.join_space_by_token(p_code text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := private.my_user_id();
  caller_ip text := 'invite:' || coalesce(split_part(
    current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1),
    'unknown');
  attempt private.link_attempts;
  invite public.space_invites;
begin
  if me is null then
    raise exception 'not_registered';
  end if;

  select * into attempt from private.link_attempts where ip = caller_ip;
  if attempt.failures >= 3 and now() < attempt.last_failure
      + least(interval '5 seconds' * 2 ^ (attempt.failures - 3), interval '1 hour') then
    raise exception 'too_many_attempts';
  end if;

  select * into invite from public.space_invites
  where token_hash = private.code_hash(p_code) and expires_at > now()
  for update;
  if not found then
    insert into private.link_attempts (ip, failures, last_failure)
    values (caller_ip, 1, now())
    on conflict (ip) do update
      set failures = link_attempts.failures + 1, last_failure = now();
    return null;
  end if;

  delete from private.link_attempts where ip = caller_ip;
  if not exists (select 1 from public.space_members
      where space_id = invite.space_id and user_id = me) then
    if not private.has_room(invite.space_id) then
      raise exception 'space_full';
    end if;
    insert into public.space_members (space_id, user_id)
    values (invite.space_id, me);
  end if;
  delete from public.space_invites where id = invite.id;
  return invite.space_id;
end
$$;

create function public.remove_member(p_space_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.spaces
      where id = p_space_id and owner_id = private.my_user_id()) then
    raise exception 'not_owner';
  end if;
  delete from public.space_members
  where space_id = p_space_id and user_id = p_user_id
    and user_id <> private.my_user_id();
end
$$;

create function public.transfer_ownership(p_space_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.spaces
      where id = p_space_id and owner_id = private.my_user_id()) then
    raise exception 'not_owner';
  end if;
  if not exists (select 1 from public.space_members
      where space_id = p_space_id and user_id = p_user_id) then
    raise exception 'not_a_member';
  end if;
  update public.spaces
  set owner_id = p_user_id, client_edited_at = now()
  where id = p_space_id;
end
$$;

-- The owner hands the Space over or deletes it instead.
create function public.leave_space(p_space_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.spaces
      where id = p_space_id and owner_id = private.my_user_id()) then
    raise exception 'owner_cannot_leave';
  end if;
  delete from public.space_members
  where space_id = p_space_id and user_id = private.my_user_id();
end
$$;

revoke execute on function public.create_space_invite, public.join_space_by_token,
  public.remove_member, public.transfer_ownership, public.leave_space
  from public, anon;
grant execute on function public.create_space_invite, public.join_space_by_token,
  public.remove_member, public.transfer_ownership, public.leave_space
  to authenticated;
revoke execute on function private.new_code, private.has_room
  from public, anon, authenticated;

-- Only the owner sets the limit, never below the current member count.
create function private.guard_max_members() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.max_members is distinct from old.max_members
      and private.my_user_id() is not null then
    if old.owner_id <> private.my_user_id() then
      new.max_members := old.max_members;
    elsif new.max_members is not null and new.max_members
        < (select count(*) from public.space_members where space_id = new.id) then
      raise exception 'below_members';
    end if;
  end if;
  return new;
end
$$;

create trigger sync_max_members before update on public.spaces
  for each row execute function private.guard_max_members();

select cron.schedule('expired_invites', '0 * * * *',
  $$delete from public.space_invites where expires_at < now()$$);
