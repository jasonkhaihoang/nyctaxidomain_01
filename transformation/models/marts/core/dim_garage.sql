select
    g.garage_id                                           as garage_key,
    g.garage_name,
    g.borough_name,
    g.bay_capacity,
    g.opened_date,
    count(v.vehicle_id)                                   as assigned_vehicle_count
from {{ ref('stg_ops__garages') }} g
left join {{ ref('stg_ops__vehicles') }} v on g.garage_id = v.garage_id
group by 1, 2, 3, 4, 5
