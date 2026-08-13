-- What a shift earned and what it cost.
--
-- Lease terms differ by engagement: an owner-operator pays a revenue share and
-- no fixed rate, a lease driver pays a fixed daily or weekly rate regardless of
-- what they took. Blending the two into one "cost" column without the type is
-- how a fleet convinces itself its best drivers are its worst.
with trip_rollup as (
    select
        ta.shift_id,
        count(*)                                       as trip_count,
        sum(f.total_amount)                            as gross_revenue,
        sum(f.fare_amount)                             as fare_revenue,
        sum(f.tip_amount)                              as tip_revenue,
        sum(f.airport_fee)                             as airport_fee_collected,
        sum(f.total_surcharges)                        as surcharge_collected,
        sum(case when f.counts_as_revenue then f.total_amount else 0 end) as recognised_revenue,
        sum(t.trip_distance)                           as paid_miles,
        sum(t.trip_seconds)                            as paid_seconds
    from {{ ref('stg_ops__trip_assignments') }} ta
    join {{ ref('int_trip_fare_components') }} f on ta.trip_key = f.trip_key
    join {{ ref('stg_tlc__trips') }} t            on ta.trip_key = t.trip_key
    group by 1
)

select
    o.shift_id,
    o.driver_id,
    o.vehicle_id,
    o.shift_date,
    o.online_seconds,
    o.on_trip_seconds,
    o.occupancy_rate,
    coalesce(r.trip_count, 0)                          as trip_count,
    coalesce(r.gross_revenue, 0)                       as gross_revenue,
    coalesce(r.fare_revenue, 0)                        as fare_revenue,
    coalesce(r.tip_revenue, 0)                         as tip_revenue,
    coalesce(r.airport_fee_collected, 0)               as airport_fee_collected,
    coalesce(r.surcharge_collected, 0)                 as surcharge_collected,
    coalesce(r.recognised_revenue, 0)                  as recognised_revenue,
    coalesce(r.paid_miles, 0)                          as paid_miles,
    coalesce(r.paid_seconds, 0)                        as paid_seconds,
    d.engagement_type,
    l.lease_type,
    l.lease_rate,
    l.revenue_share_pct,
    case l.lease_type
         when 'lease_daily'    then l.lease_rate
         when 'lease_weekly'   then l.lease_rate / 6.0
         when 'owner_operator' then coalesce(r.gross_revenue, 0) * l.revenue_share_pct
    end                                                as shift_cost,
    coalesce(r.gross_revenue, 0)
      - case l.lease_type
             when 'lease_daily'    then l.lease_rate
             when 'lease_weekly'   then l.lease_rate / 6.0
             when 'owner_operator' then coalesce(r.gross_revenue, 0) * l.revenue_share_pct
        end                                            as shift_margin,
    {{ safe_divide('coalesce(r.gross_revenue, 0)', 'o.online_seconds / 3600.0') }} as revenue_per_online_hour,
    {{ safe_divide('coalesce(r.gross_revenue, 0)', 'nullif(r.paid_miles, 0)') }}   as revenue_per_paid_mile
from {{ ref('int_shift_occupancy') }} o
left join trip_rollup r                     on o.shift_id  = r.shift_id
left join {{ ref('stg_ops__drivers') }} d   on o.driver_id = d.driver_id
left join {{ ref('stg_ops__leases') }} l    on o.driver_id = l.driver_id
