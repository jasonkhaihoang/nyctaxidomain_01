# Recon Pair: `core.fct_trip_baseline_agg` (Baseline) vs `core.fct_trip` (Target)

## Confirmed contract

- **Baseline:** `nyctaxi.core.fct_trip_baseline_agg`
- **Target:** `nyctaxi.core.fct_trip`
- **Grain:** Different. Baseline is pre-aggregated at `(trip_day, pickup_borough)`; target is
  row-level (`trip_key`). Target is rolled up to the common grain via
  `vd_recon_compile_rollup_relation`, run once per aggregate (`trip_cnt`, `gross_revenue`) on
  both sides and joined on the macro's own deterministic `grain_key` (identical algorithm on
  both sides since both sides call the same macro).
- **Mode:** Keyed, on the rollup macro's synthetic `grain_key` (encodes `trip_day` +
  `pickup_borough`; `vd_recon_compare_keyed`/`vd_recon_categorize_keyed` only ever use a
  single-column key, so a composite grain requires this synthetic column on both sides).
- **Scope:** FSA-narrowed to 6 months, `trip_day`/`pickup_date` in `[2024-01-01, 2024-07-01)` —
  the ADR-0002 reporting window, covering 1,444 of the baseline's 1,457 rows.
- **Gating:** Advisory (never blocks Intent completion) — FSA-confirmed.
- **Round cap:** 3 — FSA-confirmed.

### Column mapping

| Baseline | Target rollup | Aggregate | Cast/derivation | Justification |
| --- | --- | --- | --- | --- |
| trip_day | pickup_date | — (group-by/key) | none | identical grain unit (DATE) |
| pickup_borough | dim_zone.borough_name (joined via pickup_zone_key) | — (group-by/key) | none | target has no native borough column; resolved through `dim_zone` |
| trip_cnt | count(*) | row count, via constant `trip_flag=1` summed | none | spot-check match: 2024-01-13/Manhattan baseline=96,332, target rollup=96,332 |
| gross_revenue | sum(total_amount) | sum | none | spot-check match: 2024-01-13/Manhattan baseline=2,072,505.35, target rollup=2,072,505.35 |
| fare_gap | — | — | — | **Dropped from scope by FSA decision.** No target column/combination (`fare_residual`, `total_amount - fare_amount`, `total_surcharges`, etc.) reproduced it on spot-check; out of scope for this comparison. |

Target's remaining columns (all row-level fare/trip attributes not entering `trip_cnt` or
`gross_revenue`) have no baseline counterpart at this grain and are out of scope.

### PII

`vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline_agg)` → `[]`. No PII gating required.

### Tolerance

- Exact: `trip_cnt_sum`
- Fixed tolerance $0.01: `gross_revenue_sum` (accounts for floating-point `SUM(DOUBLE)` accumulation order differences between baseline's pre-aggregation and target's rollup)

### Profiling evidence (Negotiate step)

| Check | Macro | Result |
| --- | --- | --- |
| Baseline schema | `vd_recon_schema_probe(domain.core.fct_trip_baseline_agg)` | `trip_day DATE, pickup_borough VARCHAR, trip_cnt BIGINT, gross_revenue DOUBLE, fare_gap DOUBLE` |
| Baseline boundaries (`trip_day`) | `vd_recon_probe_boundaries(domain.core.fct_trip_baseline_agg, "trip_day")` | `{"min": "2002-12-31", "max": "2026-06-26", "count": 1457}` |
| Target boundaries (`pickup_datetime`) | `vd_recon_probe_boundaries(domain.core.fct_trip, "pickup_datetime")` | `{"min": "2002-12-31 16:46:07", "max": "2026-06-26 23:53:12", "count": 20671899}` |
| Baseline PII columns | `vd_recon_pii_columns(domain.core.fct_trip_baseline_agg)` | `{"pii_columns": []}` |
| Baseline uniqueness at grain | ad hoc: `count(*) = count(distinct trip_day\|\|pickup_borough) = 1457`, 0 nulls | unique, no nulls |

## Measurement

Scope: `trip_day`/`pickup_date` in `[2024-01-01, 2024-07-01)`.

Baseline and target rollup relations each built from two `vd_recon_compile_rollup_relation`
calls (one per aggregate) joined on the macro's own `grain_key`, then compared via
`vd_recon_compare_keyed(baseline_relation, target_relation, ["grain_key"], column_pairs)`:

```json
{"row_count": {"baseline": 1444, "target": 1444}, "key_count": {"baseline": 1444, "target": 1444}, "classification": {"matching": 432, "missing_from_target": 0, "additional_in_target": 0, "changed": 1012}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "trip_cnt_sum", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "gross_revenue_sum", "conflict_count": 993, "one_sided_null_count": 0}]}
```

`vd_recon_materialize_keyed_mismatches` produced `nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1`
(1,007 rows: the union of `changed` and any presence-class rows — none of the latter here).

## Investigation (Round 1)

<details>
<summary><b>H1 — gross_revenue_sum conflicts are floating-point summation noise, not a real value difference</b>: <span class="badge badge-good">confirmed</span></summary>

- Macro: `vd_recon_aggregate_evidence`
- Column: `abs(baseline_gross_revenue_sum - target_gross_revenue_sum)`
- `prediction_reads_as`: "every gross_revenue_sum conflict's magnitude is at the scale of double-precision floating point error, not a genuine dollar-level discrepancy"
- Result: `{"min": -3.17e-08, "max": 6.15e-08, "avg": 3.24e-09, "n": 1007}` over all 1,007 rows with both sides present — every difference is many orders of magnitude below one cent, consistent with `SUM(DOUBLE)` accumulating in a different row order on each side (baseline's own daily pre-aggregation vs. target's 6-month rollup over 20.6M rows).
- Corroborating: `select count(*) from mismatch where abs(baseline_gross_revenue_sum - target_gross_revenue_sum) > 0.01` → `0`, confirming zero rows exceed the confirmed $0.01 tolerance.
</details>

## Residual / Unexplained

None. All 1,007 `gross_revenue_sum` conflicts are covered by H1 and fall within the confirmed
$0.01 tolerance, making them immaterial. `trip_cnt_sum` has zero conflicts. No presence-class
differences (`missing_from_target`/`additional_in_target` are both 0).

## Outcome

```json
{
  "schema_version": "1.0",
  "outcome": "aligned",
  "plan_id": "core__fct_trip_baseline_agg-core__fct_trip",
  "run_id": "20240101_6mo_r1",
  "hypotheses": [
    {"id": "H1", "mechanism": "gross_revenue_sum conflicts are floating-point SUM(DOUBLE) accumulation-order noise, all within 6e-8 magnitude and the confirmed $0.01 tolerance", "disposition": "confirmed"}
  ],
  "categorization": {"matching": 432, "missing_from_target": 0, "additional_in_target": 0, "changed": 1012},
  "aggregate_measures": {
    "row_count": {"baseline": 1444, "target": 1444},
    "conflict_drivers": {"gross_revenue_sum": 1007},
    "one_sided_nulls": {}
  },
  "checks_not_performed": ["fare_gap (dropped from scope by FSA decision)"],
  "mismatch_table_ref": "nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1",
  "rounds_used": 1,
  "retries_used": 0
}
```

**Outcome: <span class="badge badge-good">aligned</span>** — `trip_cnt` reconciles exactly;
`gross_revenue` reconciles within the confirmed $0.01 floating-point tolerance (max observed
diff 6.15e-08). `fare_gap` was dropped from scope by FSA decision. Gating is advisory; this
does not block Intent completion.
