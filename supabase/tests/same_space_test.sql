begin;
select plan(3);

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
values
  ('33333333-3333-4333-8333-333333333333', 'Home', 'personal', 'flow',
   '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'Trip', 'trip', 'flow',
   '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now());

insert into categories (id, space_id, title, created_at, client_edited_at)
values ('c0000000-0000-4000-8000-000000000001',
  '44444444-4444-4444-8444-444444444444', 'Hotels', now(), now());

select throws_ok($$ insert into payments
  (id, space_id, category_id, title, amount, due_date, expense_type, created_at,
   client_edited_at)
  values ('b0000000-0000-4000-8000-000000000001',
   '33333333-3333-4333-8333-333333333333', 'c0000000-0000-4000-8000-000000000001',
   'Rent', '100', '2026-01-05', 'variable', now(), now()) $$,
  '23503', null, 'a category of another Space is refused');
select lives_ok($$ insert into payments
  (id, space_id, category_id, title, amount, due_date, expense_type, created_at,
   client_edited_at)
  values ('b0000000-0000-4000-8000-000000000002',
   '44444444-4444-4444-8444-444444444444', 'c0000000-0000-4000-8000-000000000001',
   'Hotel', '100', '2026-01-05', 'variable', now(), now()) $$,
  'its own Space''s category passes');
select lives_ok($$ insert into payments
  (id, space_id, title, amount, due_date, expense_type, created_at,
   client_edited_at)
  values ('b0000000-0000-4000-8000-000000000003',
   '33333333-3333-4333-8333-333333333333', 'Bread', '2', '2026-01-05',
   'variable', now(), now()) $$,
  'no category passes');

select * from finish();
rollback;
