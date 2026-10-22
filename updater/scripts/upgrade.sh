#!/system/bin/sh
set -eu
umask 077
TS=/data/adb/tailscale
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG=$(dirname "$HERE")
[ "$(id -u)" = 0 ] || { echo 'Root required'; exit 1; }
[ "$(getenforce)" = Enforcing ] || { echo 'This procedure expects SELinux Enforcing'; exit 1; }
export PATH="$TS/bin:$TS/scripts:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:$PATH"
for x in timeout jq busybox readlink sha256sum chcon tar nohup; do command -v "$x" >/dev/null || { echo "Required tool missing: $x" >&2; exit 1; }; done
[ -f "$PKG/bin/tailscaled" ] || { echo 'Build outputs missing. This source kit cannot upgrade until built.'; exit 1; }
(cd "$PKG" && sha256sum -c bin/SHA256SUMS)
core=$(readlink -f "$TS/bin/tailscaled")
case "$core" in "$TS"/bin/*) ;; *) echo 'Core is outside expected external bin directory'; exit 1;; esac
[ -f "$core" ] && [ ! -L "$core" ]
[ "$(readlink -f "$TS/bin/tailscale")" = "$core" ] || { echo 'Separated or wrapped binaries need review'; exit 1; }
svc="$TS/scripts/tailscaled.service"
[ -f "$svc" ]
mkdir -p "$TS/backups"
mkdir "$TS/backups/upgrade.lock" 2>/dev/null || { echo 'Another upgrade or stale lock exists'; exit 1; }
B="$TS/backups/upgrade-$(date +%Y%m%d-%H%M%S)-$$"
mkdir "$B"
echo "Private reports and backup directory: $B"
cp "$HERE/rollback.sh" "$B/rollback.sh"
watchdog=''
changed=0
stopped=0
finish() {
 rc=$?
 trap - EXIT INT TERM HUP
 if [ "$changed" = 1 ] && [ ! -f "$B/COMMITTED" ]; then
  sh "$B/rollback.sh" "$B" || { echo "AUTOMATIC ROLLBACK FAILED: $B" >&2; rc=1; }
 elif [ "$stopped" = 1 ] && [ ! -f "$B/COMMITTED" ]; then
  timeout 45 sh "$svc" start || rc=1
 fi
 touch "$B/FINISHED"
 [ -z "$watchdog" ] || kill "$watchdog" 2>/dev/null || true
 rmdir "$TS/backups/upgrade.lock" 2>/dev/null || true
 if [ "$rc" -ne 0 ]; then echo "Upgrade stopped (exit $rc). Inspect private reports: $B" >&2; fi
 exit "$rc"
}
trap finish EXIT
trap 'exit 1' INT TERM HUP
pid=''
for pd in $(pidof tailscaled 2>/dev/null || true); do
 d="/proc/$pd"
 if [ "$(readlink -f "$d/exe" 2>/dev/null || true)" = "$core" ]; then
  [ -z "$pid" ] || { echo 'Multiple core processes; abort'; exit 1; }
  pid=${d##*/}
 fi
done
[ -n "$pid" ] || { echo 'Existing daemon must be running'; exit 1; }
tr '\000' '\n' < "/proc/$pid/cmdline" > "$B/argv.txt"
arg() {
 awk -v key="$1" '
  nextval {print; exit}
  $0=="-"key || $0=="--"key {nextval=1; next}
  index($0,"-"key"=")==1 || index($0,"--"key"=")==1 {sub(/^[^=]*=/,""); print; exit}
 ' "$B/argv.txt"
}
state="$TS/tailscaled.state"
socket="$TS/tailscaled.sock"
[ "$core" = "$TS/bin/tailscaled" ]
[ -z "$(arg state)" ] || [ "$(arg state)" = "$state" ] || { echo 'Nonstandard state path; refusing automatic upgrade'; exit 1; }
[ -z "$(arg socket)" ] || [ "$(arg socket)" = "$socket" ] || { echo 'Nonstandard socket path; refusing automatic upgrade'; exit 1; }
ip link show tailscale0 > "$B/before-interface.txt"
ip -4 rule show > "$B/before-rule4.txt"
ip -6 rule show > "$B/before-rule6.txt"
ip -o -6 addr show dev tailscale0 | awk '$4 ~ /^fd7a:115c:a1e0:/ {print $4}' > "$B/before-tun6.txt"
sha256sum "$TS/settings.sh" "$svc" > "$B/config-SHA256SUMS"
[ -s "$state" ]
cli="$TS/bin/tailscale"
timeout 10 "$cli" --socket="$socket" version > "$B/old-version.txt"

