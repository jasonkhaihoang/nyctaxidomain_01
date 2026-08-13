-- The cross-layer model. silver.trips is the conformed intersection of the two
-- fleet schemas, so the fleet-specific columns ADR 0001 dropped have to be
-- rejoined from bronze by recomputing the natural key on both sides.
--
-- Both joins are optional many-to-one: a yellow trip has at most one yellow
-- extras row and no green one. Multiplication here would be a defect, which is
-- why the staging models deduplicate rather than leaving it to this join.
select
    t.*,
    y.airport_fee,
    g.ehail_fee,
    g.trip_type,
    -- Green never carries an airport fee. Distinguishing "no such column for
    -- this fleet" from "column present but null" is what stops a fleet-blind
    -- average from silently treating one as the other.
    case when t.service_type = 'green' then 'not_applicable'
         when y.airport_fee is null     then 'missing'
         else 'present' end                            as airport_fee_status
from {{ ref('stg_tlc__trips') }} t
left join {{ ref('stg_tlc__yellow_trip_extras') }} y on t.trip_key = y.trip_key
left join {{ ref('stg_tlc__green_trip_extras') }}  g on t.trip_key = g.trip_key
