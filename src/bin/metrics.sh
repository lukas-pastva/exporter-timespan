#!/bin/bash

# Configuration
CONFIG_FILE="${CONFIG_FILE:-config.yaml}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus-operated.monitoring:9090}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/metrics.log}"
STEP="${STEP:-5m}"

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
    METRICS+=("$metric")
}

# Function to collect metrics
collect_metrics() {
    local metrics_count
    metrics_count=$(yq e '.metrics | length' "$CONFIG_FILE")

    for (( idx=0; idx<metrics_count; idx++ )); do
        local metric_query
        local aggregation
        local time_window_start
        local time_window_end
        local metric_start_date

        metric_name=$(yq e ".metrics[$idx].name" "$CONFIG_FILE")
        metric_query=$(yq e ".metrics[$idx].query" "$CONFIG_FILE")
        aggregation=$(yq e ".metrics[$idx].aggregation" "$CONFIG_FILE")
        time_window_start=$(yq e ".metrics[$idx].time_window.start" "$CONFIG_FILE")
        time_window_end=$(yq e ".metrics[$idx].time_window.end" "$CONFIG_FILE")
        metric_start_date=$(yq e ".metrics[$idx].start_date" "$CONFIG_FILE")

        # Convert start date to timestamp
        START_DATE="${metric_start_date:-2024-10-10}"
        START_TIMESTAMP=$(date -d "$START_DATE" +%s)
        CURRENT_TIMESTAMP=$(date +%s)

        DAYS_TO_PROCESS=$(( (CURRENT_TIMESTAMP - START_TIMESTAMP) / 86400 ))
        if (( DAYS_TO_PROCESS < 0 )); then
            echo "Start date is in the future, skipping metric: $metric_query" >&2
            continue
        fi

        if (( DAYS_TO_PROCESS > 730 )); then
            DAYS_TO_PROCESS=730  # Limit to 2 years (730 days)
        fi

        declare -A daily_values=()

        # Collect daily values
        for (( day_offset=0; day_offset<=DAYS_TO_PROCESS; day_offset++ )); do
            TARGET_DATE=$(date -d "today - $day_offset day" +"%Y-%m-%d")

            # Calculate the start and end times for the time window on that day
            WINDOW_START="${TARGET_DATE}T${time_window_start}:00Z"
            WINDOW_END="${TARGET_DATE}T${time_window_end}:00Z"

            # Convert times to Unix timestamps
            WINDOW_START_TS=$(date -d "$WINDOW_START" +%s)
            WINDOW_END_TS=$(date -d "$WINDOW_END" +%s)

            # Skip if the window is before the start date
            if (( WINDOW_END_TS < START_TIMESTAMP )); then
                continue
            fi

            # Adjust WINDOW_START_TS if it is before the start date
            if (( WINDOW_START_TS < START_TIMESTAMP )); then
                WINDOW_START_TS=$START_TIMESTAMP
            fi

            # Build the Prometheus query
            QUERY="$metric_query"

            # URL encode query parameters
            ENCODED_QUERY=$(echo -n "$QUERY" | jq -sRr @uri)
            ENCODED_START=$(date -d "@$WINDOW_START_TS" -u +"%Y-%m-%dT%H:%M:%SZ")
            ENCODED_END=$(date -d "@$WINDOW_END_TS" -u +"%Y-%m-%dT%H:%M:%SZ")
            ENCODED_STEP=$(echo -n "$STEP" | jq -sRr @uri)

            # Build the full URL
            URL="${PROMETHEUS_URL}/api/v1/query_range?query=${ENCODED_QUERY}&start=${ENCODED_START}&end=${ENCODED_END}&step=${ENCODED_STEP}"

            # Fetch data from Prometheus
            RESPONSE=$(curl -s "$URL")

            # Check if the response contains data
            RESULT_COUNT=$(echo "$RESPONSE" | jq '.data.result | length')

            if (( RESULT_COUNT == 0 )); then
                VALUE=0
            else
                # Extract the values
                VALUES=$(echo "$RESPONSE" | jq -r '.data.result[0].values[][1]')

                if [[ "$aggregation" == "max" ]]; then
                    # Compute maximum value
                    VALUE=$(echo "$VALUES" | sort -nr | head -n1)
                elif [[ "$aggregation" == "avg" ]]; then
                    # Compute average value
                    SUM=0
                    COUNT=0
                    while read -r val; do
                        SUM=$(echo "$SUM + $val" | bc)
                        COUNT=$((COUNT + 1))
                    done <<< "$VALUES"
                    if (( COUNT > 0 )); then
                        VALUE=$(echo "scale=5; $SUM / $COUNT" | bc)
                    else
                        VALUE=0
                    fi
                else
                    echo "Unknown aggregation method: $aggregation"
                    continue
                fi
            fi

            daily_values["$day_offset"]="$VALUE"
        done

        # Handle Per Day Metrics
        for (( day_offset=0; day_offset<=DAYS_TO_PROCESS; day_offset++ )); do
            VALUE="${daily_values[$day_offset]:-0}"
            NEW_METRIC="${metric_name}_timespan_days{in_past=\"${day_offset}\"} ${VALUE}"
            metric_add "$NEW_METRIC"
        done

        # Define TIMESCALES
        declare -A TIMESCALES
        TIMESCALES=( ["weeks"]=52 ["months"]=12 ["years"]=2 )

        # For each timespan, sum the daily values
        for TIMESCALE in "${!TIMESCALES[@]}"; do
            MAX_VALUE="${TIMESCALES[$TIMESCALE]}"
            for (( i=1; i<=MAX_VALUE; i++ )); do
                case $TIMESCALE in
                    "weeks")
                        DAYS_TO_SUM=$((i * 7))
                        ;;
                    "months")
                        DAYS_TO_SUM=$((i * 30))
                        ;;
                    "years")
                        DAYS_TO_SUM=$((i * 365))
                        ;;
                esac

                # Skip if not enough data
                if (( DAYS_TO_SUM > DAYS_TO_PROCESS + 1 )); then
                    continue
                fi

                SUM=0
                for (( day_offset=0; day_offset<DAYS_TO_SUM; day_offset++ )); do
                    VALUE="${daily_values[$day_offset]:-0}"
                    SUM=$(echo "$SUM + $VALUE" | bc)
                done

                # Generate the new metric line
                NEW_METRIC="${metric_name}_timespan_${TIMESCALE}{in_past=\"${i}\"} ${SUM}"
                metric_add "$NEW_METRIC"
            done
        done
    done
}

# Main script execution
collect_metrics

# Write metrics to file
printf "%s\n" "${METRICS[@]}" > "$OUTPUT_FILE"
