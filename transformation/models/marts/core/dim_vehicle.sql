-- Type 1: current vehicle state, with maintenance downtime folded in because
-- a vehicle out of the shop for a week is not an underperforming vehicle.
with downtime as (
    select vehicle_id,
           count(*)          as maintenance_events,
           sum(down_days)    as maintenance_down_days,
           sum(cost_usd)     as maintenance_cost_usd
    from {{ ref('stg_ops__maintenance') }}
    group by 1
)

select
    v.vehicle_id                                          as vehicle_key,
    v.medallion_number,
    v.vin,
    v.make,
    v.model,
    v.make || ' ' || v.model                              as make_model,
    v.model_year,
    date_part('year', date '2024-07-01') - v.model_year    as vehicle_age_years,
    v.fuel_type,
    v.fuel_type in ('hybrid', 'electric')                  as is_low_emission,
    v.wheelchair_accessible,
    v.garage_key_src                                       as garage_key,
    g.garage_name,
    v.in_service_date,
    v.retired_date,
    v.is_in_service,
    coalesce(d.maintenance_events, 0)                      as maintenance_events,
    coalesce(d.maintenance_down_days, 0)                   as maintenance_down_days,
    coalesce(d.maintenance_cost_usd, 0)                    as maintenance_cost_usd
from (select *, garage_id as garage_key_src from {{ ref('stg_ops__vehicles') }}) v
left join {{ ref('stg_ops__garages') }} g on v.garage_key_src = g.garage_id
left join downtime d                      on v.vehicle_id     = d.vehicle_id
