create function public.touch_device() returns void
language sql security definer set search_path = ''
as $$ update public.user_devices set last_seen = now() where auth_uid = auth.uid() $$;

revoke execute on function public.touch_device from public, anon;
grant execute on function public.touch_device to authenticated;

-- Keeps 30 days of payments and incomes per Space, in the Space's own today.
-- A Space waits while a member has been away for 20 to 90 days.
create function private.retention() returns void
language sql security definer set search_path = ''
as $$
  with eligible as (
    select s.id, (now() at time zone s.timezone)::date - 30 as cutoff
    from public.spaces s
    where not exists (
      select 1 from public.space_members sm
      where sm.space_id = s.id
        and (select max(d.last_seen) from public.user_devices d
             where d.user_id = sm.user_id)
          between now() - interval '90 days' and now() - interval '20 days'
    )
  ),
  old_payments as (
    delete from public.payments p using eligible e
    where p.space_id = e.id and p.due_date < e.cutoff
  )
  delete from public.incomes i using eligible e
  where i.space_id = e.id and i.expected_date < e.cutoff;
$$;

revoke execute on function private.retention from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('retention', '15 3 * * *', 'select private.retention()');
