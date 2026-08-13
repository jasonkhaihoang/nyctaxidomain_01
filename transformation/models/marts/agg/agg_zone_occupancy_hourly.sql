-- Where the fleet spends its time, by zone and hour, from the status stream
-- rather than from trips.
--
-- This is the only place idle time is locatable. A trip tells you where a
-- driver earned; the status stream tells you where they sat waiting, and the
-- gap between those two maps is the whole point of collecting occupancy.
select
    i.interval_date,
    i.interval_hour,
    i.daypart_code,
    z.zone_natural_key                                     as location_id,
    z.zone_name,
    z.borough_name,
    z.is_airport_zone,

    count(*)                                               as interval_count,
    count(distinct i.driver_key)                           as distinct_drivers,
    count(distinct i.vehicle_key)                          as distinct_vehicles,
    sum(i.interval_seconds) / 3600.0                       as total_hours,
    sum(i.interval_seconds) filter (where i.status_code = 'ON_TRIP') / 3600.0    as on_trip_hours,
    sum(i.interval_seconds) filter (where i.status_code = 'AVAILABLE') / 3600.0  as available_hours,
    sum(i.interval_seconds) filter (where i.status_code = 'BREAK') / 3600.0      as break_hours,
    {{ safe_divide(
        "sum(i.interval_seconds) filter (where i.status_code = 'ON_TRIP')::double",
        'nullif(sum(i.interval_seconds), 0)::double') }}    as zone_occupancy_rate
from {{ ref('fct_status_interval') }} i
join {{ ref('dim_zone') }} z on i.zone_key = z.zone_key
group by 1,2,3,4,5,6,7
