-- Origin-to-destination flow. The clearest use of the role-playing zone
-- dimension: the same dimension joined twice, once as origin and once as
-- destination, producing a matrix that neither key could produce alone.
--
-- Bounded to pairs with enough traffic to be meaningful -- the full 265 x 265
-- cross product is mostly ones and twos, and publishing that invites reading
-- noise as a route.
select
    o.zone_natural_key                                    as origin_location_id,
    o.zone_name                                           as origin_zone,
    o.borough_name                                        as origin_borough,
    o.is_airport_zone                                     as origin_is_airport,
    dz.zone_natural_key                                   as dest_location_id,
    dz.zone_name                                          as dest_zone,
    dz.borough_name                                       as dest_borough,
    dz.is_airport_zone                                    as dest_is_airport,
    o.borough_name = dz.borough_name                      as is_intra_borough,

    count(*)                                              as trip_count,
    sum(f.total_amount)                                   as total_revenue,
    avg(f.total_amount)                                   as avg_fare,
    avg(f.trip_distance)                                  as avg_distance,
    avg(f.trip_seconds) / 60.0                            as avg_minutes,
    {{ safe_divide('avg(f.trip_distance)', 'avg(f.trip_seconds) / 3600.0') }} as avg_corridor_mph
from {{ ref('fct_trip') }} f
join {{ ref('dim_zone') }} o  on f.pickup_zone_key  = o.zone_key
join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
where {{ in_report_window('f.pickup_datetime') }}
  and f.is_billable
group by 1,2,3,4,5,6,7,8,9
having count(*) >= 25
