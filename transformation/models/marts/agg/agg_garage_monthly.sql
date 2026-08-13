-- Garage-month. The top of the pyramid, and the level the depot managers are
-- measured on.
select
    v.month_start_date,
    g.garage_key,
    g.garage_name,
    g.borough_name,
    g.bay_capacity,

    count(distinct v.vehicle_key)                          as active_vehicles,
    sum(v.shift_count)                                     as shift_count,
    sum(v.trip_count)                                      as trip_count,
    sum(v.online_hours)                                    as online_hours,
    sum(v.on_trip_hours)                                   as on_trip_hours,
    sum(v.gross_revenue)                                   as gross_revenue,
    sum(v.maintenance_cost)                                as maintenance_cost,
    sum(v.down_days)                                       as down_days,

    {{ safe_divide('sum(v.on_trip_hours)', 'nullif(sum(v.online_hours), 0)') }}  as occupancy_rate,
    {{ safe_divide('sum(v.gross_revenue)', 'nullif(sum(v.online_hours), 0)') }}  as revenue_per_online_hour,
    {{ safe_divide('count(distinct v.vehicle_key)::double', 'nullif(g.bay_capacity, 0)::double') }} as bay_occupancy_rate
from {{ ref('agg_vehicle_monthly') }} v
join {{ ref('dim_garage') }} g on v.garage_key = g.garage_key
group by 1,2,3,4,5
