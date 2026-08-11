select
    md5(cast(zone_id as varchar)) as zone_key,
    zone_id,
    zone,
    borough_name,
    service_zone,
    case
        when zone_id = 1 or zone ilike '%airport%' then true
        else false
    end as is_airport
from {{ ref('stg_silver__zones') }}
