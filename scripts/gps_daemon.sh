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
    for p in $PROVIDERS; do
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
appops set 2000 android:mock_location allow 2>/dev/null
appops set 1000 android:mock_location allow 2>/dev/null
appops set 0 android:mock_location allow 2>/dev/null
appops set com.android.shell android:mock_location allow 2>/dev/null
appops set android android:mock_location allow 2>/dev/null
appops set --user 0 2000 android:mock_location allow 2>/dev/null
appops set --user 0 1000 android:mock_location allow 2>/dev/null
appops set --user 0 com.android.shell android:mock_location allow 2>/dev/null
appops set --user 0 android android:mock_location allow 2>/dev/null

# Ensure system location is enabled
cmd location set-location-enabled true 2>/dev/null

# Suppress Wi-Fi and Bluetooth scanning to prevent Google Location Accuracy from overriding GPS
settings put global wifi_scan_always_enabled 0 2>/dev/null
settings put global ble_scan_always_enabled 0 2>/dev/null

echo "[$(date)] Registering test providers..." > "$LOG_FILE"

# Clean and register test providers with full capabilities (supports altitude, speed, bearing) without restrictive hardware requirements
for p in $PROVIDERS; do
    cmd location providers remove-test-provider "$p" 2>/dev/null
    if ! cmd location providers add-test-provider "$p" --supportsAltitude --supportsSpeed --supportsBearing >> "$LOG_FILE" 2>&1; then
        cmd location providers add-test-provider "$p" >> "$LOG_FILE" 2>&1
    fi
    cmd location providers set-test-provider-enabled "$p" true >> "$LOG_FILE" 2>&1
done

# Dynamically evict target apps configured by the user
evict_target_apps() {
    if [ -f "$CONFIG_FILE" ]; then
        APPS=$(awk '
            BEGIN { in_arr = 0 }
            /"target_apps"/ {
                sub(/.*"target_apps"[ \t]*:[ \t]*\[/, "")
                if (/\]/) { sub(/\].*/, ""); print; next }
                in_arr = 1; print; next
            }
            in_arr {
                if (/\]/) { sub(/\].*/, ""); print; in_arr = 0; next }
                print
            }
        ' "$CONFIG_FILE" 2>/dev/null | grep -oE '"[a-zA-Z0-9_\.]+"' | tr -d '"')
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

    # If coordinates have shifted from previous loop tick, evict target apps so they receive fresh location
    if [ -n "$PREV_BASE_LAT" ] && { [ "$PREV_BASE_LAT" != "$BASE_LAT" ] || [ "$PREV_BASE_LNG" != "$BASE_LNG" ]; }; then
        echo "[$(date)] Coordinates changed to ${BASE_LAT},${BASE_LNG} — evicting target apps" >> "$LOG_FILE"
        evict_target_apps
    fi
    PREV_BASE_LAT="$BASE_LAT"
    PREV_BASE_LNG="$BASE_LNG"

    TARGET_LAT="$BASE_LAT"
    TARGET_LNG="$BASE_LNG"
    TARGET_ACC="$ACCURACY"

    # Micro-jitter: simulate authentic GNSS atmospheric drift (±1.5 meters)
    # Using separate awk call with explicit LC_ALL=C — avoids comma decimal crash on global locales
    if [ "$JITTER" = "true" ]; then
        r1=$(( (${RANDOM:-0} % 31) - 15 ))
        r2=$(( (${RANDOM:-0} % 31) - 15 ))
        JITTER_OUT=$(LC_ALL=C awk -v r1="$r1" -v r2="$r2" \
            -v lat="$BASE_LAT" -v lng="$BASE_LNG" -v acc="$ACCURACY" \
            'BEGIN {
                d_lat = r1 * 0.0000012;
                d_lng = r2 * 0.0000012;
                res_lat = lat + d_lat;
                res_lng = lng + d_lng;
                res_acc = acc + ((r1 % 3) * 0.3);
                if (res_acc < 2.0) res_acc = 2.0;
                printf "%.7f %.7f %.1f", res_lat, res_lng, res_acc;
            }')
        # Parse awk output into individual vars — safe in mksh
        TARGET_LAT=$(echo "$JITTER_OUT" | cut -d' ' -f1)
        TARGET_LNG=$(echo "$JITTER_OUT" | cut -d' ' -f2)
        TARGET_ACC=$(echo "$JITTER_OUT" | cut -d' ' -f3)
        # Sanity-check: if jitter produced empty values fall back to base
        [ -z "$TARGET_LAT" ] && TARGET_LAT="$BASE_LAT"
        [ -z "$TARGET_LNG" ] && TARGET_LNG="$BASE_LNG"
        [ -z "$TARGET_ACC" ] && TARGET_ACC="$ACCURACY"
    fi

    TICK_COUNT=$((TICK_COUNT + 1))
    if [ $((TICK_COUNT % 10)) -eq 1 ]; then
        echo "[$(date)] Injected coords: ${TARGET_LAT},${TARGET_LNG} (acc: ${TARGET_ACC}m)" >> "$LOG_FILE"
    fi

    # Log rotation: prevent unbounded growth on /data partition (cap at 200KB)
    if [ $((TICK_COUNT % 120)) -eq 0 ] && [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$LOG_SIZE" -gt 204800 ]; then
            tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi

    # Re-register providers every 60 ticks in case GMS or LocationManager evicted them
    if [ $((TICK_COUNT % 60)) -eq 0 ]; then
        for p in $PROVIDERS; do
            cmd location providers add-test-provider "$p" 2>/dev/null
            cmd location providers set-test-provider-enabled "$p" true 2>/dev/null
        done
        echo "[$(date)] Provider keepalive tick (re-registered test providers)" >> "$LOG_FILE"
    fi

    # Inject into providers
    for p in $PROVIDERS; do
        cmd location providers set-test-provider-location "$p" --location "${TARGET_LAT},${TARGET_LNG}" --accuracy "${TARGET_ACC}" >> "$LOG_FILE" 2>&1
    done

    # Write live status atomically with safe defaults (never emits malformed JSON)
    cat << EOF > "$STATUS_FILE.tmp"
{
  "active": true,
  "pid": $$,
  "latitude": ${TARGET_LAT:-35.6895},
  "longitude": ${TARGET_LNG:-139.6917},
  "accuracy": ${TARGET_ACC:-5.0},
  "altitude": ${ALTITUDE:-40.0},
  "jitter": ${JITTER:-true},
  "last_tick": $(date +%s)
}
EOF
    mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"

    sleep "$INTERVAL"
done

cleanup
