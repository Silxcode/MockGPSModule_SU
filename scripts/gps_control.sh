#!/system/bin/sh
##########################################################################################
# KernelSU Mock GPS Controller
# CLI Management tool for the WebUI and terminal
##########################################################################################

SCRIPT_DIR=${0%/*}
CONFIG_DIR="/data/adb/ksu_fakegps"
CONFIG_FILE="$CONFIG_DIR/config.json"
PID_FILE="$CONFIG_DIR/daemon.pid"
STATUS_FILE="$CONFIG_DIR/status.json"

mkdir -p "$CONFIG_DIR" 2>/dev/null

# Ensure default config exists if directory is writable
if [ -d "$CONFIG_DIR" ] && [ ! -f "$CONFIG_FILE" ]; then
    cat << 'EOF' > "$CONFIG_FILE" 2>/dev/null
{
  "enabled": false,
  "latitude": 35.6895,
  "longitude": 139.6917,
  "altitude": 40.0,
  "accuracy": 5.0,
  "jitter": true,
  "interval": 1.0,
  "boot_persist": false,
  "target_apps": [
    "com.google.android.apps.maps"
  ]
}
EOF
fi

get_target_apps() {
    if [ -f "$CONFIG_FILE" ]; then
        awk '
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
        ' "$CONFIG_FILE" 2>/dev/null | grep -oE '"[a-zA-Z0-9_\.]+"' | tr -d '"'
    fi
}

evict_target_apps() {
    APPS=$(get_target_apps)
    for app in $APPS; do
        if [ -n "$app" ]; then
            am force-stop "$app" 2>/dev/null
        fi
    done
}

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

write_full_config() {
    EN="${1:-false}"
    LAT="${2:-35.6895}"
    LNG="${3:-139.6917}"
    ALT="${4:-40.0}"
    ACC="${5:-5.0}"
    JIT="${6:-true}"
    PER="${7:-false}"

    APPS_STR=""
    for app in $(get_target_apps); do
        if [ -z "$APPS_STR" ]; then
            APPS_STR="    \"$app\""
        else
            APPS_STR="${APPS_STR},\n    \"$app\""
        fi
    done

    cat << EOF > "$CONFIG_FILE.tmp"
{
  "enabled": $EN,
  "latitude": $LAT,
  "longitude": $LNG,
  "altitude": $ALT,
  "accuracy": $ACC,
  "jitter": $JIT,
  "interval": 1.0,
  "boot_persist": $PER,
  "target_apps": [
$(printf "$APPS_STR")
  ]
}
EOF
    chmod 0644 "$CONFIG_FILE.tmp"
    mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

write_full_config_with_apps() {
    EN=$(get_json_val "enabled" "false")
    LAT=$(get_json_val "latitude" "35.6895")
    LNG=$(get_json_val "longitude" "139.6917")
    ALT=$(get_json_val "altitude" "40.0")
    ACC=$(get_json_val "accuracy" "5.0")
    JIT=$(get_json_val "jitter" "true")
    PER=$(get_json_val "boot_persist" "false")

    APPS_STR=""
    for app in "$@"; do
        [ -z "$app" ] && continue
        if [ -z "$APPS_STR" ]; then
            APPS_STR="    \"$app\""
        else
            APPS_STR="${APPS_STR},\n    \"$app\""
        fi
    done

    cat << EOF > "$CONFIG_FILE.tmp"
{
  "enabled": $EN,
  "latitude": $LAT,
  "longitude": $LNG,
  "altitude": $ALT,
  "accuracy": $ACC,
  "jitter": $JIT,
  "interval": 1.0,
  "boot_persist": $PER,
  "target_apps": [
$(printf "$APPS_STR")
  ]
}
EOF
    chmod 0644 "$CONFIG_FILE.tmp"
    mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

is_daemon_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null | tr -d ' \r\n')
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            # Verify process cmdline actually belongs to gps_daemon to avoid PID recycling collision
            if grep -qa "gps_daemon" "/proc/$PID/cmdline" 2>/dev/null; then
                return 0
            fi
            # Stale PID file matching an unrelated process — prune it
            rm -f "$PID_FILE"
        fi
    fi
    return 1
}

update_json_val() {
    key="$1"
    new_val="$2"
    if [ -f "$CONFIG_FILE" ]; then
        sed -E "s/\"$key\"[[:space:]]*:[[:space:]]*[^,}]+/\"$key\": $new_val/" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null && mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
}

cmd_status() {
    RUNNING="false"
    PID=0
    if is_daemon_running; then
        RUNNING="true"
        PID=$(cat "$PID_FILE" 2>/dev/null | tr -d ' \r\n')
    fi

    # Read Android settings to verify Developer Options status
    DEV_OPTIONS=$(settings get global development_settings_enabled 2>/dev/null | tr -d ' \r\n')
    [ -z "$DEV_OPTIONS" ] && DEV_OPTIONS="0"

    MOCK_APP=$(settings get secure mock_location 2>/dev/null | tr -d ' \r\n')
    [ -z "$MOCK_APP" ] && MOCK_APP="none"

    CONFIG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null)
    [ -z "$CONFIG_CONTENT" ] && CONFIG_CONTENT="{}"

    LIVE_STATUS="{}"
    [ -f "$STATUS_FILE" ] && LIVE_STATUS=$(cat "$STATUS_FILE" 2>/dev/null)

    # Gather network shield and VPN info
    NET_JSON="{}"
    if [ -x "$SCRIPT_DIR/net_shield.sh" ]; then
        NET_JSON=$("$SCRIPT_DIR/net_shield.sh" status 2>/dev/null)
        [ -z "$NET_JSON" ] && NET_JSON="{}"
    fi

    cat << EOF
{
  "active": $RUNNING,
  "pid": $PID,
  "dev_options_enabled": "$DEV_OPTIONS",
  "mock_location_app": "$MOCK_APP",
  "config": $CONFIG_CONTENT,
  "status": $LIVE_STATUS,
  "net": $NET_JSON
}
EOF
}

cmd_start() {
    update_json_val "enabled" "true"

    if is_daemon_running; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        echo "{\"success\":true,\"message\":\"Daemon already running (PID: $PID)\",\"pid\":$PID}"
        return 0
    fi

    # Ensure executable permission
    chmod 0755 "$SCRIPT_DIR/gps_daemon.sh"

    # Launch daemon in background detached with explicit decoupling
    ( trap '' HUP; "$SCRIPT_DIR/gps_daemon.sh" </dev/null >/dev/null 2>&1 ) &
    DAEMON_PID=$!

    sleep 0.5
    echo "{\"success\":true,\"message\":\"Mock GPS daemon started\",\"pid\":$DAEMON_PID}"
}

cmd_stop() {
    update_json_val "enabled" "false"

    if is_daemon_running; then
        PID=$(cat "$PID_FILE" 2>/dev/null | tr -d ' \r\n')
        # Only kill if the process is verified as gps_daemon
        if grep -qa "gps_daemon" "/proc/$PID/cmdline" 2>/dev/null; then
            kill -TERM "$PID" 2>/dev/null
            # Wait up to 2 seconds for clean cleanup
            for i in 1 2 3 4; do
                if ! kill -0 "$PID" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            # Force kill if still lingering
            kill -9 "$PID" 2>/dev/null
        fi
    fi

    # Ensure test providers are fully removed
    for p in gps network fused; do
        cmd location providers set-test-provider-enabled "$p" false 2>/dev/null
        cmd location providers remove-test-provider "$p" 2>/dev/null
    done

    # Restore default scanning settings
    settings put global wifi_scan_always_enabled 1 2>/dev/null
    settings put global ble_scan_always_enabled 1 2>/dev/null

    rm -f "$PID_FILE"
    echo '{"active":false,"pid":0,"last_tick":0}' > "$STATUS_FILE"

    echo "{\"success\":true,\"message\":\"Mock GPS stopped and real GPS restored\"}"
}

cmd_set() {
    LAT="$1"
    LNG="$2"
    ALT="${3:-40.0}"
    ACC="${4:-5.0}"
    JIT="${5:-true}"

    if [ -z "$LAT" ] || [ -z "$LNG" ]; then
        echo "{\"error\":\"Missing coordinates. Usage: gps_control.sh set <lat> <lng> [alt] [acc] [jitter]\"}"
        return 1
    fi

    CUR_ENABLED=$(get_json_val "enabled" "false")
    CUR_PERSIST=$(get_json_val "boot_persist" "false")

    write_full_config "$CUR_ENABLED" "$LAT" "$LNG" "$ALT" "$ACC" "$JIT" "$CUR_PERSIST"

    # If daemon is running, immediately update mock location in all providers for zero latency
    if is_daemon_running; then
        for p in gps network; do
            cmd location providers set-test-provider-location "$p" --location "${LAT},${LNG}" --accuracy "${ACC}" 2>/dev/null
        done
        # Evict target apps so they fetch fresh location
        evict_target_apps
    fi

    echo "{\"success\":true,\"latitude\":$LAT,\"longitude\":$LNG}"
}

cmd_add_app() {
    NEW_APP="$1"
    if [ -z "$NEW_APP" ]; then
        echo "{\"error\":\"Missing package name\"}"
        return 1
    fi
    NEW_APP=$(echo "$NEW_APP" | grep -oE '^[a-zA-Z0-9_\.]+$')
    if [ -z "$NEW_APP" ]; then
        echo "{\"error\":\"Invalid package name format\"}"
        return 1
    fi
    CURRENT_APPS=$(get_target_apps)
    for a in $CURRENT_APPS; do
        if [ "$a" = "$NEW_APP" ]; then
            echo "{\"success\":true,\"message\":\"App already in target list\",\"app\":\"$NEW_APP\"}"
            return 0
        fi
    done
    write_full_config_with_apps $CURRENT_APPS "$NEW_APP"
    echo "{\"success\":true,\"message\":\"App added to target list\",\"app\":\"$NEW_APP\"}"
}

cmd_remove_app() {
    REM_APP="$1"
    if [ -z "$REM_APP" ]; then
        echo "{\"error\":\"Missing package name\"}"
        return 1
    fi
    CURRENT_APPS=$(get_target_apps)
    NEW_LIST=""
    for a in $CURRENT_APPS; do
        if [ "$a" != "$REM_APP" ]; then
            NEW_LIST="$NEW_LIST $a"
        fi
    done
    write_full_config_with_apps $NEW_LIST
    echo "{\"success\":true,\"message\":\"App removed from target list\",\"app\":\"$REM_APP\"}"
}

cmd_evict_apps() {
    evict_target_apps
    echo "{\"success\":true,\"message\":\"Target apps evicted and caches cleared\"}"
}

cmd_persist() {
    VAL="${1:-false}"
    update_json_val "boot_persist" "$VAL"
    echo "{\"success\":true,\"boot_persist\":$VAL}"
}

cmd_save_config() {
    PAYLOAD="$*"
    if [ -n "$PAYLOAD" ]; then
        echo "$PAYLOAD" > "$CONFIG_FILE.tmp"
        chmod 0644 "$CONFIG_FILE.tmp"
        mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "{\"success\":true,\"message\":\"Config updated\"}"
    else
        echo "{\"error\":\"No config payload provided\"}"
        return 1
    fi
}

cmd_get_config() {
    cat "$CONFIG_FILE" 2>/dev/null || echo "{}"
}

case "$1" in
    status)
        cmd_status
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    set)
        shift
        cmd_set "$@"
        ;;
    persist)
        shift
        cmd_persist "$@"
        ;;
    add-app)
        shift
        cmd_add_app "$@"
        ;;
    remove-app)
        shift
        cmd_remove_app "$@"
        ;;
    evict-apps)
        cmd_evict_apps
        ;;
    save-config)
        shift
        cmd_save_config "$@"
        ;;
    get-config)
        cmd_get_config
        ;;
    net-shield)
        shift
        if [ -x "$SCRIPT_DIR/net_shield.sh" ]; then
            "$SCRIPT_DIR/net_shield.sh" "${1:-status}"
        else
            echo "{\"error\":\"net_shield.sh not found\"}"
        fi
        ;;
    log)
        if [ -f "$CONFIG_DIR/daemon.log" ]; then
            tail -n 40 "$CONFIG_DIR/daemon.log"
        else
            echo "No daemon log found at $CONFIG_DIR/daemon.log"
        fi
        ;;
    *)
        echo "Usage: gps_control.sh {status|start|stop|set <lat> <lng>|add-app <pkg>|remove-app <pkg>|evict-apps|save-config <json>|get-config|net-shield [on|off|status|vpn]|log}"
        exit 1
        ;;
esac
