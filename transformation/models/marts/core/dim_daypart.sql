select
    hour_of_day,
    daypart_code,
    daypart_name,
    is_peak
from {{ ref('daypart_bands') }}
