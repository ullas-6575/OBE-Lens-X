-- Ensure every course has the six fixed CO rows used by exam mapping.
-- Existing descriptions and PO links are retained; extra legacy CO rows remain.
begin;

with normalized as (
  select c.id,
    (
      select jsonb_agg(rows.outcome order by rows.sort_order)
      from (
        select n as sort_order,
          coalesce(
            (
              select existing.value
              from jsonb_array_elements(c.outcomes) as existing(value)
              where existing.value->>'code' = 'CO' || n::text
              limit 1
            ),
            jsonb_build_object(
              'code', 'CO' || n::text,
              'description', 'CO' || n::text,
              'pos', '[]'::jsonb
            )
          ) as outcome
        from generate_series(1, 6) as series(n)

        union all

        select 6 + row_number() over (order by existing.value->>'code') as sort_order,
          existing.value as outcome
        from jsonb_array_elements(c.outcomes) as existing(value)
        where coalesce(existing.value->>'code', '') !~ '^CO[1-6]$'
      ) as rows
    ) as outcomes
  from public.courses as c
)
update public.courses as c
set outcomes = normalized.outcomes
from normalized
where c.id = normalized.id
  and c.outcomes is distinct from normalized.outcomes;

commit;
