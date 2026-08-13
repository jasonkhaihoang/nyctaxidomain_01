select
    calendar_date,
    holiday_name,
    holiday_class,
    is_holiday,
    is_weekend,
    is_school_term
from {{ source('mdm_raw', 'calendar_master') }}
