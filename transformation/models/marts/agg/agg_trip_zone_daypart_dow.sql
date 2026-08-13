-- The workhorse demand cube: pickup zone x daypart x day-of-week x fleet.
--
-- This is the grain most operational questions land on -- "where and when do we
-- actually earn" -- and materialising it means those questions do not each
-- re-scan twenty million rows.
--
-- Tip metrics are restricted to payment methods where the meter captures tips.
-- Cash trips record a zero that means "not measured", so including them drags
-- every tip rate toward zero in proportion to how much cash a zone takes,
-- which reads as a behavioural finding and is an artefact.
select
    z.zone_natural_key                                    as pickup_location_id,
    z.zone_name,
    z.borough_name,
    z.reporting_region,
    z.zone_class,
    z.is_airport_zone,
    d.day_of_week,
    d.day_name,
    d.is_weekend,
    d.is_non_working_day,
    dp.daypart_code,
    dp.daypart_name,
    dp.is_peak,
    f.service_type_key,

    count(*)                                              as trip_count,
    count(*) filter (where f.is_billable)                 as billable_trip_count,
    sum(f.total_amount)                                   as total_revenue,
    sum(f.fare_amount)                                    as fare_revenue,
    sum(f.tip_amount)                                     as tip_revenue,
    sum(f.total_surcharges)                               as surcharge_revenue,
    sum(f.trip_distance)                                  as total_miles,
    sum(f.trip_seconds) / 3600.0                          as total_paid_hours,

    avg(f.total_amount)                                   as avg_total_amount,
    avg(f.trip_distance)                                  as avg_trip_distance,
    avg(f.trip_seconds) / 60.0                            as avg_trip_minutes,
    median(f.total_amount)                                as median_total_amount,

    -- Tip rate over the measurable population only, with its own denominator
    -- published so the reader can see how much of the traffic it covers.
    avg(f.measurable_tip_rate)                            as avg_measurable_tip_rate,
    count(f.measurable_tip_rate)                          as measurable_tip_trip_count,
    {{ safe_divide('count(f.measurable_tip_rate)::double', 'count(*)::double') }} as tip_measurable_share
from {{ ref('fct_trip') }} f
join {{ ref('dim_zone') }} z    on f.pickup_zone_key = z.zone_key
join {{ ref('dim_date') }} d    on f.pickup_date_key = d.date_key
join {{ ref('dim_daypart') }} dp on f.daypart_code   = dp.daypart_code and f.pickup_hour = dp.hour_of_day
where {{ in_report_window('f.pickup_datetime') }}
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14
