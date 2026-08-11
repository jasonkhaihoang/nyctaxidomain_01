-- Decomposes each trip total into its parts and states what is left over.
--
-- The residual is the point of this model. A total that does not equal the sum
-- of its documented components means either a component TLC added that we do
-- not model, or a total that was not derived from its parts at all. Either way
-- it is a finding, and it is invisible unless something computes it.
select
    t.trip_key,
    t.service_type,
    t.pickup_date,
    t.fare_amount,
    t.tip_amount,
    t.tolls_amount,
    t.extra,
    t.mta_tax,
    t.improvement_surcharge,
    t.congestion_surcharge,
    coalesce(t.airport_fee, 0)                        as airport_fee,
    t.total_amount,
    {{ total_surcharges('t') }}                       as total_surcharges,
    {{ fare_residual('t') }}                          as fare_residual,
    abs({{ fare_residual('t') }}) > 0.01              as has_unexplained_residual,
    {{ safe_divide('t.tip_amount', 't.fare_amount') }} as tip_rate_on_fare,
    -- Only meaningful where the meter actually captures tips. Cash tips are
    -- never recorded, so a cash trip's zero is not a zero.
    case when p.tip_is_captured
         then {{ safe_divide('t.tip_amount', 't.fare_amount') }} end as measurable_tip_rate,
    p.tip_is_captured,
    p.counts_as_revenue,
    p.settlement_class
from {{ ref('int_trips_enriched') }} t
left join {{ ref('stg_mdm__payment_methods') }} p on t.payment_type = p.payment_type
