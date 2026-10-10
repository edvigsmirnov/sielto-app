begin;
select plan(6);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b');
insert into user_devices (auth_uid, user_id, device_id, last_seen) values
  ('00000000-0000-4000-a000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000a', now()),
  ('00000000-0000-4000-a000-00000000000b', '22222222-2222-4222-8222-222222222222',
   'dddddddd-dddd-4ddd-8ddd-00000000000b', now() - interval '30 days');

insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
values
  ('33333333-3333-4333-8333-333333333331', 'Solo', 'personal', 'flow',
   '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now()),
  ('33333333-3333-4333-8333-333333333332', 'Shared', 'family', 'flow',
   '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now());
insert into space_members (space_id, user_id) values
  ('33333333-3333-4333-8333-333333333332', '22222222-2222-4222-8222-222222222222');

insert into payments
  (id, space_id, title, amount, due_date, expense_type, created_at,
   client_edited_at)
select gen_random_uuid(), s, 'Rent', '100', d, 'mandatory', now(), now()
from unnest(array[
  '33333333-3333-4333-8333-333333333331'::uuid,
  '33333333-3333-4333-8333-333333333332'::uuid]) s,
  unnest(array[current_date - 40, current_date - 5]) d;
insert into incomes
  (id, space_id, title, amount, expected_date, created_at, client_edited_at)
values (gen_random_uuid(), '33333333-3333-4333-8333-333333333331', 'Salary',
  '3000', current_date - 40, now(), now());

select private.retention();

select is((select count(*)::int from payments
  where space_id = '33333333-3333-4333-8333-333333333331'), 1,
  'a payment older than 30 days leaves the server');
select is((select min(due_date) from payments
  where space_id = '33333333-3333-4333-8333-333333333331'), current_date - 5,
  'a recent payment stays');
select is((select count(*)::int from incomes), 0, 'old incomes leave as well');
select is((select count(*)::int from payments
  where space_id = '33333333-3333-4333-8333-333333333332'), 2,
  'a Space waits for a member away 20 to 90 days');

update user_devices set last_seen = now() - interval '100 days'
  where user_id = '22222222-2222-4222-8222-222222222222';
select private.retention();
select is((select count(*)::int from payments
  where space_id = '33333333-3333-4333-8333-333333333332'), 1,
  'after 90 days the wait ends');

select is((select count(*)::int from cron.job where jobname = 'retention'), 1,
  'the clean-up runs daily');

select * from finish();
rollback;
