create table public.results (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  submission_id uuid not null,
  roll_no text not null check (length(btrim(roll_no)) > 0),
  table_type text not null check (table_type in ('1-4', '5-8')),
  marks jsonb not null check (jsonb_typeof(marks) = 'object'),
  grand_total numeric(7, 2) not null check (grand_total >= 0),
  image_path text,
  created_at timestamptz not null default now(),
  unique (teacher_id, submission_id)
);

create index results_teacher_created_at_idx
  on public.results (teacher_id, created_at desc);

create index results_teacher_roll_no_idx
  on public.results (teacher_id, roll_no);

alter table public.results enable row level security;

revoke all on public.results from anon;
grant select, insert on public.results to authenticated;

create policy "Teachers can read their own results"
  on public.results
  for select
  to authenticated
  using (teacher_id = (select auth.uid()));

create policy "Teachers can insert their own results"
  on public.results
  for insert
  to authenticated
  with check (teacher_id = (select auth.uid()));
