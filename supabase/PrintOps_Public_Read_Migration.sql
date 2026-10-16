-- PrintOps public read-only dashboard migration.
-- Run once in Supabase Dashboard -> SQL Editor for the existing project.
-- Public (signed-out) visitors can read operational fields only.
-- Writes remain restricted to authenticated app_members with editor/admin roles.

begin;

-- Required for the anonymous client to query explicitly granted objects in the API schema.
grant usage on schema public to anon;

-- Never expose the workspace membership/invitation list to anonymous visitors.
alter table public.app_members enable row level security;
revoke all on table public.app_members from anon;

alter table public.products enable row level security;
alter table public.items enable row level security;
alter table public.print_jobs enable row level security;
alter table public.printers enable row level security;

-- Remove broad anonymous table grants, then grant only the columns needed by the public dashboard.
-- This intentionally omits notes, member emails, user IDs, and audit/editor fields.
revoke all on table public.products from anon;
revoke all on table public.items from anon;
revoke all on table public.print_jobs from anon;
revoke all on table public.printers from anon;

grant select (id, name, sort_order) on table public.products to anon;
grant select (id, product_id, name, target_quantity, material, weight_per_part_g, print_time_hours, infill_percent, wall_loops, ironing, created_at)
  on table public.items to anon;
grant select (id, item_id, source, printer_name, vendor_name, planned_quantity, completed_quantity, status, created_at)
  on table public.print_jobs to anon;
grant select (name, operational_status) on table public.printers to anon;

-- Explicitly keep all anonymous mutations unavailable.
revoke insert, update, delete, truncate, references, trigger on table public.products from anon;
revoke insert, update, delete, truncate, references, trigger on table public.items from anon;
revoke insert, update, delete, truncate, references, trigger on table public.print_jobs from anon;
revoke insert, update, delete, truncate, references, trigger on table public.printers from anon;

drop policy if exists "public visitors can view products" on public.products;
create policy "public visitors can view products"
  on public.products for select to anon using (true);

drop policy if exists "public visitors can view production items" on public.items;
create policy "public visitors can view production items"
  on public.items for select to anon using (true);

drop policy if exists "public visitors can view print jobs" on public.print_jobs;
create policy "public visitors can view print jobs"
  on public.print_jobs for select to anon using (true);

drop policy if exists "public visitors can view printer condition" on public.printers;
create policy "public visitors can view printer condition"
  on public.printers for select to anon using (true);

commit;
