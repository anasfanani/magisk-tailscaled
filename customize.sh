#!/system/bin/sh

# DEBUG=1
[ -n "${DEBUG:-}" ] && {
	PS4="+ \${0##*/}:\${LINENO}: "
	set -e
	set -u
	set -x
	set
} || true

# Github download helper
gh_download() {
	REPO=$1
	MATCH=$2
	DOWNLOAD_URL=$(
		wget --no-check-certificate --timeout=10 -qO- "https://api.github.com/repos/${REPO}/releases/latest" |
			grep "browser_download_url" |
			grep "${MATCH}" |
			sed 's/.*"browser_download_url": "\([^"]*\)".*/\1/' ||
			true
	)
	if [ -z "$DOWNLOAD_URL" ]; then
		ui_print "! Unable to get release from https://github.com/${REPO}/releases"
		return 1
	fi
	FILENAME=$(basename "$DOWNLOAD_URL")
	ui_print "- Downloading $FILENAME..."
	wget --no-check-certificate --timeout=100 -qO "$TMPDIR/$FILENAME" "$DOWNLOAD_URL" || {
		ui_print "! Download timeout or failed"
		return 1
	}
}

# shellcheck disable=SC2034
SKIPUNZIP=1
# shellcheck disable=SC2034
SKIPMOUNT=false

if [ "$BOOTMODE" != true ]; then
	ui_print "! Please install in Magisk Manager or KernelSU Manager"
	ui_print "! Install from recovery is NOT supported"
	abort "-----------------------------------------------------------"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
	abort "error: Please update your KernelSU and KernelSU Manager"
fi

SERVICE_DIR="/data/adb/service.d"

TS_DIR="/data/adb/tailscale"
TS_BIN_DIR="$TS_DIR/bin"
TS_SCRIPTS_DIR="$TS_DIR/scripts"

case $ARCH in
arm) F_ARCH="armv7a" ;;
arm64) F_ARCH="aarch64" ;;
*)
	ui_print "Unsupported architecture: $ARCH"
	abort
	;;
esac
ui_print "- Detected architecture: $ARCH"

