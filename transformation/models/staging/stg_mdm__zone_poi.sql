-- Many-to-many by nature: one zone, several points of interest.
select
    poi_id,
    location_id,
    poi_category,
    poi_category_name,
    poi_name,
    demand_weight
from {{ source('mdm_raw', 'zone_poi') }}
