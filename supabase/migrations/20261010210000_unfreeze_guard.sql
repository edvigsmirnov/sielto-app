-- Only the creator reopens a period: at most 48 hours, always with a reason.
create function private.guard_unfreeze() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if (new.unfrozen_until is distinct from old.unfrozen_until
      or new.unfreeze_reason is distinct from old.unfreeze_reason)
      and private.my_user_id() is not null then
    if not exists (select 1 from public.spaces
        where id = new.space_id and owner_id = private.my_user_id()) then
      raise exception 'not_owner';
    end if;
    if new.unfrozen_until is not null and (
        new.unfrozen_until > now() + interval '48 hours 5 minutes'
        or length(trim(coalesce(new.unfreeze_reason, ''))) = 0) then
      raise exception 'bad_unfreeze';
    end if;
  end if;
  return new;
end
$$;

create trigger sync_unfreeze_guard before update on public.budget_periods
  for each row execute function private.guard_unfreeze();
