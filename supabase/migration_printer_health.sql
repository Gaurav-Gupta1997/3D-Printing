-- PrintOps printer condition management migration.
-- Run once in Supabase Dashboard -> SQL Editor for an existing PrintOps database.
-- Safe to re-run: table, policies, triggers and seed values are idempotent.

create table if not exists public.printers (
  name text primary key check (name in ('P1','P2','P3','P4')),
  operational_status text not null default 'working'
    check (operational_status in ('working','maintenance','out_of_order')),
  notes text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

insert into public.printers(name, operational_status)
values ('P1','working'), ('P2','working'), ('P3','working'), ('P4','working')
on conflict (name) do nothing;

create or replace function public.set_printer_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists printers_set_updated_at on public.printers;
create trigger printers_set_updated_at
before update on public.printers
for each row execute procedure public.set_printer_updated_at();

create or replace function public.prevent_unavailable_printer_with_active_job()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.operational_status <> 'working' and exists (
    select 1 from public.print_jobs j
    where j.source = 'internal'
      and j.printer_name = new.name
      and j.status = 'printing'
  ) then
    raise exception 'Printer % has a job marked Printing. Pause or fail that job before changing printer condition.', new.name
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists printers_guard_active_job on public.printers;
create trigger printers_guard_active_job
before update of operational_status on public.printers
for each row execute procedure public.prevent_unavailable_printer_with_active_job();

create or replace function public.prevent_printing_on_unavailable_printer()
returns trigger language plpgsql set search_path = public as $$
declare printer_health text;
begin
  if new.source = 'internal' and new.status = 'printing' then
    select operational_status into printer_health
    from public.printers where name = new.printer_name;
    if printer_health is distinct from 'working' then
      raise exception 'Printer % is not marked Working. Choose another printer or update its condition first.', coalesce(new.printer_name, '(unassigned)')
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists print_jobs_check_printer_health on public.print_jobs;
create trigger print_jobs_check_printer_health
before insert or update of source, printer_name, status on public.print_jobs
for each row execute procedure public.prevent_printing_on_unavailable_printer();

alter table public.printers enable row level security;
revoke all on table public.printers from anon, authenticated;
grant select, update on table public.printers to authenticated;

drop policy if exists "members can read printer status" on public.printers;
create policy "members can read printer status" on public.printers
  for select to authenticated using (public.is_app_member());
drop policy if exists "editors can update printer status" on public.printers;
create policy "editors can update printer status" on public.printers
  for update to authenticated using (public.can_edit_production()) with check (public.can_edit_production());
