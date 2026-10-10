begin;
select plan(10);

insert into auth.users (id) values ('00000000-0000-4000-a000-00000000000a');
create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select register_new_user(
  '11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-00000000000a');

insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
values ('33333333-3333-4333-8333-333333333333', 'Home', 'personal',
  'incomeDriven', '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(),
  now());

-- Long frozen; frozen since yesterday (in grace); unfrozen right now.
insert into budget_periods
  (id, space_id, period_type, start_date, end_date, unfrozen_until, created_at,
   client_edited_at)
values
  ('a0000000-0000-4000-8000-000000000001', '33333333-3333-4333-8333-333333333333',
   'incomeDriven', '2026-01-01', '2026-01-31', null, now(), now()),
  ('a0000000-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333',
   'incomeDriven', current_date - 46, current_date - 16, null, now(), now()),
  ('a0000000-0000-4000-8000-000000000003', '33333333-3333-4333-8333-333333333333',
   'incomeDriven', '2025-12-01', '2025-12-31', now() + interval '1 hour', now(),
   now());

insert into payments
  (id, space_id, budget_period_id, title, amount, due_date, expense_type, notes,
   created_at, client_edited_at)
values
  ('b0000000-0000-4000-8000-000000000001', '33333333-3333-4333-8333-333333333333',
   'a0000000-0000-4000-8000-000000000001', 'Rent', '1200', '2026-01-05',
   'mandatory', 'Paid in cash', now(), now() - interval '20 days'),
  ('b0000000-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333',
   'a0000000-0000-4000-8000-000000000002', 'Rent', '1200', current_date - 40,
   'mandatory', null, now(), now() - interval '20 days'),
  ('b0000000-0000-4000-8000-000000000003', '33333333-3333-4333-8333-333333333333',
   'a0000000-0000-4000-8000-000000000003', 'Rent', '1200', '2025-12-05',
   'mandatory', null, now(), now() - interval '20 days');

select throws_ok($$ update payments set amount = '1300', client_edited_at = now()
  where id = 'b0000000-0000-4000-8000-000000000001' $$,
  'P0001', 'period_frozen', 'a frozen amount is refused');
select throws_ok($$ update payments set is_deleted = true, client_edited_at = now()
  where id = 'b0000000-0000-4000-8000-000000000001' $$,
  'P0001', 'period_frozen', 'a frozen record cannot be deleted');
update payments set amount = '1300', client_edited_at = '2026-02-01'
  where id = 'b0000000-0000-4000-8000-000000000001';
select is((select amount::text from payments
  where id = 'b0000000-0000-4000-8000-000000000001'), '1200',
  'a backdated edit time does not get past the freeze');
select lives_ok($$ update payments set title = 'Flat', sort_order = 5,
  client_edited_at = now() where id = 'b0000000-0000-4000-8000-000000000001' $$,
  'title and order stay editable');
select lives_ok($$ update payments
  set notes = notes || E'\n---\n[added 2026-10-10]: Receipt found',
  client_edited_at = now() where id = 'b0000000-0000-4000-8000-000000000001' $$,
  'a note can be appended');
select throws_ok($$ update payments set notes = 'Rewritten',
  client_edited_at = now() where id = 'b0000000-0000-4000-8000-000000000001' $$,
  'P0001', 'period_frozen', 'a note cannot be rewritten');

update payments set amount = '1250', client_edited_at = now() - interval '2 days'
  where id = 'b0000000-0000-4000-8000-000000000002';
select is((select amount::text from payments
  where id = 'b0000000-0000-4000-8000-000000000002'), '1250',
  'an edit made before the freeze lands within the grace window');
select throws_ok($$ update payments set amount = '1270', client_edited_at = now()
  where id = 'b0000000-0000-4000-8000-000000000002' $$,
  'P0001', 'period_frozen', 'an edit made after the freeze is refused');

update payments set amount = '1100', client_edited_at = now()
  where id = 'b0000000-0000-4000-8000-000000000003';
select is((select amount::text from payments
  where id = 'b0000000-0000-4000-8000-000000000003'), '1100',
  'an unfrozen period takes edits');

select is((select amount::text from payments
  where id = 'b0000000-0000-4000-8000-000000000001'), '1200',
  'the frozen amount is unchanged');

select * from finish();
rollback;
