-- An unknown zone would stop every Space's nightly retention.
create function private.refuse_unknown_timezone() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'unknown_timezone' using errcode = '22023';
  end if;
  return new;
end $$;

create trigger known_timezone before insert or update of timezone on public.spaces
  for each row execute function private.refuse_unknown_timezone();
