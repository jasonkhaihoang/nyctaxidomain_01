-- Sessionizing on received time instead of event time inverts a small share of
-- events against their neighbour and produces negative durations. The interval
-- model floors at zero; this asserts the floor never had to bite widely.
select count(*) as negative_intervals
from {{ ref('int_status_intervals') }}
where is_negative_interval
having count(*) > 5000
