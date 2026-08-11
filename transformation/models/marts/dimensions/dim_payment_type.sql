select
    payment_type_id,
    payment_type_name
from {{ ref('stg_silver__payment_types') }}
