#!/system/bin/sh
set -eu
B=${1:?Backup directory required}
TS=/data/adb/tailscale
# Bound the operation without imposing a new boot service.
i=0
while [ "$i" -lt 90 ]; do
 [ ! -f "$B/COMMITTED" ] && [ ! -f "$B/FINISHED" ] && [ ! -f "$B/RECOVERED" ] || exit 0
 sleep 5
 i=$((i+1))
done
# Never restore files concurrently with a slow but still-running installer.
# Compare kernel start time as well as PID to avoid signaling a reused PID.
owner=$(cat "$B/installer.pid" 2>/dev/null || true)
started=$(cat "$B/installer.start" 2>/dev/null || true)
owner_alive() {
 [ -n "$owner" ] && [ -n "$started" ] &&
 [ "$(awk '{print $22}' "/proc/$owner/stat" 2>/dev/null || true)" = "$started" ]
}
if owner_alive; then
 kill -TERM "$owner" 2>/dev/null || true
 i=0
 while owner_alive && [ "$i" -lt 30 ]; do
  [ ! -f "$B/FINISHED" ] || exit 0
  sleep 1
  i=$((i+1))
 done
 owner_alive && { echo 'Installer still alive; refusing concurrent recovery. Manual recovery required.' >&2; exit 1; }
fi
[ ! -f "$B/COMMITTED" ] && [ ! -f "$B/FINISHED" ] && [ ! -f "$B/RECOVERED" ] || exit 0
if [ -f "$B/READY" ]; then
 sh "$B/rollback.sh" "$B"
elif [ -f "$B/STOPPING" ]; then
 # Before READY, core and state have not been replaced; resume the original service.
 export PATH="$TS/bin:$TS/scripts:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:$PATH"
 timeout 45 sh "$TS/scripts/tailscaled.service" start
 rmdir "$TS/backups/upgrade.lock" 2>/dev/null || true
fi
