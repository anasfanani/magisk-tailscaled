# Existing v2 module updates

An existing `/data/adb/tailscale` installation uses a separate upgrade path.
Install the **full** module ZIP in Magisk/KernelSU Manager. The module ID stays
`magisk-tailscaled`. A lightweight ZIP is rejected before live files change.
It remains available for fresh installs. Legacy layouts are rejected, not migrated.

The installer keeps the existing settings, service scripts, boot hook, keys,
state location and CLI aliases. It stages the payload, checks its packaged SHA256
and executable version, and refuses numeric version downgrades. Packaged hashes
detect corruption; they do not authenticate an untrusted ZIP. Use trusted releases.
An identical core is a no-op: no daemon restart or state write.

Changed cores require a running, logged-in, native-TUN v2 installation, a combined
CLI/daemon and SELinux Enforcing. Installation uses the existing service manager,
with a coherent core/state backup after stopping it. It preserves file labels and
requires the new backend to become Running/online with a DERP home, unchanged
node identity, Tailnet addresses, launch arguments, service context, configuration,
IPv6 TUN address and expected Android policy rules. A platform-specific full ZIP
can also bundle `android-core-check-ARCH` for Android DNS/identity checks.

Failures trigger rollback; a detached 450-second watchdog covers installer process
termination while Android remains running. Backups are private under
`/data/adb/tailscale/backups/upgrade-TIMESTAMP-PID`. The backup contains a standalone
`rollback.sh`: as root, run `sh BACKUP/rollback.sh BACKUP` for manual recovery.
Do not share backup state, private reports or configuration archives publicly.

This is an immediate runtime check, not a reboot or power-loss guarantee. Keep the
backup until after testing reboot. A live but offline phone may fail the strict
network check and restore the old core. Automatic upgrade of an intentionally
stopped daemon, non-root service, split binaries or customized state/socket paths
is refused. Core compilation/release publishing is still maintained separately in
`anasfanani/tailscale-android-cli`; this installer does not add compatibility patches
to a Linux binary. It does not enable an official update notification for a local
custom core. Tailscale SSH must be disabled for this reduced core profile.

The module installer path requires device validation before an upstream release.
Desktop simulations verify control flow only; they do not validate Android,
SELinux, Magisk/KernelSU installation or actual network behavior.
