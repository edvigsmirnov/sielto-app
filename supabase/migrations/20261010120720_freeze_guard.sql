-- Arguments: the columns a frozen period protects. Fires after stamp_sync,
-- since triggers run in name order and the edit time must be clamped first.
create function private.freeze_guard() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  period public.budget_periods;
  freezes_at timestamptz;
  col text;
begin
  select * into period from public.budget_periods where id = old.budget_period_id;
  if period.end_date is null then
    return new;
  end if;
  select ((period.end_date + 15)::timestamp at time zone s.timezone)
    into freezes_at
    from public.spaces s where s.id = period.space_id;

  if new.client_edited_at < freezes_at
    and now() <= freezes_at + interval '7 days' then
    return new;
  end if;
  if period.unfrozen_until is not null
    and new.client_edited_at
      between period.unfrozen_until - interval '48 hours' and period.unfrozen_until
    and now() <= period.unfrozen_until + interval '7 days' then
    return new;
  end if;

  foreach col in array tg_argv loop
    if to_jsonb(new) -> col is distinct from to_jsonb(old) -> col then
      raise exception 'period_frozen' using detail = col;
    end if;
  end loop;
  if old.notes is not null
    and not starts_with(coalesce(new.notes, ''), old.notes) then
    raise exception 'period_frozen' using detail = 'notes';
  end if;
  return new;
end
$$;

create trigger sync_freeze_guard before update on public.payments
  for each row execute function private.freeze_guard(
    'amount', 'due_date', 'expense_type', 'is_paid', 'is_deleted');
create trigger sync_freeze_guard before update on public.incomes
  for each row execute function private.freeze_guard(
    'amount', 'expected_date', 'actual_date', 'is_paid', 'is_deleted');
