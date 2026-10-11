begin;
select plan(4);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b');
insert into user_devices (auth_uid, user_id, device_id) values
  ('00000000-0000-4000-a000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b', '22222222-2222-4222-8222-222222222222',
   'dddddddd-dddd-4ddd-8ddd-00000000000b');
insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
values ('33333333-3333-4333-8333-333333333333', 'Family', 'family', 'incomeDriven',
  '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now());
insert into space_members (space_id, user_id) values
  ('33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222');
insert into budget_periods
  (id, space_id, period_type, start_date, end_date, created_at, client_edited_at)
values ('44444444-4444-4444-8444-444444444444', '33333333-3333-4333-8333-333333333333',
  'incomeDriven', current_date - 60, current_date - 31, now(), now() - interval '1 day');

create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
set local role authenticated;

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select throws_ok($$ update budget_periods set unfrozen_until = now() + interval '1 hour',
  unfreeze_reason = 'fix', client_edited_at = now() $$,
  'P0001', 'not_owner', 'a member cannot reopen a period');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select throws_ok($$ update budget_periods set unfrozen_until = now() + interval '1 hour',
  unfreeze_reason = ' ', client_edited_at = now() $$,
  'P0001', 'bad_unfreeze', 'a reason is required');
select throws_ok($$ update budget_periods set unfrozen_until = now() + interval '3 days',
  unfreeze_reason = 'fix', client_edited_at = now() $$,
  'P0001', 'bad_unfreeze', 'never longer than 48 hours');
update budget_periods set unfrozen_until = now() + interval '48 hours',
  unfreeze_reason = 'Missed the rent', client_edited_at = now();
select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select is((select unfreeze_reason from budget_periods), 'Missed the rent',
  'the creator reopens it, and members see why');

select * from finish();
rollback;
