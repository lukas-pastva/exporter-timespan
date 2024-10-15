write a prometheus exporter script, that i will use for having metrics pushed to prometheus towards http://prometheus-operated.monitoring:9090
and the exporter will actually create from defined metric another metric. and the metric name will be same as source metric but named as _timespan and then the metric will have a new attribute with values as to show in last days, weeks, months years.
example: metric name gitlab_total_commits is returning user commits in last 24 hours. as it runs each 24 hours. and i want you to create metrics
gitlab_total_commits_timespan_days{in_past="1"}
..
..
gitlab_total_commits_timespan_days{in_past="30"}

gitlab_total_commitss_timespan_weeks{in_past="1"}
..
..
gitlab_total_commits_timespan_weeks{in_past="4"}

gitlab_total_commits_timespan_months{in_past="1"}
..
..
gitlab_total_commits_timespan_months{in_past="12"}

gitlab_total_commits_timespan_years{in_past="1"}
..
..
gitlab_total_commits_timespan_years{in_past="2"}


when asking how the values will be calculated, the metrics are always exporter once each 24 hours only . so the values are "per day" always. so the metric should be run towards prometheus eg tigger prometheus api and get values and paste the query to ger probably resutls "per day in last 2 years". However the start date should be configurable via env variable, as of now only since 2024-10-10
and then once the exporter has all the data it should generate the metrics.
And the metrics ill be as sum, obviously, for exmpale for metric gitlab_total_commits it will return one number per day, but in new metric gitlab_total_commits_timespan_months{in_past="1"} will sum all metircs per day in one number.

do not forget that the soruce metri name shouldd beconfigurable via env where the metrics can be more of them separated by comma
