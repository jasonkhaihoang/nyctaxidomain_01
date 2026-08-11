-- Type 2 zone dimension, natural key `location_id`.
--
-- Versioning is delivered by the master-data platform, not reconstructed here:
-- the source carries `valid_from_date` / `valid_to_date` and a version
-- number, and this model turns that into a surrogate-keyed dimension. Intervals
-- are half-open [from, to), so an as-of join uses >= and <, never BETWEEN --
-- BETWEEN is inclusive at both ends and double-counts on a changeover date.
with versioned as (
    select
        z.*,
        b.borough_code,
        b.reporting_region,
        b.is_nyc,
        b.is_core_market
    from {{ ref('stg_mdm__zones') }} z
    left join {{ ref('stg_mdm__boroughs') }} b on z.borough_name = b.borough_name
),

poi as (
    select location_id,
           count(*)                                      as poi_count,
           string_agg(distinct poi_category, ',')         as poi_categories
    from {{ ref('stg_mdm__zone_poi') }}
    group by 1
)

select
    md5(v.location_id::varchar || '|' || v.valid_from_date::varchar) as zone_key,
    v.location_id                                         as zone_natural_key,
    v.source_version                                      as zone_version,
    v.valid_from_date,
    v.valid_to_date,
    v.valid_to_date = date '2099-12-31'                   as is_current_version,
    v.zone_name,
    v.borough_name,
    v.borough_code,
    v.reporting_region,
    v.tlc_service_zone,
    v.zone_class,
    v.demand_tier,
    v.centroid_lat,
    v.centroid_lon,
    v.area_sq_mi,
    v.resident_population,
    v.is_airport_zone,
    v.is_congestion_zone,
    v.is_nyc,
    v.is_core_market,
    v.borough_name in ('Unknown', 'N/A')                  as is_unresolved_zone,
    coalesce(p.poi_count, 0)                              as poi_count,
    p.poi_categories
from versioned v
left join poi p on v.location_id = p.location_id
