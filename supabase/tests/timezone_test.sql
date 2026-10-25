begin;
select plan(2);

insert into auth.users (id) values ('00000000-0000-4000-a000-00000000000a');
create function pg_temp.act_as(auth_uid text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', auth_uid, 'role', 'authenticated')::text, true);
$$;
set local role authenticated;
select pg_temp.act_as('00000000-0000-4000-a000-00000000000a');
select register_new_user(
  '11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-00000000000a');

select lives_ok($$ insert into spaces
  (id, title, space_type, budget_mode, owner_id, timezone, currency_code,
   created_at, client_edited_at)
  values ('33333333-3333-4333-8333-333333333333', 'Home', 'personal', 'flow',
   '11111111-1111-4111-8111-111111111111', 'Europe/Berlin', 'EUR', now(), now()) $$,
  'a known zone passes');
select throws_ok($$ update spaces set timezone = 'Mars/Phobos', client_edited_at = now()
  where id = '33333333-3333-4333-8333-333333333333' $$,
  '22023', 'unknown_timezone', 'an unknown zone is refused');

select * from finish();
rollback;
