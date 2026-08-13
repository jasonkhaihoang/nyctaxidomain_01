-- Small conformed dimension. Exists so that fleet attributes live somewhere
-- other than a CASE expression repeated across every mart.
select * from (values
    ('yellow', 'Yellow medallion', true,  true,  'Street hail anywhere in the city'),
    ('green',  'Green boro taxi',  false, false, 'Street hail outside the Manhattan core and airports')
) t(service_type_key, service_type_name, may_serve_airports,
    may_serve_manhattan_core, hail_rule)
