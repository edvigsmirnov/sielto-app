-- Each member's latest activity over all their devices, for fellow members.
create function public.member_activity(p_space_id uuid)
returns table (user_id uuid, last_seen timestamptz)
language sql stable security definer set search_path = ''
as $$
  select m.user_id, max(d.last_seen)
  from public.space_members m
  left join public.user_devices d on d.user_id = m.user_id
  where m.space_id = p_space_id
    and p_space_id in (select private.my_space_ids())
  group by m.user_id;
$$;

revoke all on function public.member_activity(uuid) from public, anon;
grant execute on function public.member_activity(uuid) to authenticated;
