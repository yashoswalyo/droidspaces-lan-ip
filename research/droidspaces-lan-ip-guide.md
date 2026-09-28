# Give a Droidspaces container its own Wi-Fi LAN IP

This guide explains the network setup for a Droidspaces NAT container. For persistent assignments, install the KernelSU module described in [README.md](README.md) and use its WebUI. The module reapplies assignments after container starts and phone reboots.

The method adds a `/32` LAN address inside the container, a route on the Android host, and a proxy ARP entry on the Wi-Fi interface. The phone answers ARP with its Wi-Fi MAC and forwards packets to the container. The container gets its own LAN IP, but not its own Wi-Fi MAC or public internet IP. [Droidspaces networking](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Networking-From-Zero.md), [Linux proxy ARP](https://docs.kernel.org/networking/ip-sysctl.html)

## Choose an address

Choose an unused address on the phone's current Wi-Fi subnet. Reserve it or exclude it from your router's DHCP pool. Each container needs a different address. From another Linux machine on the LAN, you can check whether an address currently responds to ARP:

```sh
arping -D -I "$PC_IF" -c 3 "$LAN_IP"
```

Set `PC_IF` to that machine's LAN interface and `LAN_IP` to the chosen address before running the check. An ARP check cannot prevent a later DHCP conflict.

## Inspect a NAT container

In a root shell on the Android host, set `NAME` to the container name and `LAN_IP` to its chosen address. Verify that the container is in NAT mode, then inspect its current PID, NAT address, and gateway:

```sh
droidspaces --name="$NAME" info
PID=$(droidspaces --name="$NAME" pid)
nsenter -t "$PID" -n -- ip -4 addr show dev eth0
nsenter -t "$PID" -n -- ip -4 route show default
cat /proc/sys/net/ipv4/ip_forward
```

The NAT address should be on the Droidspaces bridge, and IPv4 forwarding should print `1`. The module expects the Droidspaces 6.6.0 defaults: bridge `ds-br0`, NAT gateway `172.28.0.1`, and Wi-Fi interface `wlan0`. Its defaults can be overridden with the `DSLI_BRIDGE`, `DSLI_NAT_GATEWAY`, and `DSLI_UPLINK` environment variables in `scripts/lib.sh`.

## Assign and verify

Install the module, open its WebUI in KernelSU Manager, select the NAT container, and assign the reserved LAN address. The WebUI shows whether the address is active, pending, or bound to another Wi-Fi network.

In the Android root shell, check the container address, host route, and proxy ARP entry:

```sh
PID=$(droidspaces --name="$NAME" pid)
nsenter -t "$PID" -n -- ip -4 addr show dev eth0
ip -4 route show "$LAN_IP/32"
ip neigh show proxy dev wlan0
```

The container should have `LAN_IP/32` alongside its NAT address. The host route should point through `ds-br0` to that NAT address, and the proxy entry should list `LAN_IP`. From another device on the LAN, ping the assigned address and connect to a service that is listening inside the container. A successful ping confirms routing, not that an application is running.

## Remove an address

Use **Remove IP** in the WebUI. It deletes the saved assignment and removes the container address, routes, and proxy ARP entry. The container remains in NAT mode. Uninstalling the module removes all saved assignments and their network mappings.
