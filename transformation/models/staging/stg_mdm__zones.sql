-- Zone master, versioned at source. Kept versioned here: collapsing to the
-- current row is the dimension's job, not staging's.
select
    location_id,
    borough_name,
    zone_label                                as zone_name,
    tlc_service_zone,
    zone_class,
    demand_tier,
    centroid_lat,
    centroid_lon,
    area_sq_mi,
    resident_population,
    is_airport_zone,
    is_congestion_zone,
    valid_from_date,
    valid_to_date,
    source_version,
    _load_id
from {{ source('mdm_raw', 'zone_master') }}
