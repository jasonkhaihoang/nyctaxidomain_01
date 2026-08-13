select
    driver_id,
    hack_licence_no,
    driver_ref,
    engagement_type,
    home_garage_id,
    hire_date,
    termination_date,
    is_wav_certified,
    driver_status
from {{ source('ops_raw', 'driver') }}
