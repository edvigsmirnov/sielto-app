begin;
select plan(18);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c');
create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
create table pg_temp.codes (name text primary key, code text);
grant all on pg_temp.codes to authenticated;
set local role authenticated;

select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select throws_ok($$ select create_device_link_code() $$, 'P0001',
  'not_registered', 'an unregistered device cannot hand out a code');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select register_new_user(
  '11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-00000000000a');
insert into pg_temp.codes values ('first', create_device_link_code());
select matches((select code from pg_temp.codes where name = 'first'),
  '^[2-9A-HJKMNP-Z]{8}$', 'a code is eight characters without look-alikes');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select is(link_device_by_code(lower((select code from pg_temp.codes where name = 'first')),
  'dddddddd-dddd-4ddd-8ddd-00000000000b', 'pubkey-b', 'Pixel 7'), true,
  'the new device claims the code, whatever the case typed');
select is((select count(*)::int from user_devices
  where auth_uid = '00000000-0000-4000-a000-00000000000b'), 0,
  'but joins nothing before the owner allows it');
select is((select row(status, user_id)::text from device_link_claim()), '(claimed,)',
  'and does not learn the account yet');
select is((select count(*)::int from device_link_codes), 0,
  'nor can it read the code row');
select is(link_device_by_code((select code from pg_temp.codes where name = 'first'),
  'dddddddd-dddd-4ddd-8ddd-0000000000bb', 'pubkey'), null,
  'a claimed code cannot be claimed again');

reset role;
delete from private.link_attempts;
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select is((select ephemeral_pubkey || ' ' || claimant_name from device_link_codes),
  'pubkey-b Pixel 7', 'the owner sees the new device and its public key');
select throws_ok($$ update device_link_codes set encrypted_payload = 'sealed' $$,
  '42501', null, 'the owner cannot write the row directly');
select is(answer_device_link((select id from device_link_codes), true, 'sealed'), true,
  'the owner allows it with the sealed key');
select is((select user_id from user_devices
  where auth_uid = '00000000-0000-4000-a000-00000000000b'),
  '11111111-1111-4111-8111-111111111111'::uuid, 'and the device joins that user');
select is(answer_device_link((select id from device_link_codes), false), false,
  'an answer is given once');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select is((select row(status, user_id, encrypted_payload)::text from device_link_claim()),
  '(allowed,11111111-1111-4111-8111-111111111111,sealed)',
  'the new device then reads the account and the sealed key');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select is(link_device_by_code((select code from pg_temp.codes where name = 'first'),
  'dddddddd-dddd-4ddd-8ddd-00000000000c', 'pubkey-c'), null,
  'a code works once');
select is(link_device_by_code('WRONG234', 'dddddddd-dddd-4ddd-8ddd-00000000000c',
  'pubkey-c'), null, 'a wrong code is refused');
select link_device_by_code('WRONG345', 'dddddddd-dddd-4ddd-8ddd-00000000000c', 'k');
select throws_ok($$ select link_device_by_code('WRONG456',
  'dddddddd-dddd-4ddd-8ddd-00000000000c', 'k') $$, 'P0001', 'too_many_attempts',
  'after three wrong codes the caller waits');

reset role;
delete from private.link_attempts;
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
insert into pg_temp.codes values ('second', create_device_link_code());
reset role;
update device_link_codes set expires_at = now() - interval '1 second'
  where status = 'open';
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select is(link_device_by_code((select code from pg_temp.codes where name = 'second'),
  'dddddddd-dddd-4ddd-8ddd-00000000000c', 'pubkey-c'), null,
  'an expired code is refused');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
insert into pg_temp.codes values ('third', create_device_link_code());
select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select link_device_by_code((select code from pg_temp.codes where name = 'third'),
  'dddddddd-dddd-4ddd-8ddd-00000000000c', 'pubkey-c');
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select answer_device_link((select id from device_link_codes where status = 'claimed'), false);
select pg_temp.act_as('00000000-0000-4000-a000-00000000000c');
select is((select row(status, user_id)::text from device_link_claim()), '(refused,)',
  'a refused device learns only that');

select * from finish();
rollback;
