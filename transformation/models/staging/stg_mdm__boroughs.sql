select
    borough_name,
    borough_code,
    reporting_region,
    resident_population,
    area_sq_mi,
    is_nyc,
    is_core_market
from {{ source('mdm_raw', 'borough_master') }}
