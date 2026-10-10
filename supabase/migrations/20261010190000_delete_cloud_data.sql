-- Right to erasure: everything the server holds for the caller's user,
-- then every device's sign-in.
create function public.delete_cloud_data() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := private.my_user_id();
begin
  if me is null then
    raise exception 'not_registered';
  end if;
  delete from public.spaces where owner_id = me;
  delete from public.space_members where user_id = me;
  delete from public.member_local_labels
  where viewer_user_id = me or target_user_id = me;
  delete from public.user_profiles where user_id = me;
  delete from auth.users u using public.user_devices d
  where d.auth_uid = u.id and d.user_id = me;
end
$$;

revoke execute on function public.delete_cloud_data from public, anon;
grant execute on function public.delete_cloud_data to authenticated;
