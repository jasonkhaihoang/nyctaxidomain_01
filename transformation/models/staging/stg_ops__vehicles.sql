select
    vehicle_id,
    medallion_number,
    vin,
    make,
    model,
    model_year,
    fuel_type,
    wheelchair_accessible,
    garage_id,
    in_service_date,
    retired_date,
    retired_date is null                      as is_in_service
from {{ source('ops_raw', 'vehicle') }}
