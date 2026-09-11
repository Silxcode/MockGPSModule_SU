#!/system/bin/sh
MODDIR=${0%/*}

# Toggle daemon state reliably using control script verification
STATUS=$(/system/bin/sh "$MODDIR/scripts/gps_control.sh" status 2>/dev/null)
if echo "$STATUS" | grep -q '"active"[[:space:]]*:[[:space:]]*true'; then
    /system/bin/sh "$MODDIR/scripts/gps_control.sh" stop
    echo "KernelSU Fake GPS: Stopped"
else
    /system/bin/sh "$MODDIR/scripts/gps_control.sh" start
    echo "KernelSU Fake GPS: Started"
fi
