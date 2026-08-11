select
    location_id as zone_id,
    borough as borough_name,
    zone_name as zone,
    service_zone
from {{ source('silver', 'zones') }}
