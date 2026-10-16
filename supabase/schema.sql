-- PrintOps initial schema for a fresh Supabase project.
-- Run the complete file in Supabase Dashboard -> SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.app_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'viewer' check (role in ('admin','editor','viewer')),
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null,
  target_quantity integer not null default 0 check (target_quantity >= 0),
  material text not null default 'PLA',
  weight_per_part_g numeric(12,2) not null default 0 check (weight_per_part_g >= 0),
  print_time_hours numeric(12,2) not null default 0 check (print_time_hours >= 0),
  infill_percent integer not null default 20 check (infill_percent between 0 and 100),
  wall_loops integer not null default 3 check (wall_loops >= 0),
  ironing boolean not null default false,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id, name)
);

create table if not exists public.print_jobs (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  source text not null check (source in ('internal','outside')),
  printer_name text check (printer_name is null or printer_name in ('P1','P2','P3','P4')),
  vendor_name text,
  planned_quantity integer not null check (planned_quantity > 0),
  completed_quantity integer not null default 0 check (completed_quantity >= 0),
  status text not null default 'queued' check (status in ('queued','printing','failed','completed','cancelled')),
  notes text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint print_job_assignment_check check (
    (source = 'internal' and printer_name is not null) or
    (source = 'outside' and printer_name is null)
  ),
  constraint completed_not_over_planned check (completed_quantity <= planned_quantity)
);

create index if not exists items_product_id_idx on public.items(product_id);
create index if not exists print_jobs_item_id_idx on public.print_jobs(item_id);
create index if not exists print_jobs_status_idx on public.print_jobs(status);
create unique index if not exists print_jobs_one_active_per_printer
  on public.print_jobs(printer_name)
  where source = 'internal' and status = 'printing' and printer_name is not null;

create or replace function public.current_app_role()
returns text
language sql stable security definer
set search_path = public
as $$
  select role from public.app_members where user_id = auth.uid() limit 1;
$$;

create or replace function public.is_app_member()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.app_members where user_id = auth.uid());
$$;

create or replace function public.can_edit_production()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() in ('admin','editor'), false);
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.normalize_print_job()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  if new.source = 'outside' then
    new.printer_name := null;
    if coalesce(trim(new.vendor_name), '') = '' then new.vendor_name := 'Fraxus'; end if;
  end if;
  if new.source = 'internal' then new.vendor_name := null; end if;
  if new.status = 'completed' then
    new.completed_quantity := new.planned_quantity;
    new.completed_at := coalesce(new.completed_at, now());
  elsif new.status = 'failed' then
    new.completed_quantity := 0;
    new.completed_at := null;
  else
    new.completed_quantity := greatest(0, least(coalesce(new.completed_quantity, 0), new.planned_quantity));
    new.completed_at := null;
  end if;
  if new.status = 'printing' and new.started_at is null then new.started_at := now(); end if;
  return new;
end;
$$;

drop trigger if exists app_members_after_insert_auth_user on auth.users;
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.app_members(user_id, email, role)
  values (new.id, coalesce(new.email, ''), 'viewer')
  on conflict (user_id) do update set email = excluded.email;
  return new;
end;
$$;
create trigger app_members_after_insert_auth_user
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

-- Keep updated_at fresh for edited master data.
drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products for each row execute procedure public.set_updated_at();
drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at before update on public.items for each row execute procedure public.set_updated_at();
drop trigger if exists print_jobs_normalize on public.print_jobs;
create trigger print_jobs_normalize before insert or update on public.print_jobs for each row execute procedure public.normalize_print_job();

alter table public.app_members enable row level security;
alter table public.products enable row level security;
alter table public.items enable row level security;
alter table public.print_jobs enable row level security;

drop policy if exists "members can read authorized member records" on public.app_members;
create policy "members can read authorized member records" on public.app_members
  for select to authenticated using (user_id = auth.uid() or public.current_app_role() = 'admin');
drop policy if exists "admins can update member roles" on public.app_members;
create policy "admins can update member roles" on public.app_members
  for update to authenticated using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');

