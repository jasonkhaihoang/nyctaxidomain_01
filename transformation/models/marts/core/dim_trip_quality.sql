-- Junk dimension. The trip fact carries a dozen independent boolean verdicts;
-- collapsing their observed combinations into one dimension keeps the fact
-- narrow and makes "which quality profile" a groupable attribute rather than
-- twelve separate filters.
--
-- Only combinations that actually occur are materialised -- the full cross
-- product would be 2^12 rows, almost all of them empty.
with combos as (
    select distinct
        is_billable, is_refund, is_zero_distance,
        is_implausibly_short, is_implausibly_fast, is_negative_duration,
        is_zero_passenger, is_missing_passenger_count, is_sparse_vendor_feed,
        is_unresolved_pickup_zone, is_undocumented_rate_code, is_missing_airport_fee
    from {{ ref('int_trip_quality_flags') }}
)

select
    md5(concat_ws('|', is_billable, is_refund, is_zero_distance,
        is_implausibly_short, is_implausibly_fast, is_negative_duration,
        is_zero_passenger, is_missing_passenger_count, is_sparse_vendor_feed,
        is_unresolved_pickup_zone, is_undocumented_rate_code,
        is_missing_airport_fee))                          as trip_quality_key,
    *,
    -- One rollup attribute so a report can say "clean" without listing twelve
    -- negations.
    (is_billable and not is_zero_distance and not is_implausibly_short
     and not is_implausibly_fast and not is_negative_duration
     and not is_unresolved_pickup_zone)                   as is_clean_trip
from combos
