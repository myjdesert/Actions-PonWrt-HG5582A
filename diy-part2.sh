#!/bin/bash
#
# PonWrt DIY script part 2 -- runs inside openwrt/ after the feeds are
# installed and after .config has been derived from the upstream configs.
#
# Two jobs:
#   1. inject the PON line-mode fix into the pon_userspace feed
#   2. pin the build to the FiberHome HG5382A / HG5582A profile
#
# Fix target: feeds/pon_userspace/airoha-ponctl/files/pon.init
#             -> installed as /etc/init.d/pon
#
# Background: airoha_xpon_set_mode_locked() stores a new line mode in
# configured_mode and only rebuilds the PCS/SerDes during the next ndo_open,
# while still returning success. netifd brings pon0 up before /etc/init.d/pon
# runs, so that "next activation" never arrives: the ONU keeps running the
# driver default (xgpon) and never registers on an EPON line. The patched
# script bounces the netdev whenever the running mode lags behind the
# configuration, which also makes the LuCI page apply immediately.

set -e

WORKSPACE=$(cd "$(dirname "$0")" && pwd)
FEED=feeds/pon_userspace
TARGET="$FEED/airoha-ponctl/files/pon.init"
PATCH="$WORKSPACE/fix/0001-pon-init-apply-stored-mode-immediately.patch"
FIXED="$WORKSPACE/fix/pon.init"

echo "==> Applying the PON line-mode fix"
[ -d "$FEED" ] || { echo "ERROR: feed $FEED is missing"; exit 1; }
[ -f "$TARGET" ] || { echo "ERROR: $TARGET is missing"; exit 1; }

if patch -p1 --dry-run -d "$FEED" <"$PATCH" >/dev/null 2>&1; then
	patch -p1 -d "$FEED" <"$PATCH"
	echo "    patched $TARGET"
else
	echo "::warning::upstream pon.init changed, falling back to full replacement"
	install -m 0755 "$FIXED" "$TARGET"
fi

# Fail loudly rather than shipping a silently unpatched image.
grep -q 'needs_reactivation' "$TARGET" || { echo "ERROR: patch did not land"; exit 1; }
sh -n "$TARGET" || { echo "ERROR: pon.init has a syntax error"; exit 1; }

echo "==> Pinning the build to the FiberHome HG5382A / HG5582A profile"
[ -f .config ] || { echo "ERROR: .config is missing"; exit 1; }
sed -i '/^# CONFIG_TARGET_airoha_an7581_DEVICE_fiberhome_hg5382a is not set$/d' .config
cat "$WORKSPACE/configs/hg5582a.config" >>.config
sed -i -E \
	'/^CONFIG_TARGET_airoha_an7581_DEVICE_(fiberhome_hg5382a)=y/!s/^CONFIG_TARGET_airoha_an7581_DEVICE_/# CONFIG_TARGET_airoha_an7581_DEVICE_/' \
	.config

echo "==> diy-part2.sh done"
