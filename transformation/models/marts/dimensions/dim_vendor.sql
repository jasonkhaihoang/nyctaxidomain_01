select distinct
    vendor_id,
    case
        when vendor_id = 1 then 'Creative Mobile Technologies'
        when vendor_id = 2 then 'VeriFone Inc'
        else 'Unknown'
    end as vendor_name
from {{ ref('stg_silver__trips') }}
where vendor_id is not null
