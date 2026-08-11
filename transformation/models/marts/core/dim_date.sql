-- Date spine over the calendar master, with the derived parts every rollup
-- needs. Holiday and school-term flags come from master data rather than being
-- computed, so a calendar correction restates reports without a code change.
select
    cast(strftime(c.calendar_date, '%Y%m%d') as integer)  as date_key,
    c.calendar_date,
    extract(year    from c.calendar_date)                 as calendar_year,
    extract(quarter from c.calendar_date)                 as calendar_quarter,
    extract(month   from c.calendar_date)                 as calendar_month,
    strftime(c.calendar_date, '%B')                       as month_name,
    extract(week    from c.calendar_date)                 as iso_week,
    date_trunc('month', c.calendar_date)                  as month_start_date,
    date_trunc('week',  c.calendar_date)                  as week_start_date,
    dayofweek(c.calendar_date)                            as day_of_week,
    strftime(c.calendar_date, '%A')                       as day_name,
    c.is_weekend,
    c.is_holiday,
    c.holiday_name,
    c.holiday_class,
    c.is_school_term,
    -- A holiday falling on a weekday behaves like a weekend for demand, which
    -- is why the two flags are kept separate and a third combines them.
    (c.is_weekend or c.is_holiday)                        as is_non_working_day
from {{ ref('stg_mdm__calendar') }} c
