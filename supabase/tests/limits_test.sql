begin;
select plan(5);

select lives_ok(
  $$ select '123456789012345.12345678'::public.money $$,
  'the largest amount passes'
);
select throws_ok(
  $$ select ('1' || repeat('0', 15))::public.money $$,
  '23514', null, 'sixteen whole digits are refused'
);
select lives_ok(
  $$ insert into public.user_profiles (user_id, nickname, client_edited_at)
     values ('00000000-0000-4000-a000-0000000000a1', repeat('a', 40), now()) $$,
  'a 40-character name passes'
);
select throws_ok(
  $$ insert into public.user_profiles (user_id, nickname, client_edited_at)
     values ('00000000-0000-4000-a000-0000000000a2', repeat('a', 41), now()) $$,
  '23514', null, 'a 41-character name is refused'
);
select throws_ok(
  $$ update public.user_profiles set nickname = repeat('a', 41)
     where user_id = '00000000-0000-4000-a000-0000000000a1' $$,
  '23514', null, 'and cannot be grown later'
);

select * from finish();
rollback;
