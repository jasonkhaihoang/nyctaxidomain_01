{{ config(materialized='table') }}

-- Green-only columns dropped by ADR 0001. Same natural-key reconstruction as
-- the yellow side, and the same first-occurrence rule.
select
    trip_key,
    ehail_fee,
    trip_type,
    pickup_datetime
from (
    select
        {{ trip_natural_key("'green'", 'g."VendorID"', 'g.lpep_pickup_datetime',
           'g.lpep_dropoff_datetime', 'g."PULocationID"', 'g."DOLocationID"',
           'g.trip_distance', 'g.total_amount') }}       as trip_key,
        g.ehail_fee,
        g.trip_type,
        g.lpep_pickup_datetime                            as pickup_datetime,
        row_number() over (
            partition by {{ trip_natural_key("'green'", 'g."VendorID"', 'g.lpep_pickup_datetime',
               'g.lpep_dropoff_datetime', 'g."PULocationID"', 'g."DOLocationID"',
               'g.trip_distance', 'g.total_amount') }}
            order by g._source_file
        )                                                 as dup_rank
    from {{ source('bronze', 'green_tripdata') }} g
) d
where dup_rank = 1
