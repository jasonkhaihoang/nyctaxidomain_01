-- Type 2 vendor dimension, natural key `vendor_id`.
--
-- VendorID 2 has two versions across the July 2023 Curb Mobility rebrand. A
-- trip must resolve against the version in force when it happened, or a 2022
-- trip is attributed to a company that did not yet trade under that name.
select
    md5(v.vendor_id::varchar || '|' || v.valid_from_date::varchar) as vendor_key,
    v.vendor_id                                           as vendor_natural_key,
    v.source_version                                      as vendor_version,
    v.valid_from_date,
    v.valid_to_date,
    v.valid_to_date = date '2099-12-31'                   as is_current_version,
    v.vendor_legal_name,
    v.vendor_short_code,
    v.contract_tier,
    v.is_approved
from {{ ref('stg_mdm__vendors') }} v
