-- Conformed trips, lightly shaped. Derived measures that every downstream
-- model would otherwise recompute (duration, speed, calendar keys) land here
-- once. No filtering: silver's completeness is deliberate and staging keeps it.
select
    t.trip_key,
    t.service_type,
    t.vendor_id,
    t.pickup_datetime,
    t.dropoff_datetime,
    cast(t.pickup_datetime as date)                       as pickup_date,
    extract(hour from t.pickup_datetime)                  as pickup_hour,
    t.pickup_location_id,
    t.dropoff_location_id,
    t.rate_code_id,
    t.payment_type,
    t.passenger_count,
    t.store_and_fwd_flag,
    t.trip_distance,
    t.fare_amount,
    t.extra,
    t.mta_tax,
    t.tip_amount,
    t.tolls_amount,
    t.improvement_surcharge,
    t.congestion_surcharge,
    t.total_amount,
    date_diff('second', t.pickup_datetime, t.dropoff_datetime) as trip_seconds,
    {{ safe_divide('t.trip_distance',
        'date_diff(\'second\', t.pickup_datetime, t.dropoff_datetime) / 3600.0') }} as avg_mph,
    t._load_id,
    t._source_file
from {{ source('silver', 'trips') }} t
