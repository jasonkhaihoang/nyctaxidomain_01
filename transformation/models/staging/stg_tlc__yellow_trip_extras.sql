{{ config(materialized='table') }}

-- Yellow-only columns that ADR 0001 dropped when conforming. Recomputes the
-- silver natural key so the fleet-specific fee can be rejoined to a trip.
--
-- Bronze is not deduplicated, so the same natural key can appear more than
-- once; taking the first occurrence keeps this one-row-per-trip and stops the
-- rejoin multiplying the fact.
select
    trip_key,
    airport_fee,
    pickup_location_id,
    pickup_datetime
from (
    select
        {{ trip_natural_key("'yellow'", 'y."VendorID"', 'y.tpep_pickup_datetime',
           'y.tpep_dropoff_datetime', 'y."PULocationID"', 'y."DOLocationID"',
           'y.trip_distance', 'y.total_amount') }}       as trip_key,
        y."Airport_fee"                                   as airport_fee,
        y."PULocationID"                                  as pickup_location_id,
        y.tpep_pickup_datetime                            as pickup_datetime,
        row_number() over (
            partition by {{ trip_natural_key("'yellow'", 'y."VendorID"', 'y.tpep_pickup_datetime',
               'y.tpep_dropoff_datetime', 'y."PULocationID"', 'y."DOLocationID"',
               'y.trip_distance', 'y.total_amount') }}
            order by y._source_file
        )                                                 as dup_rank
    from {{ source('bronze', 'yellow_tripdata') }} y
) d
where dup_rank = 1
