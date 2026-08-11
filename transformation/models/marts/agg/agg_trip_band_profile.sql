-- Distance, duration and fare banding in one profile.
--
-- Three independent range joins against the banding seeds. Range joins are
-- easy to get wrong at the boundary: the bands are half-open [min, max), so a
-- trip of exactly three miles lands in "3 - 6", once, rather than in two bands
-- or none.
select
    db.distance_band,
    db.band_order                                         as distance_band_order,
    ub.duration_band,
    ub.band_order                                         as duration_band_order,
    fb.fare_band,
    fb.band_order                                         as fare_band_order,
    f.service_type_key,
    z.borough_name                                        as pickup_borough,
    dp.daypart_code,

    count(*)                                              as trip_count,
    sum(f.total_amount)                                   as total_revenue,
    avg(f.total_amount)                                   as avg_total_amount,
    avg(f.measurable_tip_rate)                            as avg_measurable_tip_rate,
    count(*) filter (where not f.is_billable)             as non_billable_count
from {{ ref('fct_trip') }} f
join {{ ref('dim_zone') }} z     on f.pickup_zone_key = z.zone_key
join {{ ref('dim_daypart') }} dp on f.pickup_hour     = dp.hour_of_day
join {{ ref('distance_bands') }} db
      on f.trip_distance >= db.min_miles and f.trip_distance < db.max_miles
join {{ ref('duration_bands') }} ub
      on f.trip_seconds / 60.0 >= ub.min_minutes and f.trip_seconds / 60.0 < ub.max_minutes
join {{ ref('fare_bands') }} fb
      on f.total_amount >= fb.min_total and f.total_amount < fb.max_total
where {{ in_report_window('f.pickup_datetime') }}
group by 1,2,3,4,5,6,7,8,9