timeout 10 "$cli" --socket="$socket" status --json > "$B/before.json"
jq -e '.BackendState=="Running"' "$B/before.json" >/dev/null
timeout 10 "$cli" --socket="$socket" debug prefs > "$B/old-prefs.json"
jq -e '(.RunSSH // false)==false' "$B/old-prefs.json" >/dev/null || { echo 'This build omits Tailscale SSH, but it is enabled on this device; abort'; exit 1; }
cat "/proc/$pid/status" > "$B/process-status.txt"
cat "/proc/$pid/attr/current" > "$B/process-context.txt"
readlink "/proc/$pid/ns/net" > "$B/process-netns.txt"
# Inspected v2 service is uid=0/gid=0 with no setuidgid transition.
# Reject an unknown identity; do not quietly change its group or service.
gid=$(awk '/^Gid:/ {print $2}' "$B/process-status.txt")
[ "$gid" = "0" ] || { echo 'Expected current service GID 0'; exit 1; }
check_identity() {
 jq -s -e --arg ctx "$(tr -d '\000\r\n' < "$B/process-context.txt")" --arg ns "$(cat "$B/process-netns.txt")" '
  any(.[]; .test=="identity" and .ok==true and .value.uid==0 and .value.euid==0 and .value.gid==0 and .value.egid==0 and .value.context==$ctx and .value.netns==$ns)
 ' "$1" >/dev/null
}
# Optional Android DNS/identity probe can accompany a platform-specific full ZIP.
if [ -x "$PKG/bin/android-core-check" ]; then
 timeout 70 "$PKG/bin/android-core-check" > "$B/precheck.jsonl" 2>&1
 check_identity "$B/precheck.jsonl"
fi
timeout 10 "$PKG/bin/tailscaled" --version > "$B/new-version.txt"
cp "$PKG/bin/target-version" "$B/target-version"
target=$(cat "$B/target-version")
[ "$(head -n 1 "$B/new-version.txt")" = "$target" ]
printf '%s\n' "$core" > "$B/core.path"
printf '%s\n' "$state" > "$B/state.path"
ls -Zd "$core" | awk '{print $1}' > "$B/core.context"
ls -Zd "$state" | awk '{print $1}' > "$B/state.context"
# Snapshot configuration for inspection. Do not execute a new module installer.
cp -p "$TS/settings.sh" "$B/settings.sh"
cp -p "$svc" "$B/service.sh"
# Stop via existing hooks, then take a coherent backup of state.
cp "$HERE/watchdog.sh" "$B/watchdog.sh"
printf '%s\n' "$$" > "$B/installer.pid"
awk '{print $22}' "/proc/$$/stat" > "$B/installer.start" 2>/dev/null || true
nohup sh "$B/watchdog.sh" "$B" > "$B/watchdog.log" 2>&1 &
watchdog=$!
changed=0
stopped=1
touch "$B/STOPPING"
timeout 45 sh "$svc" stop > "$B/stop.log" 2>&1 || { timeout 45 sh "$svc" start || true; exit 1; }
for pd in $(pidof tailscaled 2>/dev/null || true); do
 d="/proc/$pd"
 [ "$(readlink -f "$d/exe" 2>/dev/null | sed 's/ (deleted)$//' || true)" != "$core" ] || { echo 'Old daemon survived stop'; timeout 45 sh "$svc" start || true; exit 1; }
done
cp -p "$core" "$B/core.old"
cp -p "$state" "$B/state.old"
(cd "$B" && sha256sum core.old state.old > BACKUP-SHA256SUMS)
# A private configuration snapshot excludes the runtime socket and bulk logs.
if ! tar -cpf "$B/configuration.tar" --exclude='*.sock' --exclude='backups' --exclude='run' -C "$TS" .; then
 timeout 45 sh "$svc" start || true
 exit 1
