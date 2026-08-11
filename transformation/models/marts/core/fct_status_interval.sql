-- The occupancy grain: one row per driver state interval. Kept as a fact in its
-- own right because "where was the fleet idle, and when" is a question about
-- intervals, and rolling straight to the shift throws that away.
select
    i.interval_id,
    i.shift_id,
    i.driver_id                                            as driver_key,
    i.vehicle_id                                           as vehicle_key,
    cast(strftime(i.interval_date, '%Y%m%d') as integer)   as interval_date_key,
    i.interval_date,
    i.interval_hour,
    dp.daypart_code,
    z.zone_key,
    i.zone_id                                              as zone_natural_key,
    i.status_code,
    i.interval_start_ts,
    i.interval_end_ts,
    i.interval_seconds,
    i.is_terminal_interval,
    i.is_negative_interval,
    i.skew_seconds
from {{ ref('int_status_intervals') }} i
left join {{ ref('dim_daypart') }} dp on i.interval_hour = dp.hour_of_day
left join {{ ref('dim_zone') }} z
       on i.zone_id = z.zone_natural_key
      and z.is_current_version
