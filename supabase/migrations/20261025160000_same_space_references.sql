-- A record may only point at a category, period or rule of its own Space:
-- a foreign one is missing on the other members' devices and stops their sync.
alter table public.categories add constraint categories_id_space unique (id, space_id);
alter table public.budget_periods add constraint budget_periods_id_space unique (id, space_id);
alter table public.income_recurrence_rules add constraint income_recurrence_rules_id_space unique (id, space_id);

alter table public.payments
  drop constraint payments_category_id_fkey,
  drop constraint payments_budget_period_id_fkey,
  add constraint payments_category_id_fkey foreign key (category_id, space_id)
    references public.categories (id, space_id),
  add constraint payments_budget_period_id_fkey foreign key (budget_period_id, space_id)
    references public.budget_periods (id, space_id);

alter table public.incomes
  drop constraint incomes_budget_period_id_fkey,
  drop constraint incomes_recurrence_rule_id_fkey,
  add constraint incomes_budget_period_id_fkey foreign key (budget_period_id, space_id)
    references public.budget_periods (id, space_id),
  add constraint incomes_recurrence_rule_id_fkey foreign key (recurrence_rule_id, space_id)
    references public.income_recurrence_rules (id, space_id);