drop policy if exists "members can read products" on public.products;
create policy "members can read products" on public.products for select to authenticated using (public.is_app_member());
drop policy if exists "editors can insert products" on public.products;
create policy "editors can insert products" on public.products for insert to authenticated with check (public.can_edit_production());
drop policy if exists "editors can update products" on public.products;
create policy "editors can update products" on public.products for update to authenticated using (public.can_edit_production()) with check (public.can_edit_production());
drop policy if exists "editors can delete products" on public.products;
create policy "editors can delete products" on public.products for delete to authenticated using (public.can_edit_production());

drop policy if exists "members can read items" on public.items;
create policy "members can read items" on public.items for select to authenticated using (public.is_app_member());
drop policy if exists "editors can insert items" on public.items;
create policy "editors can insert items" on public.items for insert to authenticated with check (public.can_edit_production());
drop policy if exists "editors can update items" on public.items;
create policy "editors can update items" on public.items for update to authenticated using (public.can_edit_production()) with check (public.can_edit_production());
drop policy if exists "editors can delete items" on public.items;
create policy "editors can delete items" on public.items for delete to authenticated using (public.can_edit_production());

drop policy if exists "members can read print jobs" on public.print_jobs;
create policy "members can read print jobs" on public.print_jobs for select to authenticated using (public.is_app_member());
drop policy if exists "editors can insert print jobs" on public.print_jobs;
create policy "editors can insert print jobs" on public.print_jobs for insert to authenticated with check (public.can_edit_production());
drop policy if exists "editors can update print jobs" on public.print_jobs;
create policy "editors can update print jobs" on public.print_jobs for update to authenticated using (public.can_edit_production()) with check (public.can_edit_production());
drop policy if exists "editors can delete print jobs" on public.print_jobs;
create policy "editors can delete print jobs" on public.print_jobs for delete to authenticated using (public.can_edit_production());

-- Seeded from the uploaded 3D_Printing_Status_Tracker(1).xlsx.
-- Current production-complete counts were not present in that workbook, so the app starts at 0 completed until jobs are marked complete.
insert into public.products(name, sort_order) values
  ('T4', 1), ('X4B', 2), ('X2C', 3), ('Lanyard Stand', 4)
on conflict (name) do update set sort_order = excluded.sort_order;

insert into public.items
  (product_id, name, target_quantity, material, weight_per_part_g, print_time_hours, infill_percent, wall_loops, ironing, notes)
select p.id, v.name, v.qty, v.material, v.weight_g, v.hours, v.infill, v.walls, v.ironing, v.notes
from (values
  ('T4','T4 Mask',1,'PLA',1845.0,48.0,25,6,false,''),
  ('T4','Fanfold Tray',10,'PLA',268.0,10.0,25,3,false,''),
  ('X4B','Front Cladding',28,'PLA',558.0,20.0,25,4,false,''),
  ('X4B','Roller Shutter Mount',35,'PLA',131.0,7.25,60,4,false,''),
  ('X4B','Roller Shutter',37,'PLA',127.0,7.0,60,4,false,''),
  ('X4B','Cap Cladding - 16 piece',4,'PLA',156.0,7.25,50,3,false,'Name and quantity preserved from workbook.'),
  ('X4B','Tablet Holder',30,'PLA',98.0,4.0,25,4,false,''),
  ('X2C','Front Cladding',68,'PLA',537.0,24.0,25,4,false,''),
  ('X2C','Tablet Holder',68,'PLA',108.0,4.3,40,4,false,''),
  ('X2C','Cap Cladding - 16 piece',8,'PLA',156.0,7.25,50,3,false,'Name and quantity preserved from workbook.'),
  ('Lanyard Stand','Flower',0,'Not set',0,0,20,3,false,'Quantity and print settings were not filled in the uploaded workbook.'),
  ('Lanyard Stand','Connect Joint',0,'Not set',0,0,20,3,false,'Quantity and print settings were not filled in the uploaded workbook.')
) as v(product_name,name,qty,material,weight_g,hours,infill,walls,ironing,notes)
join public.products p on p.name = v.product_name
on conflict (product_id, name) do nothing;
