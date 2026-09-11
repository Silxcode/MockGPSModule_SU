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

SCRIPT_DIR=${0%/*}

# Cleanup function when daemon stops
cleanup() {
    echo "[$(date)] Stopping daemon and removing mock providers..." >> "$LOG_FILE"
    for p in gps network fused; do
        cmd location providers set-test-provider-enabled "$p" false 2>> "$LOG_FILE"
        cmd location providers remove-test-provider "$p" 2>> "$LOG_FILE"
    done
    # Disable network shield and restore network settings
    if [ -x "$SCRIPT_DIR/net_shield.sh" ]; then
        "$SCRIPT_DIR/net_shield.sh" off >> "$LOG_FILE" 2>&1
    fi
    rm -f "$PID_FILE"
    echo '{"active":false,"pid":0,"last_tick":0}' > "$STATUS_FILE"
    exit 0
}

# Ignore SIGHUP so parent shell disconnect doesn't kill daemon
trap '' SIGHUP
# Clean exit on SIGTERM and SIGINT
trap cleanup SIGTERM SIGINT

# Pre-grant mock location capability to system shell, root, and system server across users
for u in 0 1000 2000; do
    appops set --user 0 $u android:mock_location allow 2>/dev/null
    appops set $u android:mock_location allow 2>/dev/null
done
appops set --user 0 com.android.shell android:mock_location allow 2>/dev/null
appops set com.android.shell android:mock_location allow 2>/dev/null
appops set --user 0 android android:mock_location allow 2>/dev/null
appops set android android:mock_location allow 2>/dev/null

# Ensure system location is enabled
cmd location set-location-enabled true 2>/dev/null

# Suppress Wi-Fi and Bluetooth scanning
settings put global wifi_scan_always_enabled 0 2>/dev/null
settings put global ble_scan_always_enabled 0 2>/dev/null
settings put secure location_mode 1 2>/dev/null

echo "[$(date)] Registering test providers..." > "$LOG_FILE"

# Helper function to extract json values safely
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

BASE_LAT=$(get_json_val "latitude" "35.6895")
BASE_LNG=$(get_json_val "longitude" "139.6917")
ACCURACY=$(get_json_val "accuracy" "5.0")

# Clean and register test providers with full capabilities
for p in $PROVIDERS; do
    cmd location providers remove-test-provider "$p" 2>/dev/null
    if ! cmd location providers add-test-provider "$p" --supportsAltitude --supportsSpeed --supportsBearing >> "$LOG_FILE" 2>&1; then
        cmd location providers add-test-provider "$p" >> "$LOG_FILE" 2>&1
    fi
    cmd location providers set-test-provider-enabled "$p" true >> "$LOG_FILE" 2>&1
    cmd location providers set-test-provider-location "$p" --location "${BASE_LAT},${BASE_LNG}" --accuracy "${ACCURACY}" >> "$LOG_FILE" 2>&1
done

# Dynamically evict target apps configured by the user (pure sed/grep, no awk dependency)
evict_target_apps() {
    if [ -f "$CONFIG_FILE" ]; then
        APPS=$(sed -n '/"target_apps"/,/]/p' "$CONFIG_FILE" 2>/dev/null | grep -oE '"[a-zA-Z0-9_\.]+"' | tr -d '"' | grep -v 'target_apps')
        for app in $APPS; do
            if [ -n "$app" ]; then
                am force-stop "$app" 2>/dev/null
                echo "[$(date)] Evicted target app: $app" >> "$LOG_FILE"
            fi
        done
    fi
}

# Initial eviction of target apps so they fetch spoofed coordinates on start
evict_target_apps

echo "[$(date)] KernelSU Mock GPS Daemon started with PID $$" >> "$LOG_FILE"

TICK_COUNT=0

# Main broadcast loop
while true; do
    if [ ! -f "$CONFIG_FILE" ]; then
        sleep 1
        continue
    fi

    # Safe read of enabled flag: default to true to avoid dying on mid-write race condition
    IS_ENABLED=$(get_json_val "enabled" "true")
    if [ "$IS_ENABLED" = "false" ]; then
        sleep 1
        if [ "$(get_json_val "enabled" "true")" = "false" ]; then
            echo "[$(date)] Mock GPS disabled in config. Exiting daemon." >> "$LOG_FILE"
            break
        fi
    fi

    NEW_LAT=$(get_json_val "latitude" "")
    NEW_LNG=$(get_json_val "longitude" "")
    [ -n "$NEW_LAT" ] && BASE_LAT="$NEW_LAT"
    [ -n "$NEW_LNG" ] && BASE_LNG="$NEW_LNG"
    ACCURACY=$(get_json_val "accuracy" "5.0")

    # If coordinates have shifted from previous loop tick, evict target apps
    if [ -n "$PREV_BASE_LAT" ] && { [ "$PREV_BASE_LAT" != "$BASE_LAT" ] || [ "$PREV_BASE_LNG" != "$BASE_LNG" ]; }; then
        echo "[$(date)] Coordinates changed to ${BASE_LAT},${BASE_LNG} — evicting target apps" >> "$LOG_FILE"
        evict_target_apps
    fi
    PREV_BASE_LAT="$BASE_LAT"
    PREV_BASE_LNG="$BASE_LNG"

    TARGET_LAT="$BASE_LAT"
    TARGET_LNG="$BASE_LNG"
    TARGET_ACC="$ACCURACY"

    TICK_COUNT=$((TICK_COUNT + 1))
    if [ $((TICK_COUNT % 10)) -eq 1 ]; then
        echo "[$(date)] Injected coords: ${TARGET_LAT},${TARGET_LNG} (acc: ${TARGET_ACC}m)" >> "$LOG_FILE"
    fi

    # Log rotation: cap at 200KB
    if [ $((TICK_COUNT % 120)) -eq 0 ] && [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$LOG_SIZE" -gt 204800 ]; then
            tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi

    # Ensure providers stay enabled every 15 ticks
    if [ $((TICK_COUNT % 15)) -eq 0 ]; then
        for p in $PROVIDERS; do
            cmd location providers set-test-provider-enabled "$p" true 2>/dev/null
        done
    fi

    # Inject into providers continuously every second
    for p in $PROVIDERS; do
        cmd location providers set-test-provider-location "$p" --location "${TARGET_LAT},${TARGET_LNG}" --accuracy "${TARGET_ACC}" 2>/dev/null
    done

    # Write live status atomically
    cat << EOF > "$STATUS_FILE.tmp"
{
  "active": true,
  "pid": $$,
  "latitude": ${TARGET_LAT:-35.6895},
  "longitude": ${TARGET_LNG:-139.6917},
  "accuracy": ${TARGET_ACC:-5.0},
  "last_tick": $(date +%s)
}
EOF
    mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"

    sleep 1
done

cleanup
