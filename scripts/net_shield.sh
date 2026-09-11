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
# Uses curl or toybox wget (HTTP fallback for TLS-less toybox)
# ─────────────────────────────────────────────
cmd_ip_check() {
    URL_HTTP="http://ip-api.com/json/?fields=status,country,countryCode,city,query"
    URL_HTTPS="https://ip-api.com/json/?fields=status,country,countryCode,city,query"
    RESULT=""

    # Try curl first with HTTPS if available
    if command -v curl >/dev/null 2>&1; then
        RESULT=$(curl -sf --max-time 6 "$URL_HTTPS" 2>/dev/null || curl -sf --max-time 6 "$URL_HTTP" 2>/dev/null)
    fi

    # Fall back to wget (toybox wget on stock Android works over HTTP port 80 without SSL errors)
    if [ -z "$RESULT" ] && command -v wget >/dev/null 2>&1; then
        RESULT=$(wget -qO- --timeout=6 "$URL_HTTP" 2>/dev/null)
    fi

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
    else
        printf '{"status":"fail","error":"no_network_tool"}'
    fi
}

# ─────────────────────────────────────────────
# Chain management helper (prevents rule leaks and duplication)
# ─────────────────────────────────────────────
setup_chains() {
    iptables -N KSU_SHIELD 2>/dev/null
    if ! iptables -C OUTPUT -j KSU_SHIELD 2>/dev/null; then
        iptables -I OUTPUT 1 -j KSU_SHIELD 2>/dev/null
    fi

    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -N KSU_SHIELD 2>/dev/null
        if ! ip6tables -C OUTPUT -j KSU_SHIELD 2>/dev/null; then
            ip6tables -I OUTPUT 1 -j KSU_SHIELD 2>/dev/null
        fi
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

    setup_chains

    # Flush existing rules in KSU_SHIELD to avoid any duplication
    iptables -F KSU_SHIELD 2>/dev/null
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -F KSU_SHIELD 2>/dev/null
    fi

    # Test whether xt_owner module is available before trying to use it
    IPTABLES_OWNER_OK=false
    if iptables -A KSU_SHIELD -m owner --uid-owner "$GMS_UID" -d 127.0.0.2 -j DROP 2>/dev/null; then
        iptables -F KSU_SHIELD 2>/dev/null
        IPTABLES_OWNER_OK=true
    fi

    if [ "$IPTABLES_OWNER_OK" = "true" ]; then
        # Block GMS UID outbound to Google geolocation IPv4 ranges
        for range in 142.250.0.0/15 216.58.0.0/16 74.125.0.0/16 108.177.0.0/17; do
            iptables -A KSU_SHIELD -m owner --uid-owner "$GMS_UID" -d "$range" -j DROP 2>/dev/null \
                && log "Blocked GMS uid=$GMS_UID -> $range"
        done

        # Block GMS UID outbound to Google geolocation IPv6 ranges
        if command -v ip6tables >/dev/null 2>&1; then
            for range6 in 2607:f8b0::/32 2001:4860::/32; do
                ip6tables -A KSU_SHIELD -m owner --uid-owner "$GMS_UID" -d "$range6" -j DROP 2>/dev/null \
                    && log "Blocked GMS uid=$GMS_UID IPv6 -> $range6"
            done
        fi
        log "iptables/ip6tables GMS geoloc shield active"
    else
        log "xt_owner module not available — using settings-only shield"
    fi

    # Settings-based suppression (always apply, belt + suspenders)
    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global ble_scan_always_enabled 0 2>/dev/null

    log "Network shield enabled (iptables=$IPTABLES_OWNER_OK)"
    printf '{"shield":"on","gms_uid":%s,"iptables":%s}' "$GMS_UID" "$IPTABLES_OWNER_OK"
    return 0
}

# ─────────────────────────────────────────────
# Remove network shield
# ─────────────────────────────────────────────
shield_off() {
    # Atomically flush custom chains (leaves zero residual rules, cannot leak)
    iptables -F KSU_SHIELD 2>/dev/null || true
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -F KSU_SHIELD 2>/dev/null || true
    fi

    settings put global wifi_scan_always_enabled 1 2>/dev/null
    settings put global ble_scan_always_enabled 1 2>/dev/null

    log "Network shield disabled (KSU_SHIELD flushed)"
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

    if iptables -L KSU_SHIELD -n 2>/dev/null | grep -q "DROP"; then
        SHIELD_ACTIVE="true"
    elif [ -n "$GMS_UID" ] && iptables -L OUTPUT -n 2>/dev/null | grep -q "uid-owner $GMS_UID"; then
        SHIELD_ACTIVE="true"
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
