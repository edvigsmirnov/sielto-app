create schema private;
grant usage on schema private to authenticated;

create domain public.money as text check (value ~ '^[0-9]+(\.[0-9]+)?$');

create table public.user_devices (
  auth_uid uuid primary key references auth.users (id) on delete cascade,
  user_id uuid not null,
  device_id uuid not null unique,
  display_name text,
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index on public.user_devices (user_id);

create table public.spaces (
  id uuid primary key,
  title text not null check (length(trim(title)) > 0),
  space_type text not null
    check (space_type in ('personal', 'family', 'trip', 'project', 'custom')),
  budget_mode text not null check (budget_mode in ('incomeDriven', 'budget', 'flow')),
  owner_id uuid not null,
  country_code text,
  timezone text not null,
  currency_code text not null,
  max_members integer default 0 check (max_members is null or max_members >= 0),
  manual_balance public.money,
  manual_balance_updated_at timestamptz,
  min_schema_version integer not null default 1,
  feed_order_mode text not null default 'grouped'
    check (feed_order_mode in ('grouped', 'free')),
  created_at timestamptz not null,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid
);

create table public.space_members (
  space_id uuid not null references public.spaces (id) on delete cascade,
  user_id uuid not null,
  joined_at timestamptz not null default now(),
  primary key (space_id, user_id)
);
create index on public.space_members (user_id);

create table public.user_profiles (
  user_id uuid primary key,
  nickname text not null check (length(trim(nickname)) > 0),
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid
);

create table public.member_local_labels (
  space_id uuid not null references public.spaces (id) on delete cascade,
  viewer_user_id uuid not null,
  target_user_id uuid not null,
  local_name text,
  local_role text,
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid,
  primary key (space_id, viewer_user_id, target_user_id)
);

create table public.categories (
  id uuid primary key,
  space_id uuid not null references public.spaces (id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  color text,
  icon text,
  starter_key text,
  expense_type text not null default 'variable'
    check (expense_type in ('mandatory', 'variable')),
  sort_order integer not null default 0,
  created_at timestamptz not null,
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid
);
create index on public.categories (space_id);

create table public.budget_periods (
  id uuid primary key,
  space_id uuid not null references public.spaces (id) on delete cascade,
  period_type text not null check (period_type in ('continuous', 'incomeDriven')),
  start_date date not null,
  end_date date check (end_date >= start_date),
  window_start date,
  window_end date check (window_end >= window_start),
  anchor_date date,
  holiday_data_incomplete boolean not null default false,
  deadline_date date,
  deadline_is_hard boolean not null default false,
  budget_target public.money,
  unfrozen_until timestamptz,
  unfreeze_reason text,
  created_at timestamptz not null,
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid
);
create index on public.budget_periods (space_id);

create table public.income_recurrence_rules (
  id uuid primary key,
  space_id uuid not null references public.spaces (id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  amount public.money check (amount::numeric > 0),
  is_anchor boolean not null default false,
  schedule_type text not null
    check (schedule_type in ('fixedDate', 'weekdayRule', 'dateRange', 'boundaryDays')),
  fixed_day integer check (fixed_day between 1 and 31),
  weekday_ordinal text
    check (weekday_ordinal in ('first', 'second', 'third', 'fourth', 'last')),
  weekday_day text check (weekday_day in
    ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')),
  date_range_start integer check (date_range_start between 1 and 31),
  date_range_end integer check (date_range_end between 1 and 31),
  boundary_anchor text check (boundary_anchor in ('start', 'end')),
  boundary_count integer check (boundary_count > 0),
  country_code text,
  created_at timestamptz not null,
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid,
  check (schedule_type <> 'fixedDate' or fixed_day is not null),
  check (schedule_type <> 'weekdayRule'
    or (weekday_ordinal is not null and weekday_day is not null)),
  check (schedule_type <> 'dateRange'
    or (date_range_start is not null and date_range_end is not null)),
  check (schedule_type <> 'boundaryDays'
    or (boundary_anchor is not null and boundary_count is not null))
);
create index on public.income_recurrence_rules (space_id);

create table public.incomes (
  id uuid primary key,
  space_id uuid not null references public.spaces (id) on delete cascade,
  recurrence_rule_id uuid references public.income_recurrence_rules (id),
  title text not null check (length(trim(title)) > 0),
  amount public.money check (amount::numeric > 0),
  expected_date date not null,
  actual_date date,
  budget_period_id uuid references public.budget_periods (id),
  sort_order integer not null default 0,
  is_paid boolean not null default false,
  notes text,
  created_at timestamptz not null,
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid
);
create index on public.incomes (space_id, expected_date);

create table public.payments (
  id uuid primary key,
  space_id uuid not null references public.spaces (id) on delete cascade,
  budget_period_id uuid references public.budget_periods (id),
  period_assignment text not null default 'auto'
    check (period_assignment in ('auto', 'manual')),
  category_id uuid references public.categories (id),
  group_recurring_id uuid,
  title text not null check (length(trim(title)) > 0),
  amount public.money not null,
  due_date date not null,
  expense_type text not null check (expense_type in ('mandatory', 'variable')),
  sort_order integer not null default 0,
  is_paid boolean not null default false,
  notes text,
  created_at timestamptz not null,
  is_deleted boolean not null default false,
  client_edited_at timestamptz not null,
  server_received_at timestamptz,
  last_modified_by uuid
);
create index on public.payments (space_id, due_date);

create function private.my_user_id() returns uuid
language sql stable security definer set search_path = ''
as $$ select user_id from public.user_devices where auth_uid = auth.uid() $$;

create function private.my_space_ids() returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select space_id from public.space_members where user_id = private.my_user_id()
$$;

create function private.my_fellow_user_ids() returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select user_id from public.space_members
  where space_id in (select private.my_space_ids())
$$;

revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Last write wins by the clamped client time; an older edit is skipped.
create function private.stamp_sync() returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.server_received_at := now();
  new.client_edited_at :=
    least(greatest(new.client_edited_at, now() - interval '30 days'), now());
  new.last_modified_by := coalesce(private.my_user_id(), new.last_modified_by);
  if tg_op = 'UPDATE' and new.client_edited_at < old.client_edited_at then
    return null;
  end if;
  return new;
end
$$;

create trigger stamp_sync before insert or update on public.spaces
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.user_profiles
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.member_local_labels
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.categories
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.budget_periods
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.income_recurrence_rules
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.incomes
  for each row execute function private.stamp_sync();
create trigger stamp_sync before insert or update on public.payments
  for each row execute function private.stamp_sync();

create function private.add_owner_member() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.space_members (space_id, user_id) values (new.id, new.owner_id);
  return null;
end
$$;

create trigger add_owner_member after insert on public.spaces
  for each row execute function private.add_owner_member();

create function public.register_new_user(
  p_user_id uuid,
  p_device_id uuid,
  p_display_name text default null
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  registered uuid;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select user_id into registered from public.user_devices where auth_uid = auth.uid();
  if found then
    if registered = p_user_id then
      return;
    end if;
    raise exception 'session_registered_to_another_user';
  end if;
  if exists (select 1 from public.user_devices where user_id = p_user_id) then
    raise exception 'user_id_taken';
  end if;
  insert into public.user_devices (auth_uid, user_id, device_id, display_name)
  values (auth.uid(), p_user_id, p_device_id, p_display_name);
end
$$;

revoke execute on function public.register_new_user from public, anon;
grant execute on function public.register_new_user to authenticated;

alter table public.user_devices enable row level security;
alter table public.spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.user_profiles enable row level security;
alter table public.member_local_labels enable row level security;
alter table public.categories enable row level security;
alter table public.budget_periods enable row level security;
alter table public.income_recurrence_rules enable row level security;
alter table public.incomes enable row level security;
alter table public.payments enable row level security;

create policy own on public.user_devices for select to authenticated
  using (user_id = (select private.my_user_id()));

create policy member_read on public.spaces for select to authenticated
  using (owner_id = (select private.my_user_id())
    or id in (select private.my_space_ids()));
create policy owner_create on public.spaces for insert to authenticated
  with check (owner_id = (select private.my_user_id()));
create policy member_edit on public.spaces for update to authenticated
  using (id in (select private.my_space_ids()))
  with check (id in (select private.my_space_ids()));
create policy owner_delete on public.spaces for delete to authenticated
  using (owner_id = (select private.my_user_id()));

create policy member_read on public.space_members for select to authenticated
  using (space_id in (select private.my_space_ids()));

create policy fellow_read on public.user_profiles for select to authenticated
  using (user_id = (select private.my_user_id())
    or user_id in (select private.my_fellow_user_ids()));
create policy own_create on public.user_profiles for insert to authenticated
  with check (user_id = (select private.my_user_id()));
create policy own_edit on public.user_profiles for update to authenticated
  using (user_id = (select private.my_user_id()))
  with check (user_id = (select private.my_user_id()));

create policy own_in_member_space on public.member_local_labels for all to authenticated
  using (viewer_user_id = (select private.my_user_id())
    and space_id in (select private.my_space_ids()))
  with check (viewer_user_id = (select private.my_user_id())
    and space_id in (select private.my_space_ids()));

create policy member on public.categories for all to authenticated
  using (space_id in (select private.my_space_ids()))
  with check (space_id in (select private.my_space_ids()));
create policy member on public.budget_periods for all to authenticated
  using (space_id in (select private.my_space_ids()))
  with check (space_id in (select private.my_space_ids()));
create policy member on public.income_recurrence_rules for all to authenticated
  using (space_id in (select private.my_space_ids()))
  with check (space_id in (select private.my_space_ids()));
create policy member on public.incomes for all to authenticated
  using (space_id in (select private.my_space_ids()))
  with check (space_id in (select private.my_space_ids()));
create policy member on public.payments for all to authenticated
  using (space_id in (select private.my_space_ids()))
  with check (space_id in (select private.my_space_ids()));

revoke all on all tables in schema public from anon, authenticated;
grant select on public.user_devices to authenticated;
grant select, insert, delete on public.spaces to authenticated;
grant update (
  title, space_type, country_code, timezone, currency_code, max_members,
  manual_balance, manual_balance_updated_at, min_schema_version, feed_order_mode,
  client_edited_at, last_modified_by
) on public.spaces to authenticated;
grant select on public.space_members to authenticated;
grant select, insert, update on
  public.user_profiles,
  public.member_local_labels,
  public.categories,
  public.budget_periods,
  public.income_recurrence_rules,
  public.incomes,
  public.payments
to authenticated;
