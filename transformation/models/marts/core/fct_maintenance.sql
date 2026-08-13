-- Vehicle downtime. A semi-additive fact: down-days sum across vehicles but
-- not across overlapping date ranges, so any availability calculation has to
-- expand this to a daily grain rather than summing the column.
select
    m.maintenance_id,
    m.vehicle_id                                           as vehicle_key,
    v.garage_key,
    cast(strftime(m.started_date, '%Y%m%d') as integer)    as started_date_key,
    m.started_date,
    m.ended_date,
    m.down_days,
    m.maintenance_type,
    m.cost_usd
from {{ ref('stg_ops__maintenance') }} m
left join {{ ref('dim_vehicle') }} v on m.vehicle_id = v.vehicle_key
