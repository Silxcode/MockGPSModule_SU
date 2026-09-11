#!/system/bin/sh
# Late-boot service for KernelSU Mock GPS Module
# Engineered with fail-safes: 100% non-blocking, max timeout, zero boot impact.

MODDIR=${0%/*}
CONFIG_DIR="/data/adb/ksu_fakegps"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Run in background subshell so service.sh exits immediately (0ms blocking time)
(
    # Check if disabled by user or rescue mode
    if [ -f "$MODDIR/disable" ] || [ -f "$CONFIG_DIR/disable" ]; then
        exit 0
    fi

    # Wait for Android boot completion with a hard limit of 60 seconds (30 * 2s)
    TIMEOUT=30
    COUNT=0
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
        COUNT=$((COUNT + 1))
        if [ "$COUNT" -ge "$TIMEOUT" ]; then
            # Safe exit if boot took unusually long
            exit 0
        fi
    done

    # Allow LocationManagerService and core framework to stabilize
    sleep 6

    # Clean up stale PID and status from previous boot
    rm -f "$CONFIG_DIR/daemon.pid"
    echo '{"active":false,"pid":0,"last_tick":0}' > "$CONFIG_DIR/status.json"

    # Only start if explicitly configured for boot persistence
    if [ -f "$CONFIG_FILE" ]; then
        BOOT_PERSIST=$(grep '"boot_persist"[[:space:]]*:[[:space:]]*true' "$CONFIG_FILE" 2>/dev/null)
        ENABLED=$(grep '"enabled"[[:space:]]*:[[:space:]]*true' "$CONFIG_FILE" 2>/dev/null)
        
        if [ -n "$BOOT_PERSIST" ] && [ -n "$ENABLED" ]; then
            if [ -f "$MODDIR/scripts/gps_control.sh" ]; then
                /system/bin/sh "$MODDIR/scripts/gps_control.sh" start >/dev/null 2>&1
            fi
        fi
    fi
) &

exit 0