fi
touch "$B/READY"
changed=1
cp -p "$core" "$core.upgrade"
cat "$PKG/bin/tailscaled" > "$core.upgrade"
chcon "$(cat "$B/core.context")" "$core.upgrade"
[ "$(ls -Zd "$core.upgrade" | awk '{print $1}')" = "$(cat "$B/core.context")" ]
[ "$(sha256sum "$core.upgrade" | awk '{print $1}')" = "$(sha256sum "$PKG/bin/tailscaled" | awk '{print $1}')" ]
mv -f "$core.upgrade" "$core"
timeout 45 sh "$svc" start > "$B/start.log" 2>&1
end=$(( $(date +%s) + 180 ))
stable=0
while [ "$(date +%s)" -lt "$end" ]; do
 if timeout 8 "$cli" --socket="$socket" status --json > "$B/after.json" 2>/dev/null &&
    jq -e '.BackendState=="Running" and .Self.Online==true and (.Self.Relay // "")!=""' "$B/after.json" >/dev/null; then
  stable=$((stable+1))
  [ "$stable" -ge 3 ] && break
 else stable=0
 fi
 sleep 3
done
[ "$stable" -ge 3 ] || { echo 'Backend/DERP did not stabilize; restoring old core and state'; exit 1; }
if [ -x "$PKG/bin/android-core-check" ]; then
 timeout 70 "$PKG/bin/android-core-check" > "$B/postcheck.jsonl" 2>&1
 check_identity "$B/postcheck.jsonl"
fi
timeout 10 "$cli" --socket="$socket" version > "$B/final-version.txt"
[ "$(head -n 1 "$B/final-version.txt")" = "$target" ]
postpid=''
for pd in $(pidof tailscaled 2>/dev/null || true); do
 d="/proc/$pd"
 if [ "$(readlink -f "$d/exe" 2>/dev/null || true)" = "$core" ]; then
  [ -z "$postpid" ] || { echo 'Multiple post-upgrade processes'; exit 1; }
  postpid=${d##*/}
 fi
done
[ -n "$postpid" ]
cat "/proc/$postpid/attr/current" > "$B/after-context.txt"
cmp -s "$B/process-context.txt" "$B/after-context.txt"
tr '\000' '\n' < "/proc/$postpid/cmdline" > "$B/after-argv.txt"
cmp -s "$B/argv.txt" "$B/after-argv.txt"
# Preserve the existing native TUN, node identity, config and IPv6 address.
ip link show tailscale0 > "$B/after-interface.txt"
ip -4 rule show > "$B/after-rule4.txt"
ip -6 rule show > "$B/after-rule6.txt"
ip -o -6 addr show dev tailscale0 | awk '$4 ~ /^fd7a:115c:a1e0:/ {print $4}' > "$B/after-tun6.txt"
[ -s "$B/before-tun6.txt" ]
[ -s "$B/after-tun6.txt" ]
cmp -s "$B/before-tun6.txt" "$B/after-tun6.txt"
jq -s -e '.[0].Self.ID==.[1].Self.ID and .[0].Self.TailscaleIPs==.[1].Self.TailscaleIPs' "$B/before.json" "$B/after.json" >/dev/null
sha256sum -c "$B/config-SHA256SUMS"
grep -E '^12500:.*100\.64\.0\.0/10.*52' "$B/after-rule4.txt" >/dev/null
grep -E '^12500:.*fd7a:115c:a1e0::/48.*52' "$B/after-rule6.txt" >/dev/null
grep -E '^13001:.*0x10020000/0x1e000000.*52' "$B/after-rule4.txt" >/dev/null
# Daemon API also needs to identify the new version.
jq -e --arg target "$target" '.Version == $target or (.Version | startswith($target + "-"))' "$B/after.json" >/dev/null
[ "$(getenforce)" = Enforcing ]
touch "$B/COMMITTED"
printf '%s\n' "$B" > "$TS/backups/last-safe-upgrade"
echo "Upgrade accepted. Backup and reports: $B"
echo "Manual rollback: sh $B/rollback.sh $B"
