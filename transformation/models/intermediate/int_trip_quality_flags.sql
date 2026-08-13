-- One row per trip carrying every quality verdict, so that downstream models
-- filter on a named condition rather than re-deriving the rule.
--
-- Nothing is deleted here. ADR 0002 puts the billable rule in gold, and a trip
-- excluded from a revenue mart is still a trip that happened.
select
    t.trip_key,
    t.total_amount > 0                                          as is_billable,
    t.total_amount < 0                                          as is_refund,
    t.trip_distance = 0                                         as is_zero_distance,
    t.trip_seconds < {{ var('min_plausible_seconds') }}         as is_implausibly_short,
    coalesce(t.avg_mph, 0) > {{ var('max_plausible_mph') }}     as is_implausibly_fast,
    t.trip_seconds < 0                                          as is_negative_duration,
    t.passenger_count = 0                                       as is_zero_passenger,
    t.passenger_count is null                                   as is_missing_passenger_count,
    -- One vendor's feed omits several optional columns together. Detecting the
    -- cluster rather than each column separately is what makes it attributable.
    (t.passenger_count is null
     and t.congestion_surcharge is null
     and t.store_and_fwd_flag is null)                          as is_sparse_vendor_feed,
    zp.is_unresolved_zone                                       as is_unresolved_pickup_zone,
    zd.is_unresolved_zone                                       as is_unresolved_dropoff_zone,
    t.rate_code_id = 99                                         as is_undocumented_rate_code,
    t.airport_fee_status = 'missing'                            as is_missing_airport_fee
from {{ ref('int_trips_enriched') }} t
left join {{ ref('int_zone_attributes') }} zp on t.pickup_location_id  = zp.location_id
left join {{ ref('int_zone_attributes') }} zd on t.dropoff_location_id = zd.location_id
