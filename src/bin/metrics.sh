#!/bin/bash

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus-operated.monitoring:9090}"
SOURCE_METRICS="${SOURCE_METRICS:-gitlab_total_commits}"
START_DATE="${START_DATE:-2024-10-10}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/metrics.log}"

# Convert START_DATE to Unix timestamp
START_TIMESTAMP=$(date -d "$START_DATE" +%s)

# Function to escape label values for Prometheus
escape_label_value() {
    local val="$1"
    val="${val//\\/\\\\}"  # Escape backslash
    val="${val//\"/\\\"}"  # Escape double quote
    val="${val//$'\n'/}"   # Remove newlines
    val="${val//$'\r'/}"   # Remove carriage returns
    echo -n "$val"
}

# Initialize metrics array
declare -a METRICS=()

# Function to add metrics to the array without duplication
metric_add() {
    local metric="$1"
    for existing_metric in "${METRICS[@]}"; do
        if [[ "$existing_metric" == "$metric" ]]; then
            echo "Duplicate metric found, not adding: $metric" >&2
            return
        fi
    done
    # echo "Adding metric: $metric" >&2
    METRICS+=("$metric")
}

# Function to collect metrics
collect_metrics() {
    IFS=',' read -ra METRIC_NAMES <<< "$SOURCE_METRICS"
    for METRIC_NAME in "${METRIC_NAMES[@]}"; do
        # Remove leading/trailing whitespace
        METRIC_NAME="$(echo -e "${METRIC_NAME}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # Timespans definitions
        declare -A TIMESCALES
        TIMESCALES=( ["days"]=30 ["weeks"]=4 ["months"]=12 ["years"]=2 )

        for TIMESCALE in "${!TIMESCALES[@]}"; do
            MAX_VALUE="${TIMESCALES[$TIMESCALE]}"
            for (( i=1; i<=MAX_VALUE; i++ )); do
                # Determine the unit
                case $TIMESCALE in
                    "days")
                        UNIT="d"
                        ;;
                    "weeks")
                        UNIT="$((i * 7))d"  # Weeks converted to days
                        ;;
                    "months")
                        UNIT="$((i * 30))d"  # Approximate month as 30 days
                        ;;
                    "years")
                        UNIT="$((i * 365))d"  # Approximate year as 365 days
                        ;;
                esac

                # Build the Prometheus query
                QUERY="sum_over_time(${METRIC_NAME}[${UNIT}])"

                # Ensure the time range does not exceed the START_DATE
                END_TIMESTAMP=$(date +%s)
                TIME_RANGE=$((END_TIMESTAMP - START_TIMESTAMP))
                UNIT_SECONDS=$(( $(date -d "${UNIT}" +%s) - $(date -d "0" +%s) ))
                if (( UNIT_SECONDS > TIME_RANGE )); then
                    # Skip if the time range exceeds data since START_DATE
                    continue
                fi

                # URL encode the query
                ENCODED_QUERY=$(echo -n "$QUERY" | jq -sRr @uri)

                # Build the full URL
                URL="${PROMETHEUS_URL}/api/v1/query?query=${ENCODED_QUERY}"

                # Fetch the data from Prometheus
                RESPONSE=$(curl -s "$URL")

                # Parse the value from the JSON response
                VALUE=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1]')

                # If VALUE is null, set to 0
                if [[ "$VALUE" == "null" ]]; then
                    VALUE=0
                fi

                # Generate the new metric line
                NEW_METRIC="${METRIC_NAME}_timespan_${TIMESCALE}{in_past=\"${i}\"} ${VALUE}"
                metric_add "$NEW_METRIC"
            done
        done
    done
}

# Main script execution
collect_metrics

# Write metrics to file
printf "%s\n" "${METRICS[@]}" > "$OUTPUT_FILE"
