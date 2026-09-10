#!/system/bin/sh
##########################################################################################
# KernelSU Mock GPS Daemon
# Injects mock location via root provider without Developer Options mock toggle.
##########################################################################################

CONFIG_DIR="/data/adb/ksu_fakegps"
CONFIG_FILE="$CONFIG_DIR/config.json"
PID_FILE="$CONFIG_DIR/daemon.pid"
STATUS_FILE="$CONFIG_DIR/status.json"

mkdir -p "$CONFIG_DIR"
echo "$$" > "$PID_FILE"

PROVIDERS="gps network fused"
LOG_FILE="$CONFIG_DIR/daemon.log"

# Cleanup function when daemon stops
cleanup() {
    echo "[$(date)] Stopping daemon and removing mock providers..." >> "$LOG_FILE"
    for p in $PROVIDERS; do
        cmd location providers set-test-provider-enabled "$p" false 2>> "$LOG_FILE"
        cmd location providers remove-test-provider "$p" 2>> "$LOG_FILE"
    done
    rm -f "$PID_FILE"
    echo '{"active":false,"pid":0,"last_tick":0}' > "$STATUS_FILE"
    exit 0
}

# Ignore SIGHUP so parent shell disconnect doesn't kill daemon
trap '' SIGHUP
# Clean exit on SIGTERM and SIGINT
trap cleanup SIGTERM SIGINT

# Pre-grant mock location capability to system shell across users
appops set 2000 android:mock_location allow 2>/dev/null
appops set 0 android:mock_location allow 2>/dev/null
appops set com.android.shell android:mock_location allow 2>/dev/null
appops set --user 0 2000 android:mock_location allow 2>/dev/null
appops set --user 0 com.android.shell android:mock_location allow 2>/dev/null

# Ensure system location is enabled
cmd location set-location-enabled true 2>/dev/null

# Suppress Wi-Fi and Bluetooth scanning to prevent Google Location Accuracy from overriding GPS
settings put global wifi_scan_always_enabled 0 2>/dev/null
settings put global ble_scan_always_enabled 0 2>/dev/null
content insert --uri content://com.google.settings/partner --bind name:s:network_location_opt_in --bind value:s:0 2>/dev/null

echo "[$(date)] Registering test providers..." > "$LOG_FILE"

# Clean and register test providers with full capabilities
for p in $PROVIDERS; do
    cmd location providers remove-test-provider "$p" 2>/dev/null
    cmd location providers add-test-provider "$p" --requiresNetwork --requiresSatellite --supportsAltitude --supportsSpeed --supportsBearing 2>> "$LOG_FILE"
    # Fallback to basic if flags rejected
    if [ $? -ne 0 ]; then
        cmd location providers add-test-provider "$p" 2>> "$LOG_FILE"
    fi
    cmd location providers set-test-provider-enabled "$p" true 2>> "$LOG_FILE"
done

# Kill Google Maps so it clears in-memory cached location
am force-stop com.google.android.apps.maps 2>/dev/null

# Helper function to extract json values
get_json_val() {
    key="$1"
    default_val="$2"
    val=$(grep -E "\"$key\"[[:space:]]*:" "$CONFIG_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*:[[:space:]]*"?([^",]+)"?.*/\1/' | tr -d ' \r\n')
    if [ -z "$val" ]; then
        echo "$default_val"
    else
        echo "$val"
    fi
}

echo "[$(date)] KernelSU Mock GPS Daemon started with PID $$"

# Main broadcast loop
while true; do
    if [ ! -f "$CONFIG_FILE" ]; then
        sleep 2
        continue
    fi

    IS_ENABLED=$(get_json_val "enabled" "false")
    if [ "$IS_ENABLED" != "true" ]; then
        echo "[$(date)] Mock GPS disabled in config. Exiting daemon."
        break
    fi

    BASE_LAT=$(get_json_val "latitude" "35.6895")
    BASE_LNG=$(get_json_val "longitude" "139.6917")
    ALTITUDE=$(get_json_val "altitude" "40.0")
    ACCURACY=$(get_json_val "accuracy" "5.0")
    JITTER=$(get_json_val "jitter" "true")
    INTERVAL=$(get_json_val "interval" "1.0")

    TARGET_LAT="$BASE_LAT"
    TARGET_LNG="$BASE_LNG"
    TARGET_ACC="$ACCURACY"

    # Micro-jitter calculation to simulate authentic satellite atmospheric drift (±1.5 meters)
    if [ "$JITTER" = "true" ]; then
        r1=$(( (RANDOM % 31) - 15 ))
        r2=$(( (RANDOM % 31) - 15 ))
        
        # Calculate tiny coordinate offsets using awk
        read -r TARGET_LAT TARGET_LNG TARGET_ACC << EOF
$(awk -v r1="$r1" -v r2="$r2" -v lat="$BASE_LAT" -v lng="$BASE_LNG" -v acc="$ACCURACY" 'BEGIN {
    d_lat = r1 * 0.0000012;
    d_lng = r2 * 0.0000012;
    res_lat = lat + d_lat;
    res_lng = lng + d_lng;
    res_acc = acc + ((r1 % 3) * 0.3);
    if (res_acc < 2.0) res_acc = 2.0;
    printf "%.7f %.7f %.1f", res_lat, res_lng, res_acc;
}')
EOF
    fi

    TICK_COUNT=$((TICK_COUNT + 1))
    if [ $((TICK_COUNT % 10)) -eq 1 ]; then
        echo "[$(date)] Injected coords: ${TARGET_LAT},${TARGET_LNG} (acc: ${TARGET_ACC}m)" >> "$LOG_FILE"
    fi

    # Inject into providers
    for p in $PROVIDERS; do
        cmd location providers set-test-provider-location "$p" --location "${TARGET_LAT},${TARGET_LNG}" --accuracy "${TARGET_ACC}" 2>> "$LOG_FILE"
    done

    # Write live status
    cat << EOF > "$STATUS_FILE.tmp"
{
  "active": true,
  "pid": $$,
  "latitude": $TARGET_LAT,
  "longitude": $TARGET_LNG,
  "accuracy": $TARGET_ACC,
  "altitude": $ALTITUDE,
  "jitter": $JITTER,
  "last_tick": $(date +%s)
}
EOF
    mv "$STATUS_FILE.tmp" "$STATUS_FILE"

    sleep "$INTERVAL"
done

cleanup
