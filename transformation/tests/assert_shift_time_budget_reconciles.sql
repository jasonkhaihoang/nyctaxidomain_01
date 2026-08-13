-- On-trip, available and break seconds must not exceed the shift's online
-- seconds. Exceeding it means overlapping intervals, which means the stream was
-- sessionized without partitioning correctly.
select shift_id, online_seconds,
       on_trip_seconds + available_seconds + break_seconds as accounted_seconds
from {{ ref('int_shift_occupancy') }}
where on_trip_seconds + available_seconds + break_seconds > online_seconds + 60
