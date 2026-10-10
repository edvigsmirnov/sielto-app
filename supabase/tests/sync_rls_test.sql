begin;
select plan(17);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b');

create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select lives_ok($$ select register_new_user(
  '11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-00000000000a') $$,
  'a device registers its user id');
select lives_ok($$ select register_new_user(
  '11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-00000000000a') $$,
  'registering again is a no-op');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select throws_ok($$ select register_new_user(
  '11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-00000000000b') $$,
  'user_id_taken');
select lives_ok($$ select register_new_user(
  '22222222-2222-4222-8222-222222222222', 'dddddddd-dddd-4ddd-8ddd-00000000000b') $$,
  'another device registers another user');
select throws_ok($$ insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
  values ('55555555-5555-4555-8555-555555555555', 'Fake', 'personal', 'flow',
   '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now()) $$,
  '42501', null, 'nobody creates a Space for someone else');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
values ('33333333-3333-4333-8333-333333333333', 'Home', 'personal', 'flow',
  '11111111-1111-4111-8111-111111111111', 'Europe/Berlin', 'EUR', now(),
  now() + interval '1 day');
select results_eq($$ select user_id from space_members $$,
  $$ values ('11111111-1111-4111-8111-111111111111'::uuid) $$,
  'the owner becomes a member');
select ok((select client_edited_at <= now() from spaces),
  'a future edit time is clamped to now');

insert into payments
  (id, space_id, title, amount, due_date, expense_type, created_at,
   client_edited_at, last_modified_by)
values ('44444444-4444-4444-8444-444444444444',
  '33333333-3333-4333-8333-333333333333', 'Rent', '1200.00', '2026-10-01',
  'mandatory', now(), now() - interval '1 hour',
  '22222222-2222-4222-8222-222222222222');
select is((select last_modified_by from payments),
  '11111111-1111-4111-8111-111111111111'::uuid,
  'the author is set by the server');
select throws_ok($$ update spaces set owner_id = '22222222-2222-4222-8222-222222222222' $$,
  '42501', null, 'the owner cannot be changed');
select throws_ok($$ insert into payments
  (id, space_id, title, amount, due_date, expense_type, created_at, client_edited_at)
  values (gen_random_uuid(), '33333333-3333-4333-8333-333333333333', 'Bad',
   '-5', '2026-10-01', 'variable', now(), now()) $$,
  '23514', null, 'a negative amount is refused');

update payments set amount = '999', client_edited_at = now() - interval '2 hours';
select is((select amount::text from payments), '1200.00', 'an older edit loses');
update payments set amount = '1300', client_edited_at = now();
select is((select amount::text from payments), '1300', 'a newer edit wins');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select is_empty($$ select 1 from spaces $$, 'a stranger sees no Space');
select is_empty($$ select 1 from payments $$, 'a stranger sees no payment');
select throws_ok($$ insert into payments
  (id, space_id, title, amount, due_date, expense_type, created_at, client_edited_at)
  values (gen_random_uuid(), '33333333-3333-4333-8333-333333333333', 'Spy', '1',
   '2026-10-01', 'variable', now(), now()) $$,
  '42501', null, 'a stranger cannot write into a Space');

reset role;
insert into space_members (space_id, user_id) values
  ('33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222');
set local role authenticated;
select isnt_empty($$ select 1 from payments $$, 'a member sees the payments');

set local role anon;
select throws_ok($$ select 1 from payments $$, '42501', null,
  'the anonymous API role reads nothing');

select * from finish();
rollback;
