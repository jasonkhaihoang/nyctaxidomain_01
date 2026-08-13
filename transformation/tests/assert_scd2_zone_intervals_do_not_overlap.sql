-- Overlapping validity intervals on a Type 2 dimension multiply every fact row
-- that joins them. This asserts the half-open intervals tile cleanly per
-- natural key.
with ranked as (
    select zone_natural_key, valid_from_date, valid_to_date,
           lead(valid_from_date) over (
               partition by zone_natural_key order by valid_from_date
           ) as next_from
    from {{ ref('dim_zone') }}
)
select * from ranked
where next_from is not null and valid_to_date > next_from
