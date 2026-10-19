#
# LuCI app: SoC status for Airoha AN758x ONUs
#
# Reads the thermal zones the airoha TSENS driver exports, per-core cpufreq,
# load, memory and attached storage. Written as a read-only status page so it
# cannot interfere with anything else.
#
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI SoC status (temperature / clock / memory / storage)
LUCI_DESCRIPTION:=Temperature, frequency, governor, load, memory and USB storage \
	overview for Airoha AN758x based ONUs.
LUCI_DEPENDS:=+luci-compat
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-socinfo
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=myjdesert

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
