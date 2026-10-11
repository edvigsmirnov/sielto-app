begin;
select plan(3);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c');
insert into user_devices (auth_uid, user_id, device_id, last_seen) values
  ('00000000-0000-4000-a000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000a', now()),
  ('00000000-0000-4000-a000-00000000000b', '22222222-2222-4222-8222-222222222222',
   'dddddddd-dddd-4ddd-8ddd-00000000000b', now() - interval '95 days'),
  ('00000000-0000-4000-a000-00000000000c', '99999999-9999-4999-8999-999999999999',
   'dddddddd-dddd-4ddd-8ddd-00000000000c', now());
insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
values ('33333333-3333-4333-8333-333333333333', 'Family', 'family', 'incomeDriven',
  '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', now(), now());
insert into space_members (space_id, user_id) values
  ('33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222');

create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
set local role authenticated;

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select is((select count(*) from member_activity('33333333-3333-4333-8333-333333333333')),
  2::bigint, 'every member is listed');
select ok((select last_seen < now() - interval '90 days' from member_activity(
  '33333333-3333-4333-8333-333333333333')
  where user_id = '22222222-2222-4222-8222-222222222222'), 'with their latest activity');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select is((select count(*) from member_activity('33333333-3333-4333-8333-333333333333')),
  0::bigint, 'an outsider sees nothing');

select * from finish();
rollback;
