select
    rate_code                                 as rate_code_id,
    rate_plan_name,
    pricing_model,
    is_flat_fare,
    flat_fare_amount,
    is_airport_plan,
    is_metered_baseline
from {{ source('mdm_raw', 'rate_plan_master') }}
