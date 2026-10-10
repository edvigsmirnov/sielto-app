begin;
select plan(7);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c');
insert into user_devices (auth_uid, user_id, device_id) values
  ('00000000-0000-4000-a000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c', '22222222-2222-4222-8222-222222222222',
   'dddddddd-dddd-4ddd-8ddd-00000000000c');
insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
values
  ('33333333-3333-4333-8333-333333333331', 'Mine', 'personal', 'flow',
   '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now()),
  ('33333333-3333-4333-8333-333333333332', 'Theirs', 'family', 'flow',
   '22222222-2222-4222-8222-222222222222', 'UTC', 'EUR', now(), now());
insert into space_members (space_id, user_id) values
  ('33333333-3333-4333-8333-333333333332', '11111111-1111-4111-8111-111111111111');
insert into user_profiles (user_id, nickname, client_edited_at) values
  ('11111111-1111-4111-8111-111111111111', 'Me', now()),
  ('22222222-2222-4222-8222-222222222222', 'Them', now());
insert into payments
  (id, space_id, title, amount, due_date, expense_type, created_at,
   client_edited_at)
values (gen_random_uuid(), '33333333-3333-4333-8333-333333333331', 'Rent',
  '100', current_date, 'mandatory', now(), now());

create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select delete_cloud_data();
reset role;

select is((select array_agg(title) from spaces), array['Theirs'],
  'only the caller''s own Spaces go');
select is((select count(*)::int from payments), 0, 'with their records');
select is((select array_agg(user_id) from space_members),
  array['22222222-2222-4222-8222-222222222222'::uuid],
  'the caller leaves other Spaces');
select is((select array_agg(nickname) from user_profiles), array['Them'],
  'the profile goes');
select is((select count(*)::int from user_devices
  where user_id = '11111111-1111-4111-8111-111111111111'), 0,
  'every device is unlinked');
select is((select count(*)::int from auth.users), 1,
  'and loses its sign-in');

set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select throws_ok($$ select delete_cloud_data() $$, 'P0001', 'not_registered',
  'a second call has nothing left');

select * from finish();
rollback;
