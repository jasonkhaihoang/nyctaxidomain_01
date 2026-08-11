select
    rate_code_id,
    rate_code_desc as rate_code_name
from {{ source('silver', 'rate_codes') }}
