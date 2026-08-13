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
| fare_gap | fare_residual + congestion_surcharge | sum | `t.fare_residual + coalesce(t.congestion_surcharge, 0)` | **Amendment 3 (re-scoped in):** re-mapped from "no target equivalent" to `fare_residual + congestion_surcharge` after H2 (below) confirmed the relationship. `congestion_surcharge` is nullable (unset before congestion pricing zones/dates) — `coalesce(..., 0)` is required, or the additive NULL silently drops the whole row's `fare_residual` from `SUM()`, not just the surcharge (diagnosed as H1 below). |

Target's remaining columns (all row-level fare/trip attributes not entering `trip_cnt` or
`gross_revenue`) have no baseline counterpart at this grain and are out of scope.

### PII

`vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline_agg)` → `[]`. No PII gating required.

### Tolerance

- Exact: `trip_cnt_sum`
- Fixed tolerance $0.01: `gross_revenue_sum`, `fare_gap_sum` (both account for floating-point `SUM(DOUBLE)` accumulation order differences between baseline's pre-aggregation and target's rollup)

## Amendment 3 — `fare_gap` re-scoped in (user request, this run)

FSA requested `fare_gap` be brought back into scope, mapped to `fare_residual` — the same
column identified but not confirmed in the prior run's column-mapping search. Re-running the
full pipeline (rollup → compare → materialize → investigate → categorize → outcome) with all
three metrics (`trip_cnt`, `gross_revenue`, `fare_gap`) in scope. No other part of the
confirmed contract (grain, key, window, gating, round cap) changes.

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

Baseline and target rollup relations each built from three `vd_recon_compile_rollup_relation`
calls (one per aggregate: `trip_cnt`, `gross_revenue`, `fare_gap`), joined on the macro's own
`grain_key`, then compared via `vd_recon_compare_keyed(baseline_relation, target_relation,
["grain_key"], column_pairs)`. First attempt mapped `fare_gap` naively to bare
`fare_residual` and found 1,133 conflicts including 9 one-sided nulls (target null,
baseline non-null); root-caused (H1 below) to `congestion_surcharge` being nullable and used
additively without `coalesce`, silently dropping matching rows' entire `fare_residual`
contribution from the `SUM()`. Final mapping is
`fare_residual + coalesce(congestion_surcharge, 0)`:

```json
{"row_count": {"baseline": 1444, "target": 1444}, "key_count": {"baseline": 1444, "target": 1444}, "classification": {"matching": 354, "missing_from_target": 0, "additional_in_target": 0, "changed": 1090}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "trip_cnt_sum", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "gross_revenue_sum", "conflict_count": 1008, "one_sided_null_count": 0}, {"column": "fare_gap_sum", "conflict_count": 426, "one_sided_null_count": 0}]}
```

`vd_recon_materialize_keyed_mismatches` produced
`nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1_faregap3` (1,092 rows: the union of `changed`
and any presence-class rows — none of the latter here; zero one-sided nulls, zero
missing/additional rows on either side).

## Investigation (Round 1)

<details>
<summary><b>H1 — a naive fare_residual + congestion_surcharge mapping loses rows to NULL propagation</b>: <span class="badge badge-good">confirmed</span></summary>

Initial attempt mapped `fare_gap` to bare `fare_residual + congestion_surcharge` and
produced 1,133 conflicts, 9 with a one-sided null on the target side, and diffs up to
$63,494.25 — clearly material, not noise.

- Direct inspection: `congestion_surcharge` is `NULL` for trips outside congestion-pricing
  zones/dates (e.g. `pickup_date = '2024-01-13'`, `pickup_borough = 'Staten Island'`: 1 row,
  `congestion_surcharge IS NULL`, `fare_residual = 2.5`). In SQL, `x + NULL = NULL`, so
  `SUM(fare_residual + congestion_surcharge)` drops that row's `fare_residual` from the sum
  entirely, not just the missing surcharge — corrupting every grain cell containing at least
  one such trip.
