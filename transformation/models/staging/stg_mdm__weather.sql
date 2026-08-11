select
    observation_id,
    obs_date,
    borough_name,
    temp_avg_f,
    precip_inches,
    snow_inches,
    wind_mph,
    precip_inches > 0.10                      as is_wet_day,
    snow_inches  > 0.50                       as is_snow_day
from {{ source('mdm_raw', 'weather_daily') }}
