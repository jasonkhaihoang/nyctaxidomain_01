-- Reconciliation support model: exposes `fct_trip` at its native grain with
-- the two inputs the baseline-agg reconciliation needs but `fct_trip` itself
-- doesn't carry — the TLC-published borough (joined from the bronze zone
-- lookup by location id, not `dim_zone`, which leaves borough null/mismatched
-- for a handful of pre-2024 dates) and a literal row-count flag, so
-- `vd_recon_compile_rollup_relation`'s SUM-only rollup can produce `trip_cnt`
-- via `sum(trip_flag)` alongside `sum(total_amount)` for `gross_revenue`.
--
-- Reads the Target relation directly off the `domain` attach rather than
-- through `ref('fct_trip')`: this reconciliation is against `fct_trip` as
-- already built in the domain database (the dev/ephemeral run never
-- rebuilds it), the same relation `core.fct_trip_baseline_agg` is compared
-- against.
select
    t.trip_key,
    t.pickup_date                                          as trip_day,
    coalesce(l."Borough", 'N/A')                           as pickup_borough,
    t.total_amount,
    1                                                       as trip_flag
from domain.core.fct_trip t
left join {{ source('bronze', 'taxi_zone_lookup') }} l
       on t.pickup_location_id = l."LocationID"
