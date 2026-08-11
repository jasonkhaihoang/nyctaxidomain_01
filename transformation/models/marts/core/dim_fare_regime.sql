-- Effective-dated surcharge rates. Not a conformed dimension of the trip fact;
-- it is joined on component and date to explain a surcharge, which is why it
-- keeps its own validity interval rather than being flattened into dim_date.
select
    regime_code                                           as fare_regime_key,
    fare_component,
    rate_amount,
    applies_to_fleet,
    valid_from_date,
    valid_to_date,
    valid_to_date = date '2099-12-31'                     as is_current_regime
from {{ ref('stg_mdm__fare_regimes') }}
