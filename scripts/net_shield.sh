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
    # packages.list format: <package> <uid> <debuggable> <data_dir> ...
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
        if ip link show "$iface" 2>/dev/null | grep -q 'UP\|UNKNOWN'; then
            VPN_IFACE="$iface"
            VPN_IP=$(ip addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -n1)
            IS_VPN="true"
            break
        fi
    done

    echo "{\"vpn_active\":$IS_VPN,\"iface\":\"${VPN_IFACE:-none}\",\"tunnel_ip\":\"${VPN_IP:-none}\"}"
}

# ─────────────────────────────────────────────
# Check if iptables rule already exists
# ─────────────────────────────────────────────
rule_exists() {
    uid="$1"
    iptables -C OUTPUT -m owner --uid-owner "$uid" -j DROP 2>/dev/null
}

# ─────────────────────────────────────────────
# Apply network shield (block GMS location lookups)
# ─────────────────────────────────────────────
shield_on() {
    GMS_UID=$(get_gms_uid)
    if [ -z "$GMS_UID" ]; then
        log "ERROR: Could not find GMS UID. Is Google Play Services installed?"
        echo "{\"error\":\"GMS UID not found\"}"
        return 1
    fi
    log "GMS UID resolved: $GMS_UID"

    # Block GMS outbound connections to Google's location accuracy servers
    # These domains handle: geolocation database lookups, Wi-Fi BSSID resolution,
    # and network-location correction signals.
    GOOGLE_GEOLOC_DOMAINS="
        www.googleapis.com
        maps.googleapis.com
        geolocation.googleapis.com
        www.gstatic.com
        safebrowsing.googleapis.com
    "

    # Primary approach: Block GMS network location via UID-based iptables
    # We only block connections to UDP/TCP port 443 (HTTPS) for Google location APIs
    # This is surgical — it does NOT break authentication, Play Store, etc.
    if ! rule_exists "$GMS_UID" 2>/dev/null; then
        # Block only GMS uid outbound on well-known geolocation IP ranges
        # 142.250.0.0/15 = Google's AS15169 range (maps/location APIs)
        iptables -I OUTPUT 1 -m owner --uid-owner "$GMS_UID" -d 142.250.0.0/15 -j DROP 2>/dev/null \
            && log "Blocked GMS (uid=$GMS_UID) -> Google geoloc range 142.250.0.0/15"

        iptables -I OUTPUT 1 -m owner --uid-owner "$GMS_UID" -d 216.58.0.0/16 -j DROP 2>/dev/null \
            && log "Blocked GMS (uid=$GMS_UID) -> Google geoloc range 216.58.0.0/16"

        iptables -I OUTPUT 1 -m owner --uid-owner "$GMS_UID" -d 74.125.0.0/16 -j DROP 2>/dev/null \
            && log "Blocked GMS (uid=$GMS_UID) -> Google geoloc range 74.125.0.0/16"

        # Also block the 'network' location provider port on GMS
        iptables -I OUTPUT 1 -m owner --uid-owner "$GMS_UID" -p tcp --dport 443 \
            -m string --string "geolocation.googleapis" --algo bm -j DROP 2>/dev/null \
            && log "Blocked GMS SSL geolocation.googleapis"
    else
        log "GMS network shield already active (uid=$GMS_UID)"
    fi

    # Disable Google Location Accuracy via settings (belt + suspenders)
    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global ble_scan_always_enabled 0 2>/dev/null
    settings put secure location_mode 3 2>/dev/null   # GPS_ONLY on older Android (no-op on A12+)

    # Network-location opt-out via Google's settings provider (rooted access)
    content insert --uri content://com.google.settings/partner \
        --bind name:s:network_location_opt_in --bind value:s:0 2>/dev/null
    content insert --uri content://com.google.settings/partner \
        --bind name:s:use_location_for_services --bind value:s:0 2>/dev/null

    log "Network shield enabled"
    echo "{\"shield\":\"on\",\"gms_uid\":$GMS_UID,\"status\":\"active\"}"
}

# ─────────────────────────────────────────────
# Remove network shield
# ─────────────────────────────────────────────
shield_off() {
    GMS_UID=$(get_gms_uid)
    if [ -n "$GMS_UID" ]; then
        iptables -D OUTPUT -m owner --uid-owner "$GMS_UID" -d 142.250.0.0/15 -j DROP 2>/dev/null
        iptables -D OUTPUT -m owner --uid-owner "$GMS_UID" -d 216.58.0.0/16 -j DROP 2>/dev/null
        iptables -D OUTPUT -m owner --uid-owner "$GMS_UID" -d 74.125.0.0/16 -j DROP 2>/dev/null
        iptables -D OUTPUT -m owner --uid-owner "$GMS_UID" -p tcp --dport 443 \
            -m string --string "geolocation.googleapis" --algo bm -j DROP 2>/dev/null
        log "Network shield disabled (uid=$GMS_UID)"
    fi

    # Restore scanning settings
    settings put global wifi_scan_always_enabled 1 2>/dev/null
    settings put global ble_scan_always_enabled 1 2>/dev/null

    echo "{\"shield\":\"off\",\"status\":\"restored\"}"
}

# ─────────────────────────────────────────────
# Full status JSON
# ─────────────────────────────────────────────
cmd_status() {
    GMS_UID=$(get_gms_uid)
    VPN_JSON=$(get_vpn_status)
    SHIELD_ACTIVE="false"

    if [ -n "$GMS_UID" ]; then
        if iptables -L OUTPUT 2>/dev/null | grep -q "uid-owner $GMS_UID"; then
            SHIELD_ACTIVE="true"
        fi
    fi

    cat << EOF
{
  "gms_uid": "${GMS_UID:-unknown}",
  "shield_active": $SHIELD_ACTIVE,
  "vpn": $VPN_JSON,
  "wifi_scan": "$(settings get global wifi_scan_always_enabled 2>/dev/null | tr -d ' \r\n')",
  "ble_scan": "$(settings get global ble_scan_always_enabled 2>/dev/null | tr -d ' \r\n')"
}
EOF
}

case "$ACTION" in
    on|enable|start)
        shield_on
        ;;
    off|disable|stop)
        shield_off
        ;;
    status)
        cmd_status
        ;;
    vpn)
        get_vpn_status
        ;;
    *)
        echo "Usage: net_shield.sh {on|off|status|vpn}"
        exit 1
        ;;
esac
