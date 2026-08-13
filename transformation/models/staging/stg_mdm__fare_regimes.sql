select
    regime_code,
    fare_component,
    rate_amount,
    applies_to_fleet,
    valid_from_date,
    valid_to_date
from {{ source('mdm_raw', 'fare_regime_master') }}
