-- Vehicle-day. The asset view of the same shifts: one medallion may carry two
-- drivers across a day, and its utilisation is the sum of both.
select
    s.shift_date,
    cast(strftime(s.shift_date, '%Y%m%d') as integer)      as date_key,
    s.vehicle_key,
    v.medallion_number,
    v.make_model,
    v.fuel_type,
    v.is_low_emission,
    v.garage_key,

    count(*)                                               as shift_count,
    count(distinct s.driver_key)                           as distinct_drivers,
    sum(s.trip_count)                                      as trip_count,
    sum(s.online_seconds) / 3600.0                         as online_hours,
    sum(s.on_trip_seconds) / 3600.0                        as on_trip_hours,
    sum(s.gross_revenue)                                   as gross_revenue,
    sum(s.paid_miles)                                      as paid_miles,
    sum(s.odometer_miles)                                  as odometer_miles,

    {{ safe_divide('sum(s.on_trip_seconds)::double', 'nullif(sum(s.online_seconds), 0)::double') }} as occupancy_rate,
    -- Utilisation against the 24-hour day, not against sign-on time. A medallion
    -- idle in the depot is the asset question; a driver idle on the road is the
    -- labour question, and they are different numbers.
    {{ safe_divide('sum(s.online_seconds)::double', '86400.0') }}                as asset_utilisation_rate,
    {{ safe_divide('sum(s.paid_miles)', 'nullif(sum(s.odometer_miles), 0)') }}   as paid_mile_ratio
from {{ ref('fct_shift') }} s
join {{ ref('dim_vehicle') }} v on s.vehicle_key = v.vehicle_key
group by 1,2,3,4,5,6,7,8
