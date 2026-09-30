# 🌐 Droidspaces LAN IP

Give a Droidspaces NAT container its own IPv4 address on the phone's Wi-Fi LAN. Other devices on that LAN can use the address to reach services in the container. The phone keeps its own IP address and Wi-Fi MAC; the container does not get a separate MAC or a public IP.

## 📦 Install and assign an address

You need Droidspaces with a container in **NAT mode**, a phone connected to Wi-Fi, and a root manager with module WebUI support: **KernelSU, APatch, ReSukiSU, or KernelSU Next**. This module targets the Droidspaces 6.6.0 network layout. Keep the Droidspaces module enabled.

1. Choose an unused IPv4 address on the **same Wi-Fi subnet as the phone**. Reserve it or exclude it from your router's DHCP pool. Each container needs a different address. The module rejects duplicate saved assignments, but it cannot detect every address already used by another LAN device.
2. On the phone, download the GitHub Actions-built module ZIP from [GitHub Releases](https://github.com/yashoswalyo/droidspaces-lan-ip/releases). Download the `.zip` attached to a release, not the source-code archive.
3. Open your KernelSU, APatch, ReSukiSU, or KernelSU Next app, install the ZIP from its **Modules** screen, and reboot.
4. In the same app, open the **Droidspaces LAN IP** module WebUI. Find the NAT container, enter the chosen address, and tap **Assign IP**. Host-mode containers are not listed. You can save an assignment while a container is stopped; it applies when Droidspaces and the container are running.
5. From another device on the LAN, ping the assigned address. Then connect to a service running inside the container using that address and the service's listening port. A successful ping does not mean an application is listening.

The WebUI shows the phone's current Wi-Fi address, the Droidspaces daemon status, and each NAT container's state. An **assignment** is the address saved for a container and the phone's Wi-Fi address/prefix when you saved it. A **mapping** is the live network setup that makes that address reachable.

| State          | Meaning                                                                                                                                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Unassigned** | No address is saved for this container.                                                                                                                                                                                   |
| **Stopped**    | An address is saved, but the container is not running.                                                                                                                                                                    |
| **Other LAN**  | The phone's Wi-Fi address or prefix differs from the value saved with the assignment. This can happen even on the same subnet. The module removes the live mapping until you assign an address on the current connection. |
| **Pending**    | An address is saved, but the live mapping is not complete yet. Check the daemon status and worker log if it persists.                                                                                                     |
| **Active**     | The container address, routes, proxy ARP entry, and LAN policy rule are present.                                                                                                                                          |

## 🔄 Change or remove an address

To change a container's address, edit its field in the WebUI and tap **Update IP**. The module replaces the saved assignment and removes the old mapping.

To remove an assignment, tap **Remove** followed by its address on that container's card. The module removes the saved assignment and its live network setup. The container stays in NAT mode. If the container has changed modes or no longer exists, its assignment appears under **Saved for other modes**, where you can still remove it.

To remove all assignments, remove them one at a time or uninstall the module in your root manager. Uninstall cleans up saved mappings and deletes the module's data. Reboot after uninstall to stop its boot worker. If you only disable the module, reboot for that change to take effect; live mappings may remain until then.

## ⚙️ How it works

The module leaves the container in NAT mode. It adds the assigned `/32` address inside the container, a route back to the Wi-Fi subnet, a host route through the existing `ds-br0` NAT link, and a proxy ARP entry on `wlan0`. It also adds a policy rule so Android can route traffic to LAN peers through its main table. The phone answers ARP with its own Wi-Fi MAC and forwards packets to the container. The module does not start containers or configure applications inside them. See the [networking guide](research/droidspaces-lan-ip-guide.md) for the underlying method.

The default Droidspaces 6.6.0 layout uses `ds-br0`, NAT gateway `172.28.0.1`, and `wlan0` for Wi-Fi. The module expects Droidspaces container configs and its binary under `/data/local/Droidspaces/`.

<details open>
<summary><b>Screenshots</b></summary>

| Module list                               | Module WebUI                        |
| ----------------------------------------- | ----------------------------------- |
| ![module list](research/modules_list.jpg) | ![WebUI](research/module_webui.jpg) |

| Droidspaces panel                                    | LAN verification                     |
| ---------------------------------------------------- | ------------------------------------ |
| ![Droidspaces panel](research/droidspaces_panel.jpg) | ![ping results](research/termux.jpg) |

</details>


## 🛠️ Troubleshooting

| Symptom                                             | What to check                                                                                                                                                                                                                                                                                   |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No NAT container appears                            | Set the container to NAT mode in Droidspaces. Host-mode containers are not listed.                                                                                                                                                                                                              |
| Assignment stays **Stopped**                        | Start the container. A saved assignment can wait for it to start.                                                                                                                                                                                                                               |
| Assignment shows **Other LAN**                      | The phone's current Wi-Fi address or prefix changed. Enter an unused address on the current Wi-Fi subnet and tap **Update IP**.                                                                                                                                                                 |
| Assignment stays **Pending**                        | Confirm Droidspaces is enabled and its daemon and the container are running. Check the **Worker log** below the container cards for sync errors.                                                                                                                                                |
| Ping fails from another LAN device                  | Check that the address is unused and reserved outside DHCP. Some Wi-Fi networks isolate wireless clients and block device-to-device traffic. Use the root-shell checks below to inspect the mapping.                                                                                            |
| Ping works but the application does not connect     | Check that the application is running inside the container and listening on the expected port and address.                                                                                                                                                                                      |
| An old address returns after removal                | Disable any separate LAN IP watcher or startup script that assigned it. A script in `/data/adb/service.d` can recreate an address after this module removes it. Rename or disable that script, then reboot or stop the watcher's process. Stop the watcher, not the container.                  |
| **Other proxy addresses on this container** appears | An older manual setup or script may have left another address. After stopping that setup, tap **Remove extra IP** for the listed address. The WebUI offers this only when the address, host route, and proxy entry point to that container; it then reapplies the saved assignment if possible. |

The WebUI displays the latest 200 lines of the worker log and refreshes them every five seconds. The worker waits for the Droidspaces daemon and checks assignments every 15 seconds, including after a container restart.

## 🔍 Check a mapping from a root shell

Set `NAME` and `LAN_IP` to the container name and its assigned address on the Android host:

```sh
NAME=your-container
LAN_IP=your-assigned-ip
PID=$(/data/local/Droidspaces/bin/droidspaces --name="$NAME" pid)
/system/bin/nsenter -t "$PID" -n -- /system/bin/ip -4 addr show dev eth0
/system/bin/nsenter -t "$PID" -n -- /system/bin/ip -4 route show
/system/bin/ip -4 route show "$LAN_IP/32"
/system/bin/ip neigh show proxy dev wlan0
/system/bin/ip -4 rule show
/system/bin/sh /data/adb/modules/droidspaces-lan-ip/scripts/api.sh list
```

The container should have the assigned `/32` address alongside its `172.28.x.x` NAT address. Its LAN route should use the assigned address as the source. On the phone, the host route should point through `ds-br0` to the container's NAT address; the proxy entry should list the assigned address; and a rule at priority `6091` should direct the Wi-Fi subnet to the main routing table.

Assignments live in `/data/adb/droidspaces-lan-ip/assignments`, separate from the module directory so updates can retain them. Worker messages and sync errors live in `/data/adb/droidspaces-lan-ip/worker.log`.
