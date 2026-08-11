-- Vendor master, versioned at source. VendorID 2 has two versions across the
-- Curb Mobility rebrand.
select
    vendor_id,
    vendor_legal_name,
    vendor_short_code,
    contract_tier,
    is_approved,
    valid_from_date,
    valid_to_date,
    source_version
from {{ source('mdm_raw', 'vendor_master') }}
