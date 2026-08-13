# Recon Pair: `core.fct_trip_baseline_agg` (Baseline) vs `core.fct_trip` (Target)

## Confirmed contract

- **Baseline:** `nyctaxi.core.fct_trip_baseline_agg`
- **Target:** `nyctaxi.core.fct_trip`, rolled up to the Baseline's grain
- **Source premise:** FSA-confirmed — both derive from the same direct TLC trip source.
  `fct_trip_baseline_agg` has no dbt manifest node (not a modeled relation in this
  repo), so lineage could not be traced; recorded as a `source_fallback_declaration`,
  not a traced `source_lineage`. Independently corroborated by data fingerprint:
  dataset-wide row count matches exactly (20,671,899 = 20,671,899) and
  `pickup_date`/`trip_day` boundaries coincide exactly (`2002-12-31` to `2026-06-26`)
  on both sides.
- **Scope:** `pickup_date`/`trip_day` in `[2024-01-01, 2024-07-01)`. The dataset-wide
  boundary max (`2026-06-26`) and several other dates (`2002-12-31`, `2008-12-31`,
  `2009-01-01`, `2023-12`) are sparse noise carrying only 2-3 trips each — not the
  tail of a live feed. The dense block `2024-01` through `2024-06` carries
  20,671,854 of the dataset's 20,671,899 trips (99.9998%). A literal "latest 6
  calendar months by max date" window (`2025-12-26` to `2026-06-26`) would net only
  ~2 trips and trivially reach `aligned` with no real signal, so the dense block was
  used instead as the FSA-actionable interpretation of "latest 6 months"; flagged
  here for correction if a literal calendar-tail window was intended instead.
- **Common grain:** `(trip_day, pickup_borough)` — the coarser (Baseline) side.
  Target rolled up via `vd_recon_compile_rollup_relation`.
- **Mode:** Keyed, on a synthetic `grain_key` over `(trip_day, pickup_borough)`.
  Baseline key uniqueness confirmed dataset-wide: 1,457 total = 1,457 distinct, 0 nulls.
- **Gating:** Advisory (never blocks Intent completion).
- **Round cap:** 5 (default), raisable by the FSA without ceiling.

### Column mapping

| Baseline | Target derivation | Cast | Justification |
| --- | --- | --- | --- |
| `trip_day` | `fct_trip.pickup_date` | none | direct, native, identical type (DATE) |
| `pickup_borough` | `dim_zone.borough_name`, joined via `fct_trip.pickup_zone_key = dim_zone.zone_key` | none | reuses `fct_trip.sql`'s own manifest-declared as-of join to `dim_zone` (traced key: `dim_zone.zone_key`, `unique`+`not_null`); not a new join invented for this comparison |
| `trip_cnt` | `count(*)` | none | aggregate over the common grain |
| `gross_revenue` | `sum(total_amount)` | none | aggregate over the common grain |
| `fare_gap` | `sum(coalesce(congestion_surcharge, 0) + fare_residual)` | none | **empirically derived, not read from a manifest expression** — `fare_gap` has no Target counterpart column, so AC-80/81's expression-grounding gate cannot narrow it from a compiled expression. Carried into Measurement as a `derived_expression` hypothesis to confirm, not a given. |

### Source relations (reach extension)

| Relation | Key | `key_source` | Role |
| --- | --- | --- | --- |
| `nyctaxi.core.dim_zone` | `zone_key` | `traced` (manifest `unique`+`not_null` test) | Resolves `pickup_borough` via `fct_trip.pickup_zone_key` |

### PII

`vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline_agg)` → `[]`. No PII gating required.

### Tolerance

Exact on all three measures (`trip_cnt`, `gross_revenue`, `fare_gap`) — no rounding or
proportional-tolerance justification found in schema or profiling.

### Profiling evidence (Negotiate step)

| Check | Macro | Result |
| --- | --- | --- |
| Target schema | `vd_recon_schema_probe(nyctaxi.core.fct_trip)` | 40 columns |
| Baseline schema | `vd_recon_schema_probe(nyctaxi.core.fct_trip_baseline_agg)` | 5 columns: `trip_day`, `pickup_borough`, `trip_cnt`, `gross_revenue`, `fare_gap` |
| Baseline key uniqueness | `vd_recon_key_uniqueness(nyctaxi.core.fct_trip_baseline_agg, ["trip_day","pickup_borough"])` | `{"total": 1457, "distinct": 1457, "nulls": 0}` |
| Source-relation key uniqueness | `vd_recon_key_uniqueness(nyctaxi.core.dim_zone, ["zone_key"])` | `{"total": 272, "distinct": 272, "nulls": 0}` |
| Target boundaries (`pickup_date`) | `vd_recon_probe_boundaries(nyctaxi.core.fct_trip, "pickup_date")` | `{"min": "2002-12-31", "max": "2026-06-26", "count": 20671899}` |
| Baseline boundaries (`trip_day`) | `vd_recon_probe_boundaries(nyctaxi.core.fct_trip_baseline_agg, "trip_day")` | `{"min": "2002-12-31", "max": "2026-06-26", "count": 1457}` |
| Baseline PII columns | `vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline_agg)` | `{"pii_columns": []}` |
| Dataset-wide source-sharedness fingerprint | ad-hoc bounded SQL | row counts equal (20,671,899=20,671,899); date boundaries equal on both sides |
| Dense-window volume check | ad-hoc bounded SQL | 20,671,854 of 20,671,899 trips (99.9998%) fall in `[2024-01-01, 2024-07-01)`; all other months carry 2-12 trips only |

