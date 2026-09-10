#!/system/bin/sh
##########################################################################################
# KSU GPS Ghost — Network Shield
# Blocks Google Location Services network calls and reports VPN / IP state.
# Author: Silxcode
##########################################################################################

ACTION="${1:-status}"
CONFIG_DIR="/data/adb/ksu_fakegps"
LOG_FILE="$CONFIG_DIR/net_shield.log"

log() { echo "[$(date)] $*" >> "$LOG_FILE"; }

# ─────────────────────────────────────────────
# Resolve GMS UID from packages list
# ─────────────────────────────────────────────
get_gms_uid() {
    grep '^com.google.android.gms ' /data/system/packages.list 2>/dev/null | awk '{print $2}' | head -n1
}

# ─────────────────────────────────────────────
# Check active VPN / tunnel interface
# ─────────────────────────────────────────────
get_vpn_status() {
    VPN_IFACE=""
    VPN_IP=""
    IS_VPN="false"

    for iface in tun0 tun1 wg0 wg1 ppp0 clat0 utun0; do
        if ip link show "$iface" 2>/dev/null | grep -qE 'UP|UNKNOWN'; then
            VPN_IFACE="$iface"
            VPN_IP=$(ip addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -n1)
            IS_VPN="true"
            break
        fi
    done

    printf '{"vpn_active":%s,"iface":"%s","tunnel_ip":"%s"}' \
        "$IS_VPN" "${VPN_IFACE:-none}" "${VPN_IP:-none}"
}

# ─────────────────────────────────────────────
# IP geolocation via root shell (avoids WebView CORS issues)
# Uses wget or curl — at least one is available on most ROMs
# ─────────────────────────────────────────────
cmd_ip_check() {
    URL="https://ip-api.com/json/?fields=status,country,countryCode,city,query"
    RESULT=""

    # Try wget first (usually available in busybox/toybox)
    if command -v wget >/dev/null 2>&1; then
        RESULT=$(wget -qO- --timeout=6 "$URL" 2>/dev/null)
    fi

    # Fall back to curl
    if [ -z "$RESULT" ] && command -v curl >/dev/null 2>&1; then
        RESULT=$(curl -sf --max-time 6 "$URL" 2>/dev/null)
    fi

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
    else
        printf '{"status":"fail","error":"no_network_tool"}'
    fi
}

# ─────────────────────────────────────────────
# Apply network shield
# ─────────────────────────────────────────────
shield_on() {
    GMS_UID=$(get_gms_uid)
    if [ -z "$GMS_UID" ]; then
        log "ERROR: Could not find GMS UID"
        printf '{"error":"GMS UID not found"}'
        return 1
    fi
    log "GMS UID resolved: $GMS_UID"

    # Test whether xt_owner module is available before trying to use it
    IPTABLES_OWNER_OK=false
    if iptables -I OUTPUT 1 -m owner --uid-owner "$GMS_UID" -d 127.0.0.2 -j DROP 2>/dev/null; then
        iptables -D OUTPUT -m owner --uid-owner "$GMS_UID" -d 127.0.0.2 -j DROP 2>/dev/null
        IPTABLES_OWNER_OK=true
    fi

    if [ "$IPTABLES_OWNER_OK" = "true" ]; then
        # Block GMS UID outbound to Google geolocation IP ranges
        for range in 142.250.0.0/15 216.58.0.0/16 74.125.0.0/16 108.177.0.0/17; do
            iptables -I OUTPUT 1 -m owner --uid-owner "$GMS_UID" -d "$range" -j DROP 2>/dev/null \
                && log "Blocked GMS uid=$GMS_UID -> $range"
        done
        log "iptables GMS geoloc shield active"
    else
        log "xt_owner module not available — using settings-only shield"
    fi

    # Settings-based suppression (always apply, belt + suspenders)
    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global ble_scan_always_enabled 0 2>/dev/null
    settings put secure location_mode 3 2>/dev/null
    content insert --uri content://com.google.settings/partner \
        --bind name:s:network_location_opt_in --bind value:s:0 2>/dev/null || true
    content insert --uri content://com.google.settings/partner \
        --bind name:s:use_location_for_services --bind value:s:0 2>/dev/null || true

    log "Network shield enabled (iptables=$IPTABLES_OWNER_OK)"
    printf '{"shield":"on","gms_uid":%s,"iptables":%s}' "$GMS_UID" "$IPTABLES_OWNER_OK"
    return 0
}

# ─────────────────────────────────────────────
# Remove network shield
# ─────────────────────────────────────────────
shield_off() {
    GMS_UID=$(get_gms_uid)
    if [ -n "$GMS_UID" ]; then
        for range in 142.250.0.0/15 216.58.0.0/16 74.125.0.0/16 108.177.0.0/17; do
            iptables -D OUTPUT -m owner --uid-owner "$GMS_UID" -d "$range" -j DROP 2>/dev/null || true
        done
        log "iptables rules removed for uid=$GMS_UID"
    fi

    settings put global wifi_scan_always_enabled 1 2>/dev/null
    settings put global ble_scan_always_enabled 1 2>/dev/null

    log "Network shield disabled"
    printf '{"shield":"off","status":"restored"}'
    return 0
}

# ─────────────────────────────────────────────
# Full status JSON
# ─────────────────────────────────────────────
cmd_status() {
    GMS_UID=$(get_gms_uid)
    VPN_JSON=$(get_vpn_status)
    SHIELD_ACTIVE="false"

    if [ -n "$GMS_UID" ]; then
        if iptables -L OUTPUT -n 2>/dev/null | grep -q "uid-owner $GMS_UID"; then
            SHIELD_ACTIVE="true"
        fi
    fi

    WIFI_SCAN=$(settings get global wifi_scan_always_enabled 2>/dev/null | tr -d ' \r\n')
    BLE_SCAN=$(settings get global ble_scan_always_enabled 2>/dev/null | tr -d ' \r\n')

    printf '{"gms_uid":"%s","shield_active":%s,"vpn":%s,"wifi_scan":"%s","ble_scan":"%s"}' \
        "${GMS_UID:-unknown}" "$SHIELD_ACTIVE" "$VPN_JSON" \
        "${WIFI_SCAN:-1}" "${BLE_SCAN:-1}"
    return 0
}

case "$ACTION" in
    on|enable|start)   shield_on ;;
    off|disable|stop)  shield_off ;;
    status)            cmd_status ;;
    vpn)               get_vpn_status ;;
    ip-check)          cmd_ip_check ;;
    *)
        echo "Usage: net_shield.sh {on|off|status|vpn|ip-check}"
        exit 1
        ;;
esac
