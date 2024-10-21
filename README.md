# Exporter-timespan

```yaml
# config.yaml
metrics:
  - name: gitlab_total_users
    query: max_over_time(gitlab_total_users{container="exporter-gitlab-users-day"}[5m])
    aggregation: max
    time_window:
      start: "03:00"
      end: "03:00"
    start_date: "2024-10-18"
  - name: gitlab_total_repositories
    query: max_over_time(gitlab_total_repositories{container="exporter-gitlab-users-day"}[5m])
    aggregation: max
    time_window:
      start: "03:00"
      end: "03:00"
    start_date: "2024-10-18"
  - name: gitlab_total_commits
    query: max_over_time(gitlab_total_commits{container="exporter-gitlab-users-day"}[5m])
    aggregation: max
    time_window:
      start: "03:00"
      end: "03:00"
    start_date: "2024-10-18"
```