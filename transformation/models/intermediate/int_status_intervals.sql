-- Sessionizes the driver status stream into durable intervals: each event
-- opens a state that runs until the next event on the same shift.
--
-- Two traps. The stream is ordered on `event_ts`, never `received_ts` --
-- roughly 0.3% of events arrive skewed by up to two minutes, which is enough to
-- invert their order against a neighbour and produce a negative duration. And
-- the last event of an unclosed shift has no successor, so it is closed against
-- the shift's effective end rather than left open forever.
with ordered as (
    select
        e.event_id,
        e.shift_id,
        e.driver_id,
        e.vehicle_id,
        e.status_code,
        e.zone_id,
        e.event_ts                                     as interval_start_ts,
        lead(e.event_ts) over (
            partition by e.shift_id order by e.event_ts, e.event_id
        )                                              as next_event_ts,
        e.skew_seconds
    from {{ ref('stg_ops__status_events') }} e
)

select
    o.event_id                                         as interval_id,
    o.shift_id,
    o.driver_id,
    o.vehicle_id,
    o.status_code,
    o.zone_id,
    o.interval_start_ts,
    coalesce(o.next_event_ts, s.effective_end_ts)      as interval_end_ts,
    o.next_event_ts is null                            as is_terminal_interval,
    greatest(
        date_diff('second', o.interval_start_ts,
                  coalesce(o.next_event_ts, s.effective_end_ts)),
        0
    )                                                  as interval_seconds,
    date_diff('second', o.interval_start_ts,
              coalesce(o.next_event_ts, s.effective_end_ts)) < 0 as is_negative_interval,
    o.skew_seconds,
    cast(o.interval_start_ts as date)                  as interval_date,
    extract(hour from o.interval_start_ts)             as interval_hour
from ordered o
join {{ ref('stg_ops__shifts') }} s on o.shift_id = s.shift_id
