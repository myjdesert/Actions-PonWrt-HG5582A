#
# LuCI app: IPTV bridge for PonWrt ONUs (Airoha AN758x)
#
# Modelled on the LuCI IPTV page shipped with vendor PonWrt builds, but with
# two deliberate improvements over that version:
#
#   1. The service (unicast/PPPoE) VLAN and the multicast VLAN are separate
#      options, and both are honoured. The vendor page only exposes one VLAN,
#      which is why pointing it at the multicast VLAN makes PPPoE dial fail:
#      the untagged PADI from the router leaves through a VLAN 50 subinterface
#      and lands in the multicast VLAN, where no BRAS answers.
#
#   2. When both VLANs are configured the bridge is switched to
#      vlan_filtering=1 and given an explicit table, so the LAN port carries
#      the service VLAN untagged and the multicast VLAN tagged. A plain
#      transparent bridge strips both tags and the router can no longer tell
#      the two apart.
#
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI IPTV bridge (service + multicast VLAN)
LUCI_DESCRIPTION:=Configure an IPTV bridge on a PON uplink: unicast/PPPoE service \
	VLAN untagged on the LAN port, multicast VLAN tagged, with a bridge-level \
	nftables allow-list.
LUCI_DEPENDS:=+luci-compat
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-iptv
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=myjdesert

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
