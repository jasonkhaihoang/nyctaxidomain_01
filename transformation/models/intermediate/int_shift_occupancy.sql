-- Occupancy per shift: how much of the time a driver was signed on did they
-- spend carrying a fare, waiting for one, or on a break.
--
-- Utilisation is measured against *online* seconds, not against the wall clock.
-- A shift that ends early is not an unproductive shift, and dividing by the
-- wrong denominator is the difference between a driver ranking first and last.
with by_status as (
    select
        shift_id,
        sum(interval_seconds) filter (where status_code = 'ON_TRIP')            as on_trip_seconds,
        sum(interval_seconds) filter (where status_code in ('AVAILABLE', 'DISPATCHED')) as available_seconds,
        sum(interval_seconds) filter (where status_code = 'BREAK')              as break_seconds,
        sum(interval_seconds) filter (where status_code = 'DISPATCHED')         as dispatch_seconds,
        count(*)                                                                as event_count,
        count(*) filter (where is_negative_interval)                            as negative_interval_count,
        max(case when is_terminal_interval then 1 else 0 end) = 1               as had_open_interval
    from {{ ref('int_status_intervals') }}
    group by 1
)

select
    s.shift_id,
    s.driver_id,
    s.vehicle_id,
    s.shift_date,
    s.shift_start_ts,
    s.effective_end_ts,
    s.is_unclosed_shift,
    s.shift_seconds                                    as online_seconds,
    coalesce(b.on_trip_seconds, 0)                     as on_trip_seconds,
    coalesce(b.available_seconds, 0)                   as available_seconds,
    coalesce(b.break_seconds, 0)                       as break_seconds,
    coalesce(b.dispatch_seconds, 0)                    as dispatch_seconds,
    s.shift_seconds
      - coalesce(b.on_trip_seconds, 0)
      - coalesce(b.available_seconds, 0)
      - coalesce(b.break_seconds, 0)                   as unaccounted_seconds,
    {{ safe_divide('coalesce(b.on_trip_seconds, 0)', 's.shift_seconds') }} as occupancy_rate,
    {{ safe_divide('coalesce(b.available_seconds, 0)', 's.shift_seconds') }} as idle_rate,
    b.event_count,
    coalesce(b.negative_interval_count, 0)             as negative_interval_count,
    coalesce(b.had_open_interval, false)               as had_open_interval,
    s.odometer_miles,
    s.telematics_source
from {{ ref('stg_ops__shifts') }} s
left join by_status b on s.shift_id = b.shift_id
