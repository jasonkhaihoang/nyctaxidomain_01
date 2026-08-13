-- Demand against weather, by borough and day.
--
-- The join is borough-and-date, so it is a genuine many-to-one: one observation
-- serves every trip that started in that borough that day. Attaching weather at
-- the trip grain instead would multiply nothing but would store the same
-- observation twenty million times.
select
    w.obs_date,
    w.borough_name,
    d.day_name,
    d.is_weekend,
    d.is_holiday,
    w.temp_avg_f,
    w.precip_inches,
    w.snow_inches,
    w.is_wet_day,
    w.is_snow_day,
    case when w.snow_inches > 0.5 then 'snow'
         when w.precip_inches > 0.10 then 'wet'
         when w.temp_avg_f > 80 then 'hot'
         when w.temp_avg_f < 32 then 'freezing'
         else 'fair' end                                  as weather_class,

    count(f.trip_key)                                     as trip_count,
    sum(f.total_amount)                                   as total_revenue,
    avg(f.trip_distance)                                  as avg_trip_distance,
    avg(f.total_amount)                                   as avg_fare,
    {{ safe_divide('sum(f.trip_seconds) / 3600.0', 'count(f.trip_key)::double') }} as avg_paid_hours_per_trip
from {{ ref('stg_mdm__weather') }} w
join {{ ref('dim_date') }} d on w.obs_date = d.calendar_date
left join {{ ref('dim_zone') }} z
       on z.borough_name = w.borough_name and z.is_current_version
left join {{ ref('fct_trip') }} f
       on f.pickup_zone_key = z.zone_key and f.pickup_date = w.obs_date
group by 1,2,3,4,5,6,7,8,9,10,11
