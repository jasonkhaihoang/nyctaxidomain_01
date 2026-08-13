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

_In progress — to be completed via `vd_recon_compile_rollup_relation` +
`vd_recon_compare_keyed`/`vd_recon_materialize_keyed_mismatches`, one call per
measure (`trip_cnt`, `gross_revenue`, `fare_gap`), scoped to
`[2024-01-01, 2024-07-01)`._
