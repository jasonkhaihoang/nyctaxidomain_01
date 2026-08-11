-- Current-version zone attributes, with the borough rollup and a point-of-
-- interest summary folded in.
--
-- Two things worth knowing. First, zone_master is versioned at source, so the
-- current-version filter is mandatory -- without it every trip joining a
-- re-designated zone doubles. Second, POIs are many-to-many, so they are
-- aggregated to one row per zone here and left as a bridge for anything that
-- needs to slice by category.
with current_zone as (
    select *
    from {{ ref('stg_mdm__zones') }}
    where valid_to_date = date '2099-12-31'
),

poi_rollup as (
    select
        location_id,
        count(*)                                     as poi_count,
        sum(demand_weight)                           as poi_demand_weight,
        max(case when poi_category = 'AIRPORT' then 1 else 0 end) = 1 as has_airport_poi,
        string_agg(distinct poi_category, ',')        as poi_categories
    from {{ ref('stg_mdm__zone_poi') }}
    group by 1
)

select
    z.location_id,
    z.zone_name,
    z.borough_name,
    b.borough_code,
    b.reporting_region,
    b.is_nyc,
    b.is_core_market,
    z.tlc_service_zone,
    z.zone_class,
    z.demand_tier,
    z.centroid_lat,
    z.centroid_lon,
    z.area_sq_mi,
    z.resident_population,
    z.is_airport_zone,
    z.is_congestion_zone,
    -- TLC emits 264 and 265 for pickups it could not resolve. They join the
    -- lookup cleanly, which is exactly why they are dangerous: the failure is
    -- a meaningless borough, not an unmatched row.
    z.borough_name in ('Unknown', 'N/A')             as is_unresolved_zone,
    coalesce(p.poi_count, 0)                          as poi_count,
    coalesce(p.poi_demand_weight, 0)                  as poi_demand_weight,
    coalesce(p.has_airport_poi, false)                as has_airport_poi,
    p.poi_categories
from current_zone z
left join {{ ref('stg_mdm__boroughs') }} b on z.borough_name = b.borough_name
left join poi_rollup p                     on z.location_id  = p.location_id
