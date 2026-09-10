#!/system/bin/sh
MODDIR=${0%/*}

# Toggle daemon state reliably using control script verification
STATUS=$("$MODDIR/scripts/gps_control.sh" status 2>/dev/null)
if echo "$STATUS" | grep -q '"active"[[:space:]]*:[[:space:]]*true'; then
    "$MODDIR/scripts/gps_control.sh" stop
    echo "KernelSU Fake GPS: Stopped"
else
    "$MODDIR/scripts/gps_control.sh" start
    echo "KernelSU Fake GPS: Started"
fi
