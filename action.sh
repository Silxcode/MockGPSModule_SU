#!/system/bin/sh
MODDIR=${0%/*}
CONFIG_DIR="/data/adb/ksu_fakegps"

# Toggle daemon state
if [ -f "$CONFIG_DIR/daemon.pid" ] && kill -0 "$(cat "$CONFIG_DIR/daemon.pid" 2>/dev/null)" 2>/dev/null; then
    "$MODDIR/scripts/gps_control.sh" stop
    echo "KernelSU Fake GPS: Stopped"
else
    "$MODDIR/scripts/gps_control.sh" start
    echo "KernelSU Fake GPS: Started"
fi
