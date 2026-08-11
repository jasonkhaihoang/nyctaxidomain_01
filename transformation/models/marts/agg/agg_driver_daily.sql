-- Driver-day: the first rollup above the shift, and the base of the driver
-- pyramid (day -> month -> scorecard).
--
-- A driver can run more than one shift in a day, so shift-level rates cannot be
-- averaged up -- they have to be recomputed from summed numerators and
-- denominators. Averaging two occupancy rates gives the mean of two ratios,
-- which is not the ratio anyone asked for.
select
    s.shift_date,
    cast(strftime(s.shift_date, '%Y%m%d') as integer)      as date_key,
    s.driver_key,
    d.driver_ref,
    d.engagement_type,
    d.garage_key,
    d.home_garage_name,

    count(*)                                               as shift_count,
    count(distinct s.vehicle_key)                          as vehicles_driven,
    sum(s.trip_count)                                      as trip_count,
    sum(s.online_seconds) / 3600.0                         as online_hours,
    sum(s.on_trip_seconds) / 3600.0                        as on_trip_hours,
    sum(s.break_seconds) / 3600.0                          as break_hours,
    sum(s.gross_revenue)                                   as gross_revenue,
    sum(s.tip_revenue)                                     as tip_revenue,
    sum(s.airport_fee_collected)                           as airport_fee_collected,
    sum(s.shift_cost)                                      as total_cost,
    sum(s.shift_margin)                                    as total_margin,
    sum(s.paid_miles)                                      as paid_miles,
    sum(case when s.is_unclosed_shift then 1 else 0 end)   as unclosed_shift_count,

    -- Rates rebuilt from the summed parts, never averaged from the shifts.
    {{ safe_divide('sum(s.on_trip_seconds)::double', 'nullif(sum(s.online_seconds), 0)::double') }} as occupancy_rate,
    {{ safe_divide('sum(s.gross_revenue)', 'nullif(sum(s.online_seconds), 0) / 3600.0') }}          as revenue_per_online_hour,
    {{ safe_divide('sum(s.gross_revenue)', 'nullif(sum(s.trip_count), 0)') }}                       as revenue_per_trip
from {{ ref('fct_shift') }} s
join {{ ref('dim_driver') }} d on s.driver_key = d.driver_key
group by 1,2,3,4,5,6,7
