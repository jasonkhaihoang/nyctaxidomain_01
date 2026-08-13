-- The occupancy stream. Sessionizing happens in intermediate; staging only
-- normalises and exposes the clock-skew between assigned and received time,
-- which is what makes an interval come out negative if you pick the wrong one.
select
    event_id,
    shift_id,
    driver_id,
    vehicle_id,
    event_ts,
    received_ts,
    status_code,
    zone_id,
    source_system,
    date_diff('second', event_ts, received_ts) as skew_seconds,
    status_code in ('ON_TRIP')                 as is_occupied_status,
    status_code in ('AVAILABLE', 'DISPATCHED') as is_available_status
from {{ source('ops_raw', 'driver_status_event') }}
