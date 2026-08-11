-- Type 1: current driver state. Drivers change garage and status, but the
-- operator does not keep a history of it, so there is nothing to version --
-- claiming Type 2 here would be a dimension whose history is fabricated.
select
    d.driver_id                                           as driver_key,
    d.hack_licence_no,
    d.driver_ref,
    d.engagement_type,
    d.driver_status,
    d.is_wav_certified,
    d.hire_date,
    d.termination_date,
    date_diff('day', d.hire_date, date '2024-07-01')      as tenure_days,
    d.home_garage_id                                      as garage_key,
    g.garage_name                                         as home_garage_name,
    l.lease_id,
    l.lease_type,
    l.lease_rate,
    l.revenue_share_pct,
    l.primary_vehicle_id
from {{ ref('stg_ops__drivers') }} d
left join {{ ref('stg_ops__garages') }} g on d.home_garage_id = g.garage_id
left join {{ ref('stg_ops__leases') }}  l on d.driver_id      = l.driver_id
