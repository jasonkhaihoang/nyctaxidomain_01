-- Bridge for the many-to-many between zones and points of interest.
--
-- A weighting factor is carried so that an allocated measure can be split
-- across a zone's categories without double counting. Any join through this
-- bridge multiplies rows by design, and that is exactly why it is a separate
-- object rather than a column on dim_zone.
with weights as (
    select location_id, sum(demand_weight) as total_weight
    from {{ ref('stg_mdm__zone_poi') }}
    group by 1
)

select
    p.poi_id,
    p.location_id                                         as zone_natural_key,
    p.poi_category,
    p.poi_category_name,
    p.poi_name,
    p.demand_weight,
    {{ safe_divide('p.demand_weight', 'w.total_weight') }} as allocation_factor
from {{ ref('stg_mdm__zone_poi') }} p
join weights w on p.location_id = w.location_id
