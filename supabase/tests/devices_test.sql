begin;
select plan(11);

insert into auth.users (id) values
  ('00000000-0000-4000-a000-00000000000a'),
  ('00000000-0000-4000-a000-00000000000b'),
  ('00000000-0000-4000-a000-00000000000c'),
  ('00000000-0000-4000-a000-00000000000d'),
  ('00000000-0000-4000-a000-00000000000e'),
  ('00000000-0000-4000-a000-00000000000f');
insert into user_devices (auth_uid, user_id, device_id, display_name, last_seen)
values
  ('00000000-0000-4000-a000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000a', null, now()),
  ('00000000-0000-4000-a000-00000000000b', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000b', 'Tablet', now()),
  ('00000000-0000-4000-a000-00000000000c', '11111111-1111-4111-8111-111111111111',
   'dddddddd-dddd-4ddd-8ddd-00000000000c', 'Laptop', now()),
  ('00000000-0000-4000-a000-00000000000d', '22222222-2222-4222-8222-222222222222',
   'dddddddd-dddd-4ddd-8ddd-00000000000d', 'Stranger', now()),
  ('00000000-0000-4000-a000-00000000000e', '33333333-3333-4333-8333-333333333333',
   'dddddddd-dddd-4ddd-8ddd-00000000000e', 'Old', now() - interval '400 days'),
  ('00000000-0000-4000-a000-00000000000f', '33333333-3333-4333-8333-333333333333',
   'dddddddd-dddd-4ddd-8ddd-00000000000f', 'Older', now() - interval '500 days');

create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');

select ok(touch_device('Pixel 7'), 'a linked device is told so');
select is((select display_name from user_devices
  where auth_uid = '00000000-0000-4000-a000-00000000000a'), 'Pixel 7',
  'and a device with no name takes its model');
select ok(touch_device('Other'), 'touching again');
select is((select display_name from user_devices
  where auth_uid = '00000000-0000-4000-a000-00000000000a'), 'Pixel 7',
  'never overwrites a name');

update user_devices set display_name = 'Work laptop'
where device_id = 'dddddddd-dddd-4ddd-8ddd-00000000000c';
select is((select display_name from user_devices
  where device_id = 'dddddddd-dddd-4ddd-8ddd-00000000000c'), 'Work laptop',
  'a device renames another of its own');

select unlink_device('dddddddd-dddd-4ddd-8ddd-00000000000d');
select unlink_device('dddddddd-dddd-4ddd-8ddd-00000000000a');
select unlink_device('dddddddd-dddd-4ddd-8ddd-00000000000b');
select is((select array_agg(display_name order by display_name) from user_devices),
  array['Pixel 7', 'Work laptop']::text[], 'unlinking skips itself and strangers');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000b');
select ok(not touch_device(), 'an unlinked device is told so');

select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select unlink_other_devices();
select is((select count(*)::int from user_devices), 1,
  'unlinking the others leaves this device');

reset role;
select is((select count(*)::int from auth.users
  where id = '00000000-0000-4000-a000-00000000000b'), 0,
  'an unlinked device loses its sign-in');

select private.unlink_stale_devices();
select is((select array_agg(display_name) from user_devices
  where user_id = '33333333-3333-4333-8333-333333333333'), array['Old'],
  'a year away unlinks a device, except the most recent one');
select is((select count(*)::int from user_devices
  where user_id = '22222222-2222-4222-8222-222222222222'), 1,
  'an active device stays');

select * from finish();
rollback;
