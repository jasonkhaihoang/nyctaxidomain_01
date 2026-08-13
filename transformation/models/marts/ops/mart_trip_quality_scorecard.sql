-- What proportion of the feed is trustworthy, and which vendor's records are
-- not. Aggregated through the junk dimension so every verdict is groupable.
select
    date_trunc('month', f.pickup_datetime)                 as trip_month,
    ve.vendor_natural_key                                  as vendor_id,
    ve.vendor_legal_name,
    f.service_type_key,

    count(*)                                               as trip_count,
    count(*) filter (where q.is_clean_trip)                as clean_trip_count,
    count(*) filter (where not q.is_billable)              as non_billable_count,
    count(*) filter (where q.is_refund)                    as refund_count,
    count(*) filter (where q.is_zero_distance)             as zero_distance_count,
    count(*) filter (where q.is_implausibly_fast)          as implausible_speed_count,
    count(*) filter (where q.is_sparse_vendor_feed)        as sparse_feed_count,
    count(*) filter (where q.is_unresolved_pickup_zone)    as unresolved_zone_count,
    count(*) filter (where q.is_undocumented_rate_code)    as undocumented_rate_count,
    count(*) filter (where f.fare_residual is not null
                       and abs(f.fare_residual) > 0.01)    as unbalanced_total_count,

    {{ safe_divide('count(*) filter (where q.is_clean_trip)::double', 'count(*)::double') }} as clean_rate,
    {{ safe_divide('count(*) filter (where q.is_sparse_vendor_feed)::double', 'count(*)::double') }} as sparse_feed_rate
from {{ ref('fct_trip') }} f
join {{ ref('dim_trip_quality') }} q on f.trip_quality_key = q.trip_quality_key
left join {{ ref('dim_vendor') }} ve on f.vendor_key       = ve.vendor_key
where {{ in_report_window('f.pickup_datetime') }}
group by 1,2,3,4
