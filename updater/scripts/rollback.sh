#!/system/bin/sh
set -eu
TS=/data/adb/tailscale
B=${1:?Usage: sh rollback.sh /data/adb/tailscale/backups/upgrade-TIMESTAMP-PID}
case "$B" in "$TS"/backups/upgrade-*) ;; *) echo 'Invalid backup directory' >&2; exit 1;; esac
[ "$(id -u)" = 0 ]
[ -f "$B/READY" ]
(cd "$B" && sha256sum -c BACKUP-SHA256SUMS)
[ ! -f "$B/RECOVERED" ] || exit 0
mkdir "$B/recovery-lock" 2>/dev/null || { echo 'Recovery already in progress'; exit 1; }
trap 'rmdir "$B/recovery-lock" 2>/dev/null || true' EXIT
core=$(cat "$B/core.path"); state=$(cat "$B/state.path")
case "$core" in "$TS"/bin/*) ;; *) exit 1;; esac
case "$state" in "$TS/tailscaled.state") ;; *) exit 1;; esac
svc="$TS/scripts/tailscaled.service"
export PATH="$TS/bin:$TS/scripts:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:$PATH"
timeout 45 sh "$svc" stop >> "$B/recovery.log" 2>&1 || true
# Never overwrite a live executable or restore state while any matching daemon survives.
for pd in $(pidof tailscaled 2>/dev/null || true); do
 d="/proc/$pd"
 [ "$(readlink -f "$d/exe" 2>/dev/null | sed 's/ (deleted)$//' || true)" != "$core" ] || { echo 'Daemon still alive; recovery refused' >&2; exit 1; }
done
cp -p "$B/core.old" "$core.restore"
chcon "$(cat "$B/core.context")" "$core.restore"
mv -f "$core.restore" "$core"
cp -p "$B/state.old" "$state.restore"
chcon "$(cat "$B/state.context")" "$state.restore"
mv -f "$state.restore" "$state"
timeout 45 sh "$svc" start >> "$B/recovery.log" 2>&1 || { echo 'Old service start failed; see recovery.log' >&2; exit 1; }
echo 'Core and saved login state restored. Verify old BackendState=Running.'
touch "$B/RECOVERED"
rmdir "$TS/backups/upgrade.lock" 2>/dev/null || true
