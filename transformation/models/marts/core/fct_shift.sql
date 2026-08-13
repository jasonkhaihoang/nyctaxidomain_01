-- One row per driver sign-on. The bridge between the operational world
-- (occupancy, leases) and the revenue world (trips).
select
    e.shift_id,
    cast(strftime(e.shift_date, '%Y%m%d') as integer)      as shift_date_key,
    e.shift_date,
    e.driver_id                                            as driver_key,
    e.vehicle_id                                           as vehicle_key,
    d.garage_key,
    e.engagement_type,
    e.lease_type,

    o.shift_start_ts,
    o.effective_end_ts,
    o.is_unclosed_shift,

    -- Time budget. These four should reconcile to online_seconds; the residual
    -- is published rather than hidden so a gap in the event stream is visible.
    e.online_seconds,
    e.on_trip_seconds,
    o.available_seconds,
    o.break_seconds,
    o.unaccounted_seconds,
    e.occupancy_rate,
    o.idle_rate,

    e.trip_count,
    e.gross_revenue,
    e.fare_revenue,
    e.tip_revenue,
    e.airport_fee_collected,
    e.surcharge_collected,
    e.recognised_revenue,
    e.paid_miles,
    e.paid_seconds,
    e.shift_cost,
    e.shift_margin,
    e.revenue_per_online_hour,
    e.revenue_per_paid_mile,
    o.odometer_miles,
    {{ safe_divide('e.paid_miles', 'nullif(o.odometer_miles, 0)') }} as paid_mile_ratio,
    o.negative_interval_count,
    o.telematics_source
from {{ ref('int_shift_economics') }} e
join {{ ref('int_shift_occupancy') }} o on e.shift_id = o.shift_id
left join {{ ref('dim_driver') }} d     on e.driver_id = d.driver_key
