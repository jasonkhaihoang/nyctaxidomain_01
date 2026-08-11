-- Driver-month, built from driver-day rather than from shifts again. Building
-- each level from the one below is what keeps the pyramid consistent: if the
-- month disagreed with the sum of its days, one of them would be wrong and
-- nobody would know which.
select
    date_trunc('month', a.shift_date)                      as month_start_date,
    a.driver_key,
    a.driver_ref,
    a.engagement_type,
    a.garage_key,
    a.home_garage_name,

    count(*)                                               as active_days,
    sum(a.shift_count)                                     as shift_count,
    sum(a.trip_count)                                      as trip_count,
    sum(a.online_hours)                                    as online_hours,
    sum(a.on_trip_hours)                                   as on_trip_hours,
    sum(a.gross_revenue)                                   as gross_revenue,
    sum(a.tip_revenue)                                     as tip_revenue,
    sum(a.total_cost)                                      as total_cost,
    sum(a.total_margin)                                    as total_margin,
    sum(a.paid_miles)                                      as paid_miles,

    {{ safe_divide('sum(a.on_trip_hours)', 'nullif(sum(a.online_hours), 0)') }}   as occupancy_rate,
    {{ safe_divide('sum(a.gross_revenue)', 'nullif(sum(a.online_hours), 0)') }}   as revenue_per_online_hour,
    {{ safe_divide('sum(a.trip_count)::double', 'nullif(sum(a.online_hours), 0)') }} as trips_per_online_hour,
    {{ safe_divide('sum(a.total_margin)', 'nullif(sum(a.gross_revenue), 0)') }}   as margin_rate
from {{ ref('agg_driver_daily') }} a
group by 1,2,3,4,5,6
