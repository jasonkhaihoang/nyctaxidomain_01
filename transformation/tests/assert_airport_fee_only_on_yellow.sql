-- ADR 0001 means green has no airport fee column at all. A non-null value on a
-- green trip would mean the natural-key rejoin matched across fleets, which
-- would corrupt every fee metric.
select trip_key, service_type, airport_fee
from {{ ref('int_trips_enriched') }}
where service_type = 'green' and airport_fee is not null
