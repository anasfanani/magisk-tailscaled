[![anasfanani - Magisk-Tailscaled](https://img.shields.io/static/v1?label=anasfanani&message=Magisk-Tailscaled&color=blue&logo=github)](https://github.com/anasfanani/Magisk-Tailscaled "Go to GitHub repo")
[![Check and Update Tailscale Binary](https://github.com/anasfanani/Magisk-Tailscaled/actions/workflows/update.yml/badge.svg)](https://github.com/anasfanani/Magisk-Tailscaled/actions/workflows/update.yml)
[![Github All Releases](https://img.shields.io/github/downloads/anasfanani/Magisk-Tailscaled/total.svg)]()
[![GitHub release](https://img.shields.io/github/release/anasfanani/Magisk-Tailscaled?include_prereleases=&sort=semver&color=blue)](https://github.com/anasfanani/Magisk-Tailscaled/releases/)
[![issues - Magisk-Tailscaled](https://img.shields.io/github/issues/anasfanani/Magisk-Tailscaled)](https://github.com/anasfanani/Magisk-Tailscaled/issues)
[![Static Badge](https://img.shields.io/badge/Discussion-Telegram-blue?style=flat&logo=telegram&link=t.me%2Fsystembinsh%2F158)](https://t.me/systembinsh/158)

# Magisk Tailscaled

This repository contains a Magisk module for running Tailscale on rooted Android devices.

## What is Tailscale?

Tailscale is a networking tool that allows you to connect each of your devices as if they were on the same VPN. For example, an Android phone connected to the Tailscale network can communicate with any other device connected to Tailscale. You can install it on your PC and Android device and then connect them using the Tailscale IP. For more information, check out [How Tailscale Works](https://tailscale.com/blog/how-tailscale-works).

## Difference between this Magisk module and the Tailscale app on Play Store

The [Tailscale app](https://play.google.com/store/apps/details?id=com.tailscale.ipn) on the Play Store runs with Android's VPN, which means you can't use Tailscale while another VPN is active. This Magisk module, on the other hand, allows you to use both an Android VPN and Tailscale at the same time.

## Requirements

- A basic networking knowledge.
- An Android device with Magisk root installed.

## Quick Start & Installation

1. Download the latest zip file from the [Releases](https://github.com/anasfanani/Magisk-Tailscaled/releases/latest) page.
2. Install the downloaded zip file using Magisk & reboot your phone.
3. Open the Terminal.
4. Login with `su -c tailscale login`
5. Disable accept-dns `su -c tailscale set --accept-dns=false`
6. Run 'tailscale login' to login to your Tailscale account.
7. Open the URL in a browser to authorize your device.
8. Run 'tailscale ip' to retrieve your Tailscale IP.
9. Alternatively, you can open the [Tailscale Admin Dashboard](https://login.tailscale.com/admin/machines) to manage your devices.

After installation, the Tailscale daemon (`tailscaled`) will run automatically on boot.

## Limitation

- This module only support for `arm` or `arm64` architecture, you can download manually for other architecture.
- Tailscale binary is designed to run in Linux environment, Some feature might not works properly.
- MagicDNS currently not working.
- Runs in userspace mode, read more at [https://tailscale.com/kb/1112/userspace-networking](https://tailscale.com/kb/1112/userspace-networking) 
- Subnet routes is manually routed with socks5-tun, you must define your own ip routes to `tailscaled.tun.up` and `tailscaled.tun.down`

## Usage of this module

This module runs `tailscaled` with the following command:

```bash
tailscaled -tun=userspace-networking -statedir=/data/adb/tailscale/tmp/ -state=/data/adb/tailscale/tmp/tailscaled.state -socket=/data/adb/tailscale/tmp/tailscaled.sock -port=41641
```
The state file for tailscaled is stored at `/data/adb/tailscale/tmp/tailscaled.state`, and the log output is written to `/data/adb/tailscale/run/tailscaled.log`.

## Available command

- `tailscale`: This command is execute tailscale operation.
- `tailscaled`: This command is execute tailscaled daemon operation.
- `tailscaled.service`: This command for manage tailscaled service, you can start,stop,restart daemon and view live logs the tailscaled operation.
- `tailscaled.tun`: This command is for manage hev-socks5-tunnel.
  
## Example of Using Tailscale

### SSH to Termux

You can use Tailscale to connect SSH from Termux on Android to a Windows PC. Here's how:

#### On your Android device:

1. Set up SSHD:

```bash
apt update && apt upgrade
apt install openssh
passwd
```

Enter your password when prompted, for example, `123`.

2. Run ssh daemon with command `sshd`
3. Get your IP with the command `tailscale ip` or check your IP in the [Tailscale Admin Dashboard](https://login.tailscale.com/admin/machines).

#### On your Windows PC:

1. Download & install [Tailscale for Windows](https://tailscale.com/download/windows)
1. Open app & login to the Tailscale.
3. Open the terminal & SSH to your Android IP:

```bash
ssh <root>@<tailscale_ip> -p 8022
```

For example:

```bash
ssh root@100.95.95.95 -p 8022
```

### SSH access to your Android device

You can also enable SSH access to your Android device using [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh?slug=kb&slug=1193&slug=tailscale-ssh). To do this, advertise SSH on the host with the command `tailscale up --ssh`.

By default, Tailscale's SSH feature may not work on Android because it requires `getent`, which is part of GNU libc, and relies on glibc-specific features like nsswitch.conf.

To overcome this, I've created a mock `getent` and placed it in `tailscale/bin/`. This mock `getent` is used by Tailscale's [userLookupGetent](https://github.com/tailscale/tailscale/blob/5812093d31c8a7f9c5e3a455f0fd20dcc011d8cd/util/osuser/user.go#L121C19-L121C33) function.

After advertising SSH on the host, you can SSH into your Android device using `ssh root@<tailscale_ip>`.

### ADB over Tailscale

You can run ADB over Tailscale. First, you need to enable ADB over TCP/IP. You can do this with the following commands:

```bash
setprop service.adb.tcp.port 5555
stop adbd
start adbd
```

These commands set the ADB daemon to listen on TCP port 5555 and then restart the ADB daemon to apply the change.

After enabling ADB over TCP/IP, you can connect to your Android device from your Windows machine using the `adb connect` command followed by your Tailscale IP and the port number:

```bash
adb connect <tailscale_ip>:5555
```

## Avalilable command

```
USAGE
  tailscale [flags] <subcommand> [command flags]

For help on subcommands, add --help after: "tailscale status --help".

This CLI is still under active development. Commands and flags will
change in the future.

SUBCOMMANDS
  up         Connect to Tailscale, logging in if needed
  down       Disconnect from Tailscale
  set        Change specified preferences
  login      Log in to a Tailscale account
  logout     Disconnect from Tailscale and expire current node key
  switch     Switches to a different Tailscale account
  configure  [ALPHA] Configure the host to enable more Tailscale features
  netcheck   Print an analysis of local network conditions
  ip         Show Tailscale IP addresses
  status     Show state of tailscaled and its connections
  ping       Ping a host at the Tailscale layer, see how it routed
  nc         Connect to a port on a host, connected to stdin/stdout
  ssh        SSH to a Tailscale machine
  funnel     Turn on/off Funnel service
  serve      Serve content and local servers
  version    Print Tailscale version
  web        Run a web server for controlling Tailscale
  file       Send or receive files
  bugreport  Print a shareable identifier to help diagnose issues
  cert       Get TLS certs
  lock       Manage tailnet lock
  licenses   Get open source license information
  exit-node

FLAGS
  --socket string
        path to tailscaled socket (default /var/run/tailscale/tailscaled.sock)
```

For more details about CLI commands, check out the [Tailscale CLI documentation](https://tailscale.com/kb/1080/cli#using-the-cli).

## FAQ & Troubleshooting

Tailscale has manny issues. You can check them out [here](https://github.com/tailscale/tailscale/issues).

### Cannot access other tailnet devices

This module runs the `tailscaled` binary in userspace-networking mode. To access other devices in the tailnet, you must use a local proxy on port 1099. I've implemented a workaround using `hev-socks5-tunnel` to tunnel local socks5 on port 1099 and bind it to the interface named `tailscale0`. 

Please note, this `tailscale0` interface is different from the original `tailscale0` interface on Linux. In Linux, `tailscale0` is managed by the `tailscaled` daemon, whereas in this module, `tailscale0` is managed by `hev-socks5-tunnel`. The default gateway is `100.100.100.100`, as defined in the `tailscaled.tun.config.yaml` file.

This solution should work on most common devices. However, if you encounter problems accessing other tailnet devices, follow these troubleshooting steps:

1. Verify that `tailscaled.service` is running. If not, restart it with `tailscaled.service restart`.
2. Verify that `tailscaled.tun` is running. If not, restart it with `tailscaled.tun restart`.
3. Check if your device is connected to tailscaled and try a ping connection with `tailscale ping <your_tailnet_ip>`.
4. Verify the port you want to access is accessible. You can do this by accessing it with another tailscale device or using the Tailscale Android App.
5. Check if the local socks5 server is working with curl. Execute the following command:
    ```
    curl 1.1.1.1 -vI -x localhost:1099
    ```
    If it connects, then the local socks5 server is running and working.

6. Check if the local socks5 server can connect to the tailnet network.
    ```
    curl <your_tailnet_ip>:<port> -vI -x localhost:1099
    ```
    If it connects, then the local socks5 server is functioning correctly.

7. Finally, check the connection directly with `curl <your_tailnet_ip>:<port> -vI`.

If the last step fails, the problem likely lies with `socks5-tun`. Verify there is an interface named `tailscale0`. If it exists, the problem may be with the iptables route, either due to a conflict with another rule or some other issue. Feel free to explore your own solutions. If you're unable to resolve the issue, contact me on Telegram and I'll see if I can assist you.

### My subnet-routes is'nt working

Yes because we need define the routes with `iptables` in file `tailscaled.tun.up` and `tailscaled.tun.down`, you can check this [issue reference](https://github.com/anasfanani/Magisk-Tailscaled/issues/17).
I suppose you're already know the iptables works, if dont, there are chatAI to ask.
You can copy whole `tailscaled.tun.up` script to chatAI and send instruction with please add 192.168.1.1/24 to this route, also dont forget `tailscaled.tun.down` 

If you still can't do it by yourself, I'm verry welcome to people who needs help.

### Exit nodes

You can check this [issue reference](https://github.com/anasfanani/Magisk-Tailscaled/issues/17).

### ipv6

Unfortunately, I'm verry lazy to learn ipv6.

### Headscale 

Check [this](https://github.com/anasfanani/Magisk-Tailscaled/issues/19#issuecomment-2091579177).
Also explore on the issue first, then you can ask trough telegram.


### Other Error & Bugs

You can explore to the issue tab, if there not exists, you can open issue, for help me resolve the problem, you can include fresh log.

1. Restart tailscaled with `tailscaled.service restart`
2. Reproduce what are you doing which has problem.
3. Get log at `/data/adb/tailscale/run/tailscaled.log`

## Notes

This module is confirmed to be supported for KernelSU, as [confirmed by the author of KernelSU](https://github.com/anasfanani/Magisk-Tailscaled/issues/2#issue-2055047162). If you encounter any problems, please let me know.

For more information, check out the links below:

## Links

- [Tailscale Userspace Networking](https://tailscale.com/kb/1112/userspace-networking/)
- [Termux Issue #10166](https://github.com/termux/termux-packages/issues/10166)
- [Tailscale Static Packages](https://pkgs.tailscale.com/stable/#static)
- [Tailscale Knowledge Base](https://tailscale.com/kb)

## Credits

- [Tailscale Inc & AUTHORS](https://github.com/tailscale/tailscale). for the static binaries of tailscale & tailscaled
- [John Wu & Authors](https://github.com/topjohnwu/Magisk). for The Magic Mask for Android
- [heiher & Authors](https://github.com/heiher/hev-socks5-tunnel). for the hev-socks5-tunnel

## Disclaimer

This module is provided as-is, I'm not employee at official tailscale, not a verry genius people which can resolve all your problem.
This module is not affiliated with the official Tailscale. It is a third-party implementation and the author is not responsible for any damage to your device that may occur from its use. Use at your own risk.
Any improvements is required, any PR is verry required, not just welcome.

## License

Released under [BSD 3-Clause License](/LICENSE).
### Existing v2 updates

See [safe full-ZIP updates](docs/safe-updates.md) for preserved settings, backup, rollback, supported layouts and validation limits.
