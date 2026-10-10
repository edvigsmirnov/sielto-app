alter table public.user_devices
  add constraint display_name_length check (length(display_name) <= 60);

create policy own_rename on public.user_devices for update to authenticated
  using (user_id = (select private.my_user_id()))
  with check (user_id = (select private.my_user_id()));
grant update (display_name) on public.user_devices to authenticated;

-- False once this device has been unlinked.
drop function public.touch_device();
create function public.touch_device(p_display_name text default null)
returns boolean
language sql security definer set search_path = ''
as $$
  with touched as (
    update public.user_devices
    set last_seen = now(), display_name = coalesce(display_name, p_display_name)
    where auth_uid = auth.uid()
    returning 1
  )
  select exists (select 1 from touched)
$$;

revoke execute on function public.touch_device from public, anon;
grant execute on function public.touch_device to authenticated;

-- Deleting the sign-in revokes its sessions and cascades to user_devices.
create function public.unlink_device(p_device_id uuid) returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users u using public.user_devices d
  where d.auth_uid = u.id
    and d.device_id = p_device_id
    and d.user_id = (select private.my_user_id())
    and d.auth_uid <> auth.uid()
$$;

create function public.unlink_other_devices() returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users u using public.user_devices d
  where d.auth_uid = u.id
    and d.user_id = (select private.my_user_id())
    and d.auth_uid <> auth.uid()
$$;

revoke execute on function public.unlink_device from public, anon;
grant execute on function public.unlink_device to authenticated;
revoke execute on function public.unlink_other_devices from public, anon;
grant execute on function public.unlink_other_devices to authenticated;

-- A user's most recently seen device always stays.
create function private.unlink_stale_devices() returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users u using public.user_devices d
  where d.auth_uid = u.id
    and d.last_seen < now() - interval '365 days'
    and exists (
      select 1 from public.user_devices o
      where o.user_id = d.user_id and o.last_seen > d.last_seen
    )
$$;

revoke execute on function private.unlink_stale_devices
  from public, anon, authenticated;

select cron.schedule('unlink_stale_devices', '30 3 * * *',
  'select private.unlink_stale_devices()');
