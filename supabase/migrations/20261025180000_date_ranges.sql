-- Every date within 1900-2199: the app reads four-digit years, and a walk from
-- a far date would never end.
alter table public.budget_periods
  add constraint start_date_range check (start_date between '1900-01-01' and '2199-12-31'),
  add constraint end_date_range check (end_date between '1900-01-01' and '2199-12-31'),
  add constraint anchor_date_range check (anchor_date between '1900-01-01' and '2199-12-31'),
  add constraint window_start_range check (window_start between '1900-01-01' and '2199-12-31'),
  add constraint window_end_range check (window_end between '1900-01-01' and '2199-12-31'),
  add constraint deadline_date_range check (deadline_date between '1900-01-01' and '2199-12-31');
alter table public.incomes
  add constraint expected_date_range check (expected_date between '1900-01-01' and '2199-12-31'),
  add constraint actual_date_range check (actual_date between '1900-01-01' and '2199-12-31');
alter table public.payments
  add constraint due_date_range check (due_date between '1900-01-01' and '2199-12-31');
