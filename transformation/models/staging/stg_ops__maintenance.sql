select
    maintenance_id,
    vehicle_id,
    started_date,
    down_days,
    started_date + to_days(down_days::integer)  as ended_date,
    maintenance_type,
    cost_usd
from {{ source('ops_raw', 'maintenance_event') }}