# Keep an existing v2 deployment intact. A lightweight ZIP may still be used
# for fresh installs; existing deployments require the verified full payload.
if [ -d "$TS_DIR" ]; then
 ui_print "- Preserving external settings, scripts, keys and login state"
 unzip -qqo "$ZIPFILE" -x 'META-INF/*' 'tailscale/*' -d "$MODPATH" || abort "Unable to stage module files"
 mkdir -p "$MODPATH/updater/bin" "$MODPATH/system/bin" || abort "Unable to create staging directories"
 unzip -qqjo "$ZIPFILE" "tailscale/bin/*-$ARCH" -d "$MODPATH/updater/bin" 2>/dev/null || true
 unzip -qqjo "$ZIPFILE" "tailscale/bin/SHA256SUMS-$ARCH" -d "$MODPATH/updater/bin" 2>/dev/null || true
 # Preserve the existing module-specific boot hook. General service.d hooks
 # remain untouched. No postinstall restart that would clear the run directory.
 ACTIVE_MODPATH="$(echo "$MODPATH" | sed 's/_update//')"
 if [ "$ACTIVE_MODPATH" != "$MODPATH" ] && [ -f "$ACTIVE_MODPATH/service.sh" ]; then
  cp -p "$ACTIVE_MODPATH/service.sh" "$MODPATH/service.sh" || abort "Unable to preserve boot hook"
 elif [ -f "$SERVICE_DIR/tailscaled_service.sh" ]; then
  rm -f "$MODPATH/service.sh"
 fi
 for binary in "$TS_BIN_DIR"/*; do
  [ -e "$binary" ] || continue
  ln -sf "$binary" "$MODPATH/system/bin/" || abort "Unable to stage command alias"
 done
 ln -sf "$TS_SCRIPTS_DIR/tailscaled.service" "$MODPATH/system/bin/" || abort "Unable to stage service alias"
 set_perm_recursive "$MODPATH/updater" 0 0 0755 0755 "u:object_r:system_file:s0"
 sh "$MODPATH/updater/scripts/prepare.sh" "$MODPATH" "$ARCH" || abort "Safe core update refused or rolled back; inspect /data/adb/tailscale/backups"
 ui_print "- Existing configuration preserved. Module update staged successfully."
 return 0
fi

mkdir -p "$TS_BIN_DIR"
unzip -qqjo "$ZIPFILE" "tailscale/bin/*-$ARCH" -d "$TS_BIN_DIR" 2>/dev/null || true
for f in "$TS_BIN_DIR"/*-"$ARCH"; do
	[ -f "$f" ] && mv "$f" "${f%-"$ARCH"}"
done

[ -f "$TS_BIN_DIR/tailscaled" ] || {
	gh_download "anasfanani/tailscale-android-cli" "tailscale_.*_${ARCH}\.tgz" || abort "error: Unable to download."
	tar -xzf "$TMPDIR/$FILENAME" -C $TS_BIN_DIR || abort "error: Unable extract archive."
}

[ -f "$TS_BIN_DIR/jq" ] || {
	gh_download "theshoqanebi/jq-build-for-android" "jq-${F_ARCH}-linux-android" || abort "error: Unable to download."
	mv -f "$TMPDIR/$FILENAME" "$TS_BIN_DIR/jq" || abort "error: Unable to move file."
}

ui_print "- Extracting files..."
unzip -qqo "$ZIPFILE" -x 'META-INF/*' 'tailscale/*' -d "$MODPATH"

mkdir -p "$TS_DIR" "$TS_SCRIPTS_DIR" "$SERVICE_DIR" "$MODPATH/system/bin/"
unzip -qqjo "$ZIPFILE" 'tailscale/scripts/*' -d "$TS_SCRIPTS_DIR"
unzip -qqjo "$ZIPFILE" 'tailscale/settings.sh' -d "$TS_DIR"
ln -sf "$TS_BIN_DIR/tailscaled" "$TS_BIN_DIR/tailscale"
ln -sf "$TS_BIN_DIR/"* "$MODPATH/system/bin/"

ln -sf "$TS_SCRIPTS_DIR/tailscaled.service" "$MODPATH/system/bin/"

ui_print "- Setting permissions"
set_perm_recursive "$TS_BIN_DIR/" 0 0 0755 0755 "u:object_r:system_file:s0"
set_perm_recursive "$TS_SCRIPTS_DIR/" 0 0 0755 0755 "u:object_r:system_file:s0"
set_perm_recursive "$MODPATH/system/bin/" 0 0 0755 0755 "u:object_r:system_file:s0"
set_perm "$MODPATH/service.sh" 0 0 0755 "u:object_r:system_file:s0"

if [ ! -f "$SERVICE_DIR/tailscaled_service.sh" ]; then
	# offer to move module scripts to general scripts
	ui_print "-----------------------------------------------------------"
	ui_print "- Do you want to move Module Scripts to General Scripts ?"
	ui_print "- This option allows you to toggle the 'tailscaled' service"
	ui_print "  on or off by enabling or disabling modules."
	ui_print "- Your service directory is :"
	ui_print "  '$SERVICE_DIR'."
	ui_print "- Because the Developer Guides mentioned :"
	ui_print "  Modules should NOT add general scripts during installation."
	ui_print "- I offer this option to you."
	ui_print "- You have 10 seconds to make a selection. Default is [Yes]."
	ui_print "- [ Vol UP(+): Yes ]"
	ui_print "- [ Vol DOWN(-): No ]"
	timeout 10 sh -c '
  while true; do
    if getevent -lc 1 2>&1 | grep -q KEY_VOLUMEUP; then
      echo "up"
      break
    elif getevent -lc 1 2>&1 | grep -q KEY_VOLUMEDOWN; then
      echo "down"
      break
    fi
  done
' >"$TMPDIR/choice" || true

	choice=$(cat "$TMPDIR/choice" 2>/dev/null)
	if [ "$choice" = "up" ] || [ -z "$choice" ]; then
		ui_print "- [Yes] Move Module Scripts to General Scripts."
		mv -f "$MODPATH/service.sh" "$SERVICE_DIR/tailscaled_service.sh"
	else
		ui_print "- [No] Skip and keep using Module Scripts."
	fi
else
	ui_print "- Move General Scripts."
	mv -f "$MODPATH/service.sh" "$SERVICE_DIR/tailscaled_service.sh"
fi
ui_print "- Starting service in background."
${TS_SCRIPTS_DIR}/start.sh postinstall 2>&1 &
if [ ! -f "/system/bin/tailscale" ] || ! cmp --silent "/system/bin/tailscale" "$MODPATH/system/bin/tailscale"; then
	ui_print "- Link file to /dev/."
	ln -sf "$TS_SCRIPTS_DIR/tailscaled.service" /dev/tailscaled.service
	ln -sf "$TS_BIN_DIR/tailscaled" /dev/tailscaled
	ln -sf "$TS_BIN_DIR/tailscaled" /dev/tailscale
	ui_print "-----------------------------------------------------------"
	ui_print " Instructions       "
	ui_print "-----------------------------------------------------------"
	ui_print "- If you not reboot, execute with /dev/tailscale or /dev/tailscaled.service."
	ui_print "- After reboot, you can use tailscale and tailscaled.service directly."
	if [ ! -f "$TS_DIR/tailscaled.state" ]; then
		ui_print "- Quickstart to new user :"
		ui_print "  su -c '/dev/tailscale login'"
		ui_print "  su -c '/dev/tailscaled.service status'"
		ui_print "- Read the README.md"
	else
		ui_print "- Tailscaled service manager :"
		ui_print "  su -c '/dev/tailscaled.service'"
	fi
else
	if [ ! -f "$TS_DIR/tailscaled.state" ]; then
		ui_print "- Quickstart to login :"
		ui_print "  su -c 'tailscale login'"
		ui_print "  su -c 'tailscaled.service status'"
		ui_print "- Read the README.md"
	else
		ui_print "- Tailscaled service manager :"
		ui_print "  su -c 'tailscaled.service'"
	fi
fi
[ -n "${DEBUG:-}" ] && { set +ue; } || true
