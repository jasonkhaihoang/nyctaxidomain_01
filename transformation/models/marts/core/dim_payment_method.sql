select
    payment_type                                          as payment_method_key,
    payment_method_name,
    settlement_class,
    tip_is_captured,
    settlement_days,
    processor_fee_pct,
    counts_as_revenue
from {{ ref('stg_mdm__payment_methods') }}
