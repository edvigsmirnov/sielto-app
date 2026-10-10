begin;
select plan(17);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c');
insert into user_devices (auth_uid, user_id, device_id) values
  ('00000000-0000-4000-a000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b', '22222222-2222-4222-8222-222222222222',
   'dddddddd-dddd-4ddd-8ddd-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c', '33333333-3333-4333-8333-333333333333',
   'dddddddd-dddd-4ddd-8ddd-00000000000c');
insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   max_members, created_at, client_edited_at)
values ('44444444-4444-4444-8444-444444444444', 'Family', 'family', 'flow',
  '11111111-1111-4111-8111-111111111111', 'UTC', 'EUR', 0, now(), now());

create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
create table pg_temp.codes (name text primary key, code text);
grant all on pg_temp.codes to authenticated;
set local role authenticated;

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select throws_ok($$ select create_space_invite('44444444-4444-4444-8444-444444444444') $$,
  'P0001', 'space_full', 'a limit of 0 means no invites');
update spaces set max_members = 2, client_edited_at = now();
insert into pg_temp.codes values ('first',
  create_space_invite('44444444-4444-4444-8444-444444444444'));
select matches((select code from pg_temp.codes where name = 'first'),
  '^[2-9A-HJKMNP-Z]{8}$', 'an invite is eight characters without look-alikes');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select is((select count(*)::int from space_invites), 0,
  'only the owner sees invites');
select throws_ok($$ select create_space_invite('44444444-4444-4444-8444-444444444444') $$,
  'P0001', 'not_owner', 'and only the owner makes them');
select is(join_space_by_token('WRONG234'), null, 'a wrong code joins nothing');
select is(join_space_by_token(lower((select code from pg_temp.codes where name = 'first'))),
  '44444444-4444-4444-8444-444444444444'::uuid, 'the right code joins the Space');
select is((select title from spaces), 'Family', 'and the Space becomes visible');
select is(join_space_by_token((select code from pg_temp.codes where name = 'first')),
  null, 'a code works once');

update spaces set max_members = 9, client_edited_at = now();
select is((select max_members from spaces), 2, 'a member cannot change the limit');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select throws_ok($$ select create_space_invite('44444444-4444-4444-8444-444444444444') $$,
  'P0001', 'space_full', 'a full Space takes no more invites');
select throws_ok($$ update spaces set max_members = 1, client_edited_at = now() $$,
  'P0001', 'below_members', 'the limit never drops below the members');
select throws_ok($$ select leave_space('44444444-4444-4444-8444-444444444444') $$,
  'P0001', 'owner_cannot_leave', 'the owner hands over before leaving');

select transfer_ownership('44444444-4444-4444-8444-444444444444',
  '22222222-2222-4222-8222-222222222222');
select is((select owner_id from spaces),
  '22222222-2222-4222-8222-222222222222'::uuid, 'ownership moves to a member');
select leave_space('44444444-4444-4444-8444-444444444444');
select is((select count(*)::int from spaces), 0, 'a member who leaves loses the Space');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
update spaces set max_members = 3, client_edited_at = now();
insert into pg_temp.codes values ('second',
  create_space_invite('44444444-4444-4444-8444-444444444444'));
select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select is(join_space_by_token((select code from pg_temp.codes where name = 'second')),
  '44444444-4444-4444-8444-444444444444'::uuid, 'the new owner invites');
select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select remove_member('44444444-4444-4444-8444-444444444444',
  '33333333-3333-4333-8333-333333333333');
select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select is((select count(*)::int from spaces), 0, 'a removed member loses the Space');
select throws_ok($$ select remove_member('44444444-4444-4444-8444-444444444444',
  '22222222-2222-4222-8222-222222222222') $$,
  'P0001', 'not_owner', 'only the owner removes members');

select * from finish();
rollback;
