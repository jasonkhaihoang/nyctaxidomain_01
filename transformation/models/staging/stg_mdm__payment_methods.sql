select
    payment_type_code                         as payment_type,
    payment_method_name,
    settlement_class,
    tip_is_captured,
    settlement_days,
    processor_fee_pct,
    counts_as_revenue
from {{ source('mdm_raw', 'payment_method_master') }}
