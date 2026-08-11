-- Finance's headline table, in the Monday revenue pack.
--
-- The billable rule (ADR 0002) is applied here, in gold, and nowhere upstream,
-- so data-quality work can still see the rows this excludes.
select
    f.pickup_date                                          as trip_date,
    z.zone_natural_key                                     as pickup_location_id,
    z.borough_name                                         as borough,
    z.zone_name,
    z.reporting_region,
    count(*)                                               as trip_count,
    sum(f.fare_amount)                                     as fare_revenue,
    sum(f.tip_amount)                                      as tip_revenue,
    sum(f.total_surcharges)                                as surcharge_revenue,
    sum(f.tolls_amount)                                    as toll_revenue,
    sum(f.total_amount)                                    as total_revenue
from {{ ref('fct_trip') }} f
join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
where {{ in_report_window('f.pickup_datetime') }}
  and f.is_billable
group by 1,2,3,4,5
