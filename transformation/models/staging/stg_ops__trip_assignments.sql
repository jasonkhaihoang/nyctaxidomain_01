select
    assignment_id,
    trip_key,
    shift_id,
    driver_id,
    vehicle_id,
    assigned_ts,
    assignment_method
from {{ source('ops_raw', 'trip_assignment') }}
