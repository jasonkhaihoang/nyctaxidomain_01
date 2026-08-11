with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2024-01-01' as date)",
        end_date="cast('2024-07-01' as date)"
    ) }}
),

enriched as (
    select
        cast(date_day as date) as calendar_date,
        cast(strftime(date_day, '%Y%m%d') as integer) as date_key,
        extract(year from date_day) as year,
        extract(quarter from date_day) as quarter,
        extract(month from date_day) as month,
        case extract(month from date_day)
            when 1 then 'January' when 2 then 'February' when 3 then 'March'
            when 4 then 'April' when 5 then 'May' when 6 then 'June'
            when 7 then 'July' when 8 then 'August' when 9 then 'September'
            when 10 then 'October' when 11 then 'November' when 12 then 'December'
        end as month_name,
        extract(dayofweek from date_day) as day_of_week,
        case extract(dayofweek from date_day)
            when 0 then 'Sunday' when 1 then 'Monday' when 2 then 'Tuesday'
            when 3 then 'Wednesday' when 4 then 'Thursday' when 5 then 'Friday'
            when 6 then 'Saturday'
        end as day_name,
        case when extract(dayofweek from date_day) in (0, 6) then true else false end as is_weekend
    from spine
)

select * from enriched
