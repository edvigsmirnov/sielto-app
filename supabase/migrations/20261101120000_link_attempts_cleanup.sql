-- The backoff caps at an hour; a day-old failure only keeps an IP address.
select cron.schedule(
  'link_attempts_cleanup',
  '45 3 * * *',
  $$delete from private.link_attempts where last_failure < now() - interval '1 day'$$
);
