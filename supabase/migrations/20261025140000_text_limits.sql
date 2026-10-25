-- Upper bounds on what one member can make every other member download.
-- The app's own limits are TextLimits in lib/core/ui/form_fields.dart.
alter domain public.money drop constraint money_check;
alter domain public.money add constraint money_check
  check (value ~ '^[0-9]{1,15}(\.[0-9]{1,8})?$');

alter table public.spaces
  add constraint title_length check (length(title) <= 100),
  add constraint country_code_length check (length(country_code) <= 8),
  add constraint timezone_length check (length(timezone) <= 64),
  add constraint currency_code_length check (length(currency_code) <= 8);

alter table public.user_profiles
  add constraint nickname_length check (length(nickname) <= 40);

alter table public.member_local_labels
  add constraint local_name_length check (length(local_name) <= 40),
  add constraint local_role_length check (length(local_role) <= 40);

alter table public.categories
  add constraint title_length check (length(title) <= 100),
  add constraint color_length check (length(color) <= 16),
  add constraint icon_length check (length(icon) <= 32),
  add constraint starter_key_length check (length(starter_key) <= 40);

alter table public.budget_periods
  add constraint unfreeze_reason_length check (length(unfreeze_reason) <= 500);

alter table public.income_recurrence_rules
  add constraint title_length check (length(title) <= 100),
  add constraint country_code_length check (length(country_code) <= 8);

alter table public.incomes
  add constraint title_length check (length(title) <= 100),
  add constraint notes_length check (length(notes) <= 5000);

alter table public.payments
  add constraint title_length check (length(title) <= 100),
  add constraint notes_length check (length(notes) <= 5000);