- Fix: `fare_residual + coalesce(congestion_surcharge, 0)`. Re-running the target rollup with
  the corrected expression eliminated all 9 one-sided nulls and reduced conflicts from 1,133
  to 426, with max diff dropping from $266,609.5 to 5.8e-11 — see H2.
</details>

<details>
<summary><b>H2 — remaining fare_gap_sum conflicts are floating-point summation noise, not a real value difference</b>: <span class="badge badge-good">confirmed</span></summary>

- Macro: `vd_recon_aggregate_evidence`
- Column: `abs(baseline_fare_gap_sum - target_fare_gap_sum)`
- `prediction_reads_as`: "every remaining fare_gap_sum conflict's magnitude is at the scale of double-precision floating point error, not a genuine dollar-level discrepancy"
- Result: `{"min": 5.55e-17, "max": 5.82e-11, "avg": 9.38e-13, "n": 422}` over all 422 rows with both sides present, after the H1 fix — every difference is many orders of magnitude below one cent.
- Corroborating: `select count(*) from mismatch where abs(baseline_fare_gap_sum - target_fare_gap_sum) > 0.01` → `0`, confirming zero rows exceed the confirmed $0.01 tolerance.
</details>

<details>
<summary><b>H3 — gross_revenue_sum conflicts are floating-point summation noise, not a real value difference</b>: <span class="badge badge-good">confirmed</span></summary>

Same mechanism and evidence as the prior run's H1 (unaffected by the `fare_gap` remapping,
since `gross_revenue`'s own mapping is unchanged): `{"min": -3.17e-08, "max": 6.15e-08, "avg": 3.24e-09, "n": 1007}` over all 1,007 conflicting rows; `0` rows exceed the $0.01 tolerance.
</details>

## Residual / Unexplained

None. All 422 `fare_gap_sum` conflicts (post-H1-fix) are covered by H2, and all 1,007
`gross_revenue_sum` conflicts are covered by H3 — both fall within the confirmed $0.01
tolerance, making them immaterial. `trip_cnt_sum` has zero conflicts. No presence-class
differences (`missing_from_target`/`additional_in_target` are both 0; zero one-sided nulls
after the H1 fix).

## Outcome

```json
{
  "schema_version": "1.0",
  "outcome": "aligned",
  "plan_id": "core__fct_trip_baseline_agg-core__fct_trip",
  "run_id": "20240101_6mo_r1_faregap3",
  "hypotheses": [
    {"id": "H1", "mechanism": "naive fare_residual + congestion_surcharge mapping loses rows to NULL propagation when congestion_surcharge is unset; fixed with coalesce(congestion_surcharge, 0)", "disposition": "confirmed"},
    {"id": "H2", "mechanism": "post-fix fare_gap_sum conflicts are floating-point SUM(DOUBLE) accumulation-order noise, all within 5.8e-11 magnitude and the confirmed $0.01 tolerance", "disposition": "confirmed"},
    {"id": "H3", "mechanism": "gross_revenue_sum conflicts are floating-point SUM(DOUBLE) accumulation-order noise, all within 6.15e-08 magnitude and the confirmed $0.01 tolerance", "disposition": "confirmed"}
  ],
  "categorization": {"matching": 354, "missing_from_target": 0, "additional_in_target": 0, "changed": 1090},
  "aggregate_measures": {
    "row_count": {"baseline": 1444, "target": 1444},
    "conflict_drivers": {"gross_revenue_sum": 1007, "fare_gap_sum": 422},
    "one_sided_nulls": {}
  },
  "checks_not_performed": [],
  "mismatch_table_ref": "nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1_faregap3",
  "rounds_used": 1,
  "retries_used": 0
}
```

**Outcome: <span class="badge badge-good">aligned</span>** — `trip_cnt` reconciles exactly;
`gross_revenue` and `fare_gap` both reconcile within the confirmed $0.01 floating-point
tolerance (max observed diffs 6.15e-08 and 5.82e-11 respectively) once `fare_gap` is mapped
to `fare_residual + coalesce(congestion_surcharge, 0)`. Gating is advisory; this does not
block Intent completion.