## Measurement

Each measure was rolled up via `vd_recon_compile_rollup_relation` (Target side folds
the manifest-traced `fct_trip → dim_zone` join and the confirmed date-scope filter
into its `relation` argument, per this repo's own established practice of folding
casts/filters into `baseline_relation`/`target_relation` — see the sibling
`fct_trip_baseline` pair's Amendment 1/2), then compared via `vd_recon_compare_keyed`
on a synthetic `grain_key` over `(trip_day, pickup_borough)`.

### `trip_cnt`

`vd_recon_compare_keyed(...)`:

```json
{"row_count": {"baseline": 1444, "target": 1444}, "key_count": {"baseline": 1444, "target": 1444}, "classification": {"matching": 1444, "missing_from_target": 0, "additional_in_target": 0, "changed": 0}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "trip_cnt", "conflict_count": 0, "one_sided_null_count": 0}]}
```

Exact match, no investigation needed. Material population: empty.

### `gross_revenue`

`vd_recon_compare_keyed(...)`:

```json
{"row_count": {"baseline": 1444, "target": 1444}, "key_count": {"baseline": 1444, "target": 1444}, "classification": {"matching": 421, "missing_from_target": 0, "additional_in_target": 0, "changed": 1023}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "gross_revenue", "conflict_count": 1006, "one_sided_null_count": 0}]}
```

`vd_recon_materialize_keyed_mismatches(...)` → `{"mismatch_table_ref": "nyctaxi.main.vd_recon_mismatch_6mo_gross_revenue_final", "row_count": 1013, "source_relations_excluded": []}`.

### `fare_gap`

`vd_recon_compare_keyed(...)`:

```json
{"row_count": {"baseline": 1444, "target": 1444}, "key_count": {"baseline": 1444, "target": 1444}, "classification": {"matching": 1035, "missing_from_target": 0, "additional_in_target": 0, "changed": 409}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "fare_gap", "conflict_count": 414, "one_sided_null_count": 0}]}
```

`vd_recon_materialize_keyed_mismatches(...)` → `{"mismatch_table_ref": "nyctaxi.main.vd_recon_mismatch_6mo_fare_gap_final", "row_count": 418, "source_relations_excluded": []}`.

## Investigation

<details>
<summary><b>H0 — gross_revenue/fare_gap classification counts fluctuate run-to-run due to DuckDB parallel floating-point summation, not a real data instability</b>: <span class="badge badge-good">confirmed</span></summary>

Both `gross_revenue` (`sum(total_amount)`) and `fare_gap`
(`sum(coalesce(congestion_surcharge,0) + fare_residual)`) aggregate `DOUBLE` columns.
Re-running the identical `vd_recon_compare_keyed` call against `gross_revenue`
three consecutive times produced `changed` counts of 1017, 1006, and 1026 (and a
fourth, frozen run used for Measurement above: 1023) — the exact-equality boundary
shifts by roughly 1% between runs because DuckDB's parallel aggregation does not
guarantee bit-identical summation order every execution. `row_count`/`key_count`
(1444/1444 both sides, every run) never varied — only which individual rows tip
across the `is distinct from` boundary. This is a floating-point-precision artifact
of the comparison mechanism itself (mechanism: `cast`/precision, closest fit in the
mechanism vocabulary), not evidence of a real, reproducible data mismatch.

- Evidence: 4 independent `vd_recon_compare_keyed` calls, identical
  `baseline_relation`/`target_relation`/`column_pairs`, `changed` count varying
  {1017, 1006, 1026, 1023} while `row_count`/`key_count` held constant at
  `{"baseline": 1444, "target": 1444}` every time.
- `prediction_reads_as`: "the classification boundary for a DOUBLE-typed sum column
  is not stable across repeated identical executions of the same comparison query"
- Consequence: the frozen `vd_recon_materialize_keyed_mismatches` table (run
  immediately after the reported `vd_recon_compare_keyed` call) is treated as the
  canonical evidence set for H1 below, rather than re-running comparisons
  repeatedly and picking a result.

</details>

<details>
<summary><b>H1 — every gross_revenue/fare_gap conflict is within $0.01 floating-point tolerance; fare_gap's candidate formula (<code>sum(coalesce(congestion_surcharge,0) + fare_residual)</code>) is correct</b>: <span class="badge badge-good">confirmed</span></summary>

`fare_gap` has no Target counterpart column (AC-80/81's expression-grounding gate
falls back to the full column inventory, per the confirmed contract's PENDING note),
so its mapping was carried as an unconfirmed `derived_expression` hypothesis into
Measurement rather than a given mapping. Both this hypothesis and the
`gross_revenue` float-tolerance finding are confirmed together, since fare_gap's
mismatch shape is identical to gross_revenue's.

- Macro: `vd_recon_predict`
- Predicate (`gross_revenue`): `abs(baseline_gross_revenue - target_gross_revenue) < 0.01`
- `prediction_reads_as`: "every gross_revenue conflict row's baseline/target values differ by less than one cent"
- `compiled_query`: `select count(*) as n from nyctaxi.main.vd_recon_mismatch_6mo_gross_revenue_final where abs(("baseline_gross_revenue" - "target_gross_revenue")) < 0.01`
- Result: `matched_count: 1013` — the full mismatch-table row count (1013/1013).

- Predicate (`fare_gap`): `abs(baseline_fare_gap - target_fare_gap) < 0.01`
- `prediction_reads_as`: "every fare_gap conflict row's baseline/target values differ by less than one cent, using the candidate formula sum(coalesce(congestion_surcharge,0) + fare_residual)"
- `compiled_query`: `select count(*) as n from nyctaxi.main.vd_recon_mismatch_6mo_fare_gap_final where abs(("baseline_fare_gap" - "target_fare_gap")) < 0.01`
- Result: `matched_count: 418` — the full mismatch-table row count (418/418), simultaneously confirming the candidate `fare_gap` formula (a wrong formula would show conflicts far larger than one cent, not a tight sub-cent band).

</details>

## Residual / Unexplained

None. `trip_cnt`'s material population is empty (exact match). `gross_revenue`'s and
`fare_gap`'s full mismatch populations (1013 and 418 rows respectively, from their
frozen materialized tables) are each fully confirmed within H1's sub-cent
floating-point tolerance.

## Outcome

```json
{
  "schema_version": "1.0",
  "outcome": "divergent-explained",
  "plan_id": "core__fct_trip_baseline_agg-core__fct_trip",
  "run_id": "6mo_final",
  "hypotheses": [
    {"id": "H0", "mechanism": "cast (floating-point precision): DOUBLE-typed sum columns produce run-to-run non-deterministic classification boundaries under DuckDB parallel aggregation", "disposition": "confirmed"},
    {"id": "H1", "mechanism": "derived_expression + cast: fare_gap = sum(coalesce(congestion_surcharge,0) + fare_residual); all gross_revenue/fare_gap conflicts are within $0.01 floating-point tolerance", "disposition": "confirmed"}
  ],
  "categorization": {
    "trip_cnt": {"matching": 1444, "missing_from_target": 0, "additional_in_target": 0, "changed": 0},
    "gross_revenue": {"matching": 421, "missing_from_target": 0, "additional_in_target": 0, "changed": 1023},
    "fare_gap": {"matching": 1035, "missing_from_target": 0, "additional_in_target": 0, "changed": 409}
  },
  "aggregate_measures": {
    "row_count": {"baseline": 1444, "target": 1444},
    "conflict_drivers": {"gross_revenue": 1013, "fare_gap": 418},
    "one_sided_nulls": {}
  },
  "checks_not_performed": [],
  "mismatch_table_ref": "nyctaxi.main.vd_recon_mismatch_6mo_gross_revenue_final; nyctaxi.main.vd_recon_mismatch_6mo_fare_gap_final",
  "rounds_used": 1,
  "retries_used": 0
}
```

**Outcome: <span class="badge badge-good">divergent-explained</span>** —
`trip_cnt` matches exactly; `gross_revenue` and `fare_gap` each show conflicts,
but every conflicting unit in both materialized mismatch tables is confirmed within
H1's sub-cent floating-point tolerance (a DOUBLE-precision artifact of parallel
summation, not a semantic defect), and `fare_gap`'s previously-unconfirmed formula
is validated as `sum(coalesce(congestion_surcharge, 0) + fare_residual)`. Gating is
advisory; this does not block Intent completion.

**Note on scope:** the confirmed scope is the dense 6-month block
`[2024-01-01, 2024-07-01)`, not a literal "latest 6 calendar months by max date" —
see the Scope entry under Confirmed contract above for why. Flagged for correction
if a literal calendar-tail window was actually intended.
