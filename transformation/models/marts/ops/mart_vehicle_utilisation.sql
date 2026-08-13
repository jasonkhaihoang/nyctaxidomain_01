-- Asset utilisation for the period, with downtime netted out.
select
    v.vehicle_key,
    v.medallion_number,
    v.make_model,
    v.model_year,
    v.fuel_type,
    v.is_low_emission,
    v.garage_key,
    g.garage_name,
    v.is_in_service,

    sum(m.active_days)                                     as active_days,
    sum(m.shift_count)                                     as shift_count,
    sum(m.trip_count)                                      as trip_count,
    sum(m.online_hours)                                    as online_hours,
    sum(m.on_trip_hours)                                   as on_trip_hours,
    sum(m.gross_revenue)                                   as gross_revenue,
    sum(m.paid_miles)                                      as paid_miles,
    sum(m.down_days)                                       as down_days,
    sum(m.maintenance_cost)                                as maintenance_cost,
    sum(m.available_days)                                  as available_days,

    {{ safe_divide('sum(m.on_trip_hours)', 'nullif(sum(m.online_hours), 0)') }}   as occupancy_rate,
    {{ safe_divide('sum(m.active_days)::double', 'nullif(sum(m.available_days), 0)::double') }} as availability_adjusted_rate,
    {{ safe_divide('sum(m.gross_revenue)', 'nullif(sum(m.online_hours), 0)') }}   as revenue_per_online_hour,
    {{ safe_divide('sum(m.gross_revenue) - sum(m.maintenance_cost)', 'nullif(sum(m.active_days), 0)') }} as net_revenue_per_active_day
from {{ ref('agg_vehicle_monthly') }} m
join {{ ref('dim_vehicle') }} v on m.vehicle_key = v.vehicle_key
left join {{ ref('dim_garage') }} g on v.garage_key = g.garage_key
group by 1,2,3,4,5,6,7,8,9
