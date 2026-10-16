#!/bin/bash
#
# PonWrt DIY script part 1 -- runs inside openwrt/ right after
# feeds.conf.default is installed and before `feeds update -a`.
#
# Nothing is required here. The PON line-mode fix lives in diy-part2.sh,
# because it patches a file that only exists once the feeds have been fetched.
#
# Use this script to add feed sources or tweak the tree before feeds update.

set -e

# Add an extra feed source, e.g.
#   echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
#
# Or clone a package in as a local feed, e.g.
#   mkdir -p ../local-feed
#   git clone --depth=1 https://github.com/<owner>/<repo>.git ../local-feed/<name>
#   echo 'src-link local ../../local-feed' >>feeds.conf.default

echo "==> diy-part1.sh done"
