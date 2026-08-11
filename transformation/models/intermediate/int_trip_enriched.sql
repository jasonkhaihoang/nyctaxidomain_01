select
    t.trip_key,
    t.service_type,
    t.vendor_id,
    t.pickup_datetime,
    t.dropoff_datetime,
    t.pickup_date,
    t.pickup_hour,
    t.pickup_location_id,
    t.dropoff_location_id,
    t.rate_code_id,
    t.payment_type,
    t.passenger_count,
    t.store_and_fwd_flag,
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
    t.total_amount,

    -- date dimension key
    cast(strftime(t.pickup_date, '%Y%m%d') as integer) as pickup_date_key,

    -- daypart classification
    case
        when t.pickup_hour between 6 and 11 then 'morning'
        when t.pickup_hour between 12 and 16 then 'afternoon'
        when t.pickup_hour between 17 and 21 then 'evening'
        else 'night'
    end as daypart_code,

    -- zone dimension keys
    md5(cast(t.pickup_location_id as varchar)) as pickup_zone_key,
    md5(cast(t.dropoff_location_id as varchar)) as dropoff_zone_key,

    -- vendor key
    md5(cast(t.vendor_id as varchar)) as vendor_key,

    -- payment type key
    t.payment_type as payment_type_key,

    -- rate code key
    t.rate_code_id as rate_code_key,

    -- fare components
    coalesce(t.extra, 0) + coalesce(t.mta_tax, 0) + coalesce(t.improvement_surcharge, 0) + coalesce(t.congestion_surcharge, 0) as total_surcharges,

    t.total_amount - t.fare_amount - coalesce(t.tip_amount, 0) - coalesce(t.tolls_amount, 0)
        - (coalesce(t.extra, 0) + coalesce(t.mta_tax, 0) + coalesce(t.improvement_surcharge, 0) + coalesce(t.congestion_surcharge, 0))
        as fare_residual,

    -- tip metrics
    case
        when t.fare_amount > 0 then t.tip_amount / t.fare_amount
        else null
    end as tip_rate,

    -- quality flags
    case
        when t.trip_seconds <= 0 then true
        when t.trip_distance < 0 then true
        when t.fare_amount < 0 then true
        when t.trip_distance = 0 and t.total_amount > 0 then true
        when t.avg_mph > 100 then true
        else false
    end as is_quality_flagged,

    -- fleet ops
    case
        when t.service_type = 'yellow' then true
        else false
    end as is_fleet_attributed,

    case
        when t.service_type = 'yellow' then 'yellow_v' || cast(t.vendor_id as varchar)
        else 'green'
    end as assignment_method

from {{ ref('stg_silver__trips') }} t
