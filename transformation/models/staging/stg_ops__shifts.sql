-- Shift sign-ons. `shift_end_ts` is null where the tablet died before LOGOUT,
-- so an effective end is resolved here once rather than in every consumer,
-- and the substitution is flagged so nobody has to guess whether it happened.
select
    shift_id,
    vehicle_id,
    driver_id,
    shift_start_ts,
    shift_end_ts,
    derived_end_ts,
    coalesce(shift_end_ts, derived_end_ts)    as effective_end_ts,
    shift_end_ts is null                      as is_unclosed_shift,
    date_diff('second', shift_start_ts,
              coalesce(shift_end_ts, derived_end_ts)) as shift_seconds,
    cast(shift_start_ts as date)              as shift_date,
    reported_trip_count,
    odometer_start,
    odometer_end,
    odometer_end - odometer_start             as odometer_miles,
    telematics_source
from {{ source('ops_raw', 'shift') }}
