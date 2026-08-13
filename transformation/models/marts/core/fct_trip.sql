{{ config(
    materialized = 'incremental',
    unique_key   = 'trip_key',
    incremental_strategy = 'delete+insert'
) }}

-- The grain of the warehouse: one row per TLC trip.
--
-- Three things make this fact more than a rename.
--
-- 1. **Role-playing zone.** Pickup and dropoff both point at dim_zone. Two
--    separate surrogate keys, resolved independently, so a report can group by
--    origin or destination without a second fact.
--
-- 2. **As-of joins to the Type 2 dimensions.** dim_zone and dim_vendor are
--    versioned, so the join carries the trip's own date through a half-open
--    validity interval. Joining on the natural key alone would multiply every
--    trip that touches a re-designated zone.
--
-- 3. **Sparse fleet attribution.** Harbour Point runs ~420 of roughly 13,000
--    city medallions, so driver, vehicle and shift are null on most rows. That
--    is a real property of the business, not missing data, and
--    `is_fleet_attributed` says so explicitly rather than leaving every
--    consumer to infer it from a null.

with trips as (
    select * from {{ ref('int_trips_enriched') }}
    {% if is_incremental() %}
    where pickup_datetime > (select coalesce(max(pickup_datetime), '1900-01-01') from {{ this }})
    {% endif %}
),

quality as (
    select
        trip_key,
        md5(concat_ws('|', is_billable, is_refund, is_zero_distance,
            is_implausibly_short, is_implausibly_fast, is_negative_duration,
            is_zero_passenger, is_missing_passenger_count, is_sparse_vendor_feed,
            is_unresolved_pickup_zone, is_undocumented_rate_code,
            is_missing_airport_fee))                       as trip_quality_key,
        is_billable
    from {{ ref('int_trip_quality_flags') }}
)

select
    t.trip_key,

    -- Degenerate and conformed dimension keys
    d.date_key                                             as pickup_date_key,
    t.pickup_date,
    t.pickup_hour,
    dp.daypart_code,
    t.service_type                                         as service_type_key,
    zp.zone_key                                            as pickup_zone_key,
    zd.zone_key                                            as dropoff_zone_key,
    v.vendor_key,
    t.payment_type                                         as payment_method_key,
    t.rate_code_id                                         as rate_plan_key,
    q.trip_quality_key,

    -- Fleet attribution. Null for any trip run by another operator.
    ta.shift_id,
    ta.driver_id                                           as driver_key,
    ta.vehicle_id                                          as vehicle_key,
    ta.assignment_method,
    ta.shift_id is not null                                as is_fleet_attributed,

    -- Degenerate attributes
    t.pickup_datetime,
    t.dropoff_datetime,
    t.pickup_location_id,
    t.dropoff_location_id,
    t.passenger_count,
    t.store_and_fwd_flag,
    t.trip_type,

    -- Measures
    t.trip_distance,
    t.trip_seconds,
    t.avg_mph,
    t.fare_amount,
    t.extra,
    t.mta_tax,
    t.tip_amount,
    t.tolls_amount,
    t.improvement_surcharge,
    t.congestion_surcharge,
    t.airport_fee,
    t.ehail_fee,
    t.total_amount,
    fc.total_surcharges,
    fc.fare_residual,
    fc.measurable_tip_rate,
    q.is_billable,
    t.airport_fee_status

from trips t
left join quality q                        on t.trip_key = q.trip_key
left join {{ ref('int_trip_fare_components') }} fc on t.trip_key = fc.trip_key
left join {{ ref('dim_date') }} d          on t.pickup_date = d.calendar_date
left join {{ ref('dim_daypart') }} dp      on t.pickup_hour = dp.hour_of_day

-- Role-playing dimension, resolved as of the trip's own date.
left join {{ ref('dim_zone') }} zp
       on t.pickup_location_id = zp.zone_natural_key
      and t.pickup_date >= zp.valid_from_date
      and t.pickup_date <  zp.valid_to_date
left join {{ ref('dim_zone') }} zd
       on t.dropoff_location_id = zd.zone_natural_key
      and t.pickup_date >= zd.valid_from_date
      and t.pickup_date <  zd.valid_to_date

left join {{ ref('dim_vendor') }} v
       on t.vendor_id = v.vendor_natural_key
      and t.pickup_date >= v.valid_from_date
      and t.pickup_date <  v.valid_to_date

left join {{ ref('stg_ops__trip_assignments') }} ta on t.trip_key = ta.trip_key
