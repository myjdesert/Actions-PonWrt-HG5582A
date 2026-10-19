#
# Refuse PON line modes that hang the boot sequence.
#
# Observed on Nokia XG-040G-MF (AN7583DT) and FiberHome HG5582A (AN7581):
# selecting `epon-1g` makes the EN7572 driver block during probe. /etc/rc.d
# runs S18pon before S20network, so the block prevents airoha_eth from probing,
# the DSA switch never registers and the box ends up with link-up on every LAN
# port but no IP, no DHCP and no SSH. Recovering from that needs the U-Boot
# recovery page and a rootfs_data wipe.
#
# This guard runs at S17, before pon.init, and rewrites a stored `epon-1g`
# back to `epon-10g-1g`. Mode changes made at runtime are not covered (the
# guard only runs at boot), but LuCI and ponctl both store the mode and reboot
# for it to take effect, so the guard sees it first.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=pon-guard
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=myjdesert

include $(INCLUDE_DIR)/package.mk

define Package/pon-guard
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Guard against PON line modes that hang the boot
	DEPENDS:=+airoha-ponctl
	PKGARCH:=all
endef

define Package/pon-guard/description
	Rewrites a stored epon-1g line mode back to epon-10g-1g before the PON
	driver starts, because epon-1g blocks probe on AN758x and leaves the
	device without networking.
endef

define Build/Compile
endef

define Package/pon-guard/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/pon-guard.init $(1)/etc/init.d/pon-guard
endef

$(eval $(call BuildPackage,pon-guard))
