-- Run once in the Supabase SQL editor. Safe to run again.
--
-- Mirrors the local SQLite tables. `user_id` scopes every row to the signed-in
-- user; `server_at` is the pull cursor; timestamps written by the apps are
-- fixed-width UTC strings, so comparing them as text is correct.

create or replace function todo_stamp() returns trigger language plpgsql set search_path = '' as $$
begin
  -- Last write wins: drop an update that is older than the stored row.
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.server_at := clock_timestamp();
  return new;
end $$;

do $$
declare
  t text;
  extra text;
begin
  for t, extra in values
    ('lists', 'title text not null'),
    ('tasks', 'list_id text, title text not null, notes text, tag text, date text,
               start_time text, end_time text, done_at text, calendar_event_id text'),
    ('habits', 'title text not null, time text, start_date text, end_date text, sort integer not null default 0'),
    ('habit_checks', 'habit_id text not null, date text not null, done integer not null'),
    ('focus_sessions', 'task_id text, kind text not null, started_at text not null,
                        planned_min integer not null, ended_at text')
  loop
    execute format('create table if not exists %I (
      id text primary key,
      user_id uuid not null default auth.uid() references auth.users on delete cascade,
      %s,
      created_at text not null,
      updated_at text not null,
      deleted_at text,
      server_at timestamptz not null default clock_timestamp()
    )', t, extra);
    execute format('create index if not exists %I on %I (user_id, server_at)', t || '_pull', t);
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists own_rows on %I', t);
    execute format('create policy own_rows on %I for all to authenticated
      using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('drop trigger if exists stamp on %I', t);
    execute format('create trigger stamp before insert or update on %I
      for each row execute function todo_stamp()', t);
  end loop;
end $$;

-- Added after the first release.
alter table habits add column if not exists time text;
