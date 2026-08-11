select
    garage_id,
    garage_name,
    borough                                   as borough_name,
    bay_capacity,
    opened_date
from {{ source('ops_raw', 'garage') }}
