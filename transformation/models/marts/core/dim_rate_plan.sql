select
    rate_code_id                                          as rate_plan_key,
    rate_plan_name,
    pricing_model,
    is_flat_fare,
    flat_fare_amount,
    is_airport_plan,
    is_metered_baseline
from {{ ref('stg_mdm__rate_plans') }}
