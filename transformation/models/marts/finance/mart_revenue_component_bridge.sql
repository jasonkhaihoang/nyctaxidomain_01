-- Unpivots each trip total into its components so the walk from fare to total
-- is auditable line by line.
--
-- The residual is carried as its own component rather than being absorbed into
-- one of the real ones. If it is non-zero the walk does not balance, and that
-- is a finding about the source, not a rounding difference to bury.
with base as (
    select
        date_trunc('month', f.pickup_datetime)             as trip_month,
        f.service_type_key,
        z.borough_name,
        sum(f.fare_amount)                                 as c_fare,
        sum(f.tip_amount)                                  as c_tip,
        sum(f.tolls_amount)                                as c_tolls,
        sum(f.extra)                                       as c_extra,
        sum(f.mta_tax)                                     as c_mta_tax,
        sum(f.improvement_surcharge)                       as c_improvement,
        sum(f.congestion_surcharge)                        as c_congestion,
        sum(coalesce(f.airport_fee, 0))                    as c_airport_fee,
        sum(f.fare_residual)                               as c_residual,
        sum(f.total_amount)                                as total_amount,
        count(*)                                           as trip_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where {{ in_report_window('f.pickup_datetime') }}
      and f.is_billable
    group by 1,2,3
)

select trip_month, service_type_key, borough_name, trip_count, total_amount,
       component_name, component_order, component_amount,
       {{ safe_divide('component_amount', 'nullif(total_amount, 0)') }} as component_share
from base
unpivot (component_amount for component_name in (
    c_fare, c_tip, c_tolls, c_extra, c_mta_tax,
    c_improvement, c_congestion, c_airport_fee, c_residual
))
join (values
    ('c_fare', 1), ('c_tip', 2), ('c_tolls', 3), ('c_extra', 4),
    ('c_mta_tax', 5), ('c_improvement', 6), ('c_congestion', 7),
    ('c_airport_fee', 8), ('c_residual', 9)
) ord(name, component_order) on ord.name = component_name
