-- Monthly volume and revenue by fleet and payment method, for Operations
-- reporting. Carries the settlement class so that a receivable can be told
-- apart from cash already in hand.
select
    date_trunc('month', f.pickup_datetime)                 as trip_month,
    f.service_type_key                                     as service_type,
    p.payment_method_name,
    p.settlement_class,
    p.counts_as_revenue,
    count(*)                                               as trip_count,
    sum(f.trip_distance)                                   as total_miles,
    sum(f.total_amount)                                    as total_revenue,
    avg(f.total_amount)                                    as avg_fare,
    sum(f.total_amount * p.processor_fee_pct)              as est_processor_fees
from {{ ref('fct_trip') }} f
join {{ ref('dim_payment_method') }} p on f.payment_method_key = p.payment_method_key
where {{ in_report_window('f.pickup_datetime') }}
  and f.is_billable
group by 1,2,3,4,5
