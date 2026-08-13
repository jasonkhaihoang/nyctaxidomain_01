{% docs trip_key %}
md5 over the trip's natural columns: service type, vendor, pickup and dropoff
timestamps, pickup and dropoff zone, distance, total. Published by `silver.trips`.

Bronze does not carry it. Any model reaching back to a fleet-specific bronze
column has to recompute this expression identically -- same column order, same
separator -- which is why it lives in the `trip_natural_key` macro rather than
being written out per model.
{% enddocs %}

{% docs measurable_tip_rate %}
Tip as a share of fare, **restricted to payment methods where the meter records
tips**. Cash trips are excluded rather than counted as zero.

This distinction is not cosmetic. Cash is roughly a fifth of airport traffic and
records a tip on 0.04% of trips, so a blended tip rate falls in proportion to how
much cash a zone takes. That reads as a behavioural finding about the zone and is
an artefact of the instrument.
{% enddocs %}

{% docs fare_residual %}
Trip total minus every component this warehouse models: fare, tip, tolls, extra,
MTA tax, improvement surcharge and congestion surcharge.

A non-zero residual means either a surcharge TLC introduced that is not yet
modelled, or a total that was not derived from its parts. It is published as its
own column, and as its own row in the revenue bridge, rather than being absorbed
into a real component.
{% enddocs %}

{% docs scd2_asof %}
This dimension is Type 2 with a natural key and half-open validity intervals
`[valid_from_date, valid_to_date)`.

Joining on the natural key alone multiplies every fact row whose entity has more
than one version. The join must carry the fact's own date and use `>=` and
`<` -- `BETWEEN` is inclusive at both ends and double-counts on a changeover
date.
{% enddocs %}

{% docs occupancy_rate %}
On-trip seconds divided by online seconds.

The denominator is sign-on time, not wall-clock time. A driver who works four
hours and carries fares for three is at 75%, not 12.5%. Where a rate is rolled
up across shifts it is recomputed from summed numerators and denominators, never
averaged from the shift-level rates.
{% enddocs %}

{% docs fleet_attribution %}
Harbour Point runs roughly 420 of the city's ~13,000 medallions, so driver,
vehicle and shift are null on most trip rows.

This is a property of the business, not missing data. `is_fleet_attributed`
states it explicitly so that no consumer has to infer it from a null, and so
that a fleet-level denominator is never taken over the whole fact.
{% enddocs %}
