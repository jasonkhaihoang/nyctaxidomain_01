select
    trip_key,
    service_type,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    cast(pickup_datetime as date) as pickup_date,
    date_part('hour', pickup_datetime) as pickup_hour,
    pickup_location_id,
    dropoff_location_id,
    rate_code_id,
    payment_type,
    passenger_count,
    store_and_fwd_flag,
    trip_distance,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    congestion_surcharge,
    total_amount,
    date_diff('second', pickup_datetime, dropoff_datetime) as trip_seconds,
    case
        when date_diff('second', pickup_datetime, dropoff_datetime) = 0 then null
        else trip_distance / (date_diff('second', pickup_datetime, dropoff_datetime) / 3600.0)
    end as avg_mph,
    _load_id,
    _source_file
from {{ source('silver', 'trips') }}
