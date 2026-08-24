-- Reconciliation support model: exposes `fct_trip` at its native grain with
-- the inputs the baseline-agg reconciliation needs but `fct_trip` itself
-- doesn't carry at this grain — the TLC-published borough (joined from the
-- bronze zone lookup by location id, not `dim_zone`, which leaves borough
-- null/mismatched for a handful of pre-2024 dates) and a literal
-- row-count flag, so `vd_recon_compile_rollup_relation`'s SUM-only rollup
-- can produce `trip_cnt` via `sum(trip_flag)`, `gross_revenue` via
-- `sum(total_amount)`, and `fare_gap` via
-- `sum(fare_residual + coalesce(congestion_surcharge, 0))` — confirmed by
-- investigation (H2) as the exact target-side counterpart of the
-- baseline's fare_gap: fare_residual (int_trip_fare_components) already
-- nets congestion_surcharge out of the total, so adding it back isolates
-- the amount the baseline deliberately treats as unexplained-by-core-fare
-- (the congestion pass-through plus any genuine residual), matching the
-- baseline's own definition row-for-row and to double-precision noise.
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
    t.fare_residual + coalesce(t.congestion_surcharge, 0)  as fare_gap,
    1                                                       as trip_flag
from domain.core.fct_trip t
left join {{ source('bronze', 'taxi_zone_lookup') }} l
       on t.pickup_location_id = l."LocationID"
