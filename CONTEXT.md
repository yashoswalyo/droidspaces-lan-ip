# Droidspaces LAN IP

Terms used when describing how a Droidspaces container receives a reachable address on the phone's Wi-Fi LAN.

## Language

**NAT container**:
A Droidspaces container configured in NAT mode, with a private address on the Droidspaces network.

**LAN assignment**:
An IPv4 address saved for one NAT container together with the phone's Wi-Fi address and prefix at the time it was chosen.
_Avoid_: Saved mapping

**LAN mapping**:
The active network state that makes a LAN assignment reachable from the phone's Wi-Fi network.
_Avoid_: Assignment, when referring to live reachability

**Extra proxy address**:
An address routed and proxied to a NAT container outside its saved LAN assignment.
