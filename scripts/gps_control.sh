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

mkdir -p "$CONFIG_DIR"

# Ensure default config exists
if [ ! -f "$CONFIG_FILE" ]; then
    cat << 'EOF' > "$CONFIG_FILE"
{
  "enabled": false,
  "latitude": 35.6895,
  "longitude": 139.6917,
  "altitude": 40.0,
  "accuracy": 5.0,
  "jitter": true,
  "interval": 1.0,
  "boot_persist": false
}
EOF
fi

is_daemon_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null | tr -d ' \r\n')
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

update_json_val() {
    key="$1"
    new_val="$2"
    if [ -f "$CONFIG_FILE" ]; then
        sed -i -E "s/\"$key\"[[:space:]]*:[[:space:]]*[^,}]+/\"$key\": $new_val/" "$CONFIG_FILE"
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

    update_json_val "latitude" "$LAT"
    update_json_val "longitude" "$LNG"
    update_json_val "altitude" "$ALT"
    update_json_val "accuracy" "$ACC"
    update_json_val "jitter" "$JIT"

    echo "{\"success\":true,\"latitude\":$LAT,\"longitude\":$LNG}"
}

cmd_save_config() {
    PAYLOAD="$1"
    if [ -n "$PAYLOAD" ]; then
        echo "$PAYLOAD" > "$CONFIG_FILE"
        chmod 0644 "$CONFIG_FILE"
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
    *)
        echo "Usage: gps_control.sh {status|start|stop|set <lat> <lng>|save-config <json>|get-config|net-shield [on|off|status|vpn]}"
        exit 1
        ;;
esac
