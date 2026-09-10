#!/system/bin/sh
SKIPUNZIP=0

ui_print "************************************************"
ui_print "*        KernelSU Mock GPS (WebUI)             *"
ui_print "*   No Developer Options Mock Toggle Required  *"
ui_print "************************************************"

ui_print "- Installing module files..."

# Fix script execution permissions
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755 0755
set_perm "$MODPATH/action.sh" 0 0 0755 0755

# Ensure persistent data directory exists
CONFIG_DIR="/data/adb/ksu_fakegps"
mkdir -p "$CONFIG_DIR"
chmod 0755 "$CONFIG_DIR"

# Initialize default configuration if not present
if [ ! -f "$CONFIG_DIR/config.json" ]; then
  ui_print "- Initializing default location configuration..."
  cat << 'EOF' > "$CONFIG_DIR/config.json"
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
  chmod 0644 "$CONFIG_DIR/config.json"
fi

# Ensure webroot permissions are correct
ui_print "- Configuring WebUI environment..."
if [ -d "$MODPATH/webroot" ]; then
  find "$MODPATH/webroot" -type d -exec chmod 0755 {} +
  find "$MODPATH/webroot" -type f -exec chmod 0644 {} +
fi

ui_print "- Checking system location services..."
# Pre-grant mock location capability to system shell
appops set 2000 android:mock_location allow 2>/dev/null
appops set 0 android:mock_location allow 2>/dev/null
appops set com.android.shell android:mock_location allow 2>/dev/null
appops set --user 0 2000 android:mock_location allow 2>/dev/null
appops set --user 0 com.android.shell android:mock_location allow 2>/dev/null

# Make all scripts executable
chmod 0755 "$MODPATH/scripts/gps_daemon.sh" 2>/dev/null
chmod 0755 "$MODPATH/scripts/gps_control.sh" 2>/dev/null
chmod 0755 "$MODPATH/scripts/net_shield.sh" 2>/dev/null

ui_print "************************************************"
ui_print " Installation Finished!                         "
ui_print " Open KernelSU Manager -> Modules to launch UI  "
ui_print "************************************************"
