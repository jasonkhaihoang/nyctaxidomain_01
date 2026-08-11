select
    payment_type as payment_type_id,
    payment_type_desc as payment_type_name
from {{ source('silver', 'payment_types') }}
