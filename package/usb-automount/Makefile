#
# Mount USB block devices on hotplug.
#
# Deliberately not using the tree's `automount` package: it depends on
# kmod-fs-ntfs (the legacy read-only NTFS driver), which is not built for
# 6.18 kernels. This script only needs blkid plus the filesystem modules that
# mf-extra.config already selects (ext4, exfat, vfat, ntfs3, f2fs).
#
# A plugged stick appears as /mnt/<devname> immediately, and luci-app-socinfo
# lists it under Storage.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=usb-automount
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=myjdesert

include $(INCLUDE_DIR)/package.mk

define Package/usb-automount
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Mount USB block devices automatically on hotplug
	DEPENDS:=+block-mount +blkid +kmod-fs-ext4 +kmod-fs-exfat +kmod-fs-vfat \
		+kmod-fs-ntfs3
	PKGARCH:=all
endef

define Package/usb-automount/description
	Hotplug script that mounts a newly attached USB block device under
	/mnt/<device> and unmounts it on removal. Covers ext2/3/4, vfat, exfat,
	ntfs3 and f2fs; no manual fstab entry required.
endef

define Build/Compile
endef

define Package/usb-automount/install
	$(INSTALL_DIR) $(1)/etc/hotplug.d/block
	$(INSTALL_BIN) ./files/10-usb-automount $(1)/etc/hotplug.d/block/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/90-usb-automount $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,usb-automount))
