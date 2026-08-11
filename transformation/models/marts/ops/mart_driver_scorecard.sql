-- Driver performance for the period, ranked within garage and fleet-wide.
--
-- Ranking is deliberately done on revenue per online hour rather than on gross
-- revenue: gross rewards whoever worked the most hours, which is a roster fact,
-- not a performance one. Drivers below a minimum hours floor are carried but
-- flagged, because ranking someone on two shifts against someone on sixty is
-- noise dressed as a league table.
with period as (
    select
        m.driver_key,
        m.driver_ref,
        m.engagement_type,
        m.garage_key,
        m.home_garage_name,
        sum(m.active_days)                                 as active_days,
        sum(m.shift_count)                                 as shift_count,
        sum(m.trip_count)                                  as trip_count,
        sum(m.online_hours)                                as online_hours,
        sum(m.on_trip_hours)                               as on_trip_hours,
        sum(m.gross_revenue)                               as gross_revenue,
        sum(m.tip_revenue)                                 as tip_revenue,
        sum(m.total_cost)                                  as total_cost,
        sum(m.total_margin)                                as total_margin,
        sum(m.paid_miles)                                  as paid_miles
    from {{ ref('agg_driver_monthly') }} m
    group by 1,2,3,4,5
)

select
    p.*,
    {{ safe_divide('p.on_trip_hours', 'nullif(p.online_hours, 0)') }}    as occupancy_rate,
    {{ safe_divide('p.gross_revenue', 'nullif(p.online_hours, 0)') }}    as revenue_per_online_hour,
    {{ safe_divide('p.gross_revenue', 'nullif(p.trip_count, 0)') }}      as revenue_per_trip,
    {{ safe_divide('p.trip_count::double', 'nullif(p.online_hours, 0)') }} as trips_per_online_hour,
    {{ safe_divide('p.tip_revenue', 'nullif(p.gross_revenue, 0)') }}     as tip_share,
    p.online_hours < 40                                                  as is_below_ranking_floor,
    rank() over (
        order by {{ safe_divide('p.gross_revenue', 'nullif(p.online_hours, 0)') }} desc
    )                                                                    as fleet_rank,
    rank() over (
        partition by p.garage_key
        order by {{ safe_divide('p.gross_revenue', 'nullif(p.online_hours, 0)') }} desc
    )                                                                    as garage_rank,
    ntile(4) over (
        order by {{ safe_divide('p.gross_revenue', 'nullif(p.online_hours, 0)') }}
    )                                                                    as revenue_quartile,
    percent_rank() over (
        order by {{ safe_divide('p.on_trip_hours', 'nullif(p.online_hours, 0)') }}
    )                                                                    as occupancy_percentile
from period p
