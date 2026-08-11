select
    rate_code_id,
    rate_code_name
from {{ ref('stg_silver__rate_codes') }}
