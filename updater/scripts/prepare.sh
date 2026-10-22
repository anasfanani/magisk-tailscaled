#!/system/bin/sh
# Existing v2 installs only. Invoked after extraction, before any live file changes.
set -eu
umask 077
MODPATH=${1:?Module staging path required}
ARCH=${2:?Architecture required}
TS=/data/adb/tailscale
P="$MODPATH/updater"
export PATH="$TS/bin:$TS/scripts:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:$PATH"
[ "$(id -u)" = 0 ]
[ -s "$TS/tailscaled.state" ] || { echo 'Expected v2 flat state. Fresh/legacy installs need separate review.'; exit 1; }
[ -f "$TS/settings.sh" ] && [ -f "$TS/scripts/tailscaled.service" ]
[ "$(readlink -f "$TS/bin/tailscale")" = "$TS/bin/tailscaled" ] || { echo 'Expected combined v2 core'; exit 1; }
[ -x "$TS/bin/jq" ] || { echo 'Existing jq required'; exit 1; }
[ -f "$P/bin/tailscaled-$ARCH" ] || { echo 'Existing installs require a full ZIP with the matching Android core. Nothing changed.'; exit 1; }
(cd "$P/bin" && sha256sum -c "SHA256SUMS-$ARCH")
mv "$P/bin/tailscaled-$ARCH" "$P/bin/tailscaled"
if [ -f "$P/bin/android-core-check-$ARCH" ]; then mv "$P/bin/android-core-check-$ARCH" "$P/bin/android-core-check"; fi
chmod 0755 "$P/bin/tailscaled"
[ ! -f "$P/bin/android-core-check" ] || chmod 0755 "$P/bin/android-core-check"
timeout 10 "$P/bin/tailscaled" --version > "$P/bin/target-version"
target=$(head -n 1 "$P/bin/target-version")
current=$(timeout 10 "$TS/bin/tailscaled" --version | head -n 1)
valid_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9._+-]+)?$'; }
valid_version "$target" && valid_version "$current" || { echo 'Unrecognized executable version'; exit 1; }
# Compare numeric triples; distribution suffixes do not establish precedence.
awk -v old="$current" -v new="$target" 'BEGIN {
 split(old,a,/[^0-9]+/); split(new,b,/[^0-9]+/);
 for(i=1;i<=3;i++){if(b[i]+0>a[i]+0)exit 0;if(b[i]+0<a[i]+0)exit 1} exit 0
}' || { echo "Refusing core downgrade: $current -> $target"; exit 1; }
printf '%s\n' "$target" > "$P/bin/target-version"
(cd "$P" && sha256sum bin/tailscaled > bin/SHA256SUMS)
if [ -x "$P/bin/android-core-check" ]; then (cd "$P" && sha256sum bin/android-core-check >> bin/SHA256SUMS); fi
# Identical core: register the module update without restarting or touching state.
if cmp -s "$P/bin/tailscaled" "$TS/bin/tailscaled"; then
 echo "Core already installed: $target. Preserving running service."
 exit 0
fi
sh "$P/scripts/upgrade.sh"
