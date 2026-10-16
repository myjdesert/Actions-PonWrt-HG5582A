# PonWrt for FiberHome HG5382A / HG5582A — PON 线路模式切换修复

基于上游源码（[pbs05/ponwrt](https://github.com/pbs05/ponwrt) +
[pbs05/openwrt-pon-userspace](https://github.com/pbs05/openwrt-pon-userspace)）云编译一台
FiberHome HG5382A / HG5582A（Airoha AN7581DT）的固件，并修掉 **PON 线路模式切换不生效** 的问题。

工程骨架沿用 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 模板的写法，
方便你日后自己往 `diy-part*.sh` 里加东西。

---

## 1. 问题现象

- 线路是 **10G-EPON**，设备却钉在 **O1**，永远注册不上。
- `ponctl mode` 显示：

  ```
  configured=epon-10g-1g     <- /etc/config/pon 里配的目标模式
  active=xgpon               <- 驱动实际跑的模式
  ```

- 手动 `ip link set pon0 down/up` 弹一次接口，立刻就切过去了，注册也正常。
- 所以「切换功能不好」的实际含义是：**配了模式不算数，必须重启接口才算数**。

## 2. 根因（源码级）

### 2.1 驱动把模式变更设计成「下次激活生效」

`airoha-xpon/src/airoha-xpon-mode.c` → `airoha_xpon_set_mode_locked()`：

```c
xpon->configured_mode = mode;               /* 先记账 */
if (netif_running(xpon->pon_netdev) ||
    xpon->lifecycle != AIROHA_XPON_STOPPED) {
        dev_info(xpon->dev,
            "PON line mode %s will take effect on the next interface activation\n",
            next->name);
        return 0;                            /* 返回成功，但什么也没做 */
}
```

只要线路已经在跑，新模式只写进 `configured_mode`，**PCS / SerDes 不会重建**，
而返回值仍是成功 —— 调用方完全看不出来没生效。

### 2.2 用户态没有任何人去触发那次「下次激活」

`airoha-ponctl/files/pon.init`（= 设备上的 `/etc/init.d/pon`）只做了两件事：

```sh
/usr/sbin/ponctl --device "$device" mode set "$mode"
/usr/sbin/ponctl --device "$device" identity set --serial ... --registration-id ...
```

**没有 down/up**。

### 2.3 于是那次激活永远不会到来

`pon.init` 的 `START=18`，但 `pon0` 是 platform 设备，netifd 在本脚本运行之前就已经把它
拉起来了。等 `mode set` 执行时线路早已 `running`，于是命中 2.1 的「推迟」分支 ——
开机永远停在驱动默认的 `xgpon`。

LuCI 页面自己都写着：

> Line mode and registration identity take effect after the PON interface restarts.

……但保存配置后**没有任何东西去重启那个接口**。这就是"功能不好"的全部来源。

### 2.4 顺带一提：注册身份（LOID）也是同一套路

`airoha-xpon-control.c` 的 `serial_number_store` / `registration_id_store` 只写
`pending_identity`，同样要等下一次 `ndo_open` 才 latch。所以 LOID 下发后不弹接口也不生效。

## 3. 修复方式

只改一个文件：`feeds/pon_userspace/airoha-ponctl/files/pon.init`
（安装后即 `/etc/init.d/pon`）。

新增判断：**运行中的模式（或尚未落地的身份）与配置不一致时，重新激活一次接口**。

```sh
needs_reactivation() {
        running=$(running_mode "$device")            # ponctl mode -> active=
        [ -z "$running" ] || [ "$running" = none ] && return 1   # 未激活：ndo_open 自会带上
        [ -n "$mode" ] && [ "$running" != "$mode" ] && return 0
        # 串号已改但还没 latch（pending_identity != active_serial_number）
        ...
}
```

| 场景 | 行为 |
|---|---|
| 开机，netifd 已把 pon0 拉起（active=xgpon，配置=epon-10g-1g） | 检测到不一致 → down/up → 切到 EPON |
| 开机，pon.init 抢在 netifd 之前跑（active=none） | 不弹接口（无意义），驱动在随后的 ndo_open 里直接用新配置 |
| LuCI 改模式后保存 | 触发 pon 服务 reload → 检测到不一致 → **立即生效** |
| LuCI 保存但模式没变 | 不弹接口，**避免无谓的链路抖动** |
| 只改了串号 / LOID | 检测到 `pending != active` → 弹一次让身份落地 |

没有改内核驱动：一是 `set_mode_locked` 跑在 netlink 上下文里，在里面做 stop/start 有死锁
风险；二是上游 LuCI 的提示本身就承认「重启接口才生效」，把这一步自动化正是它本来的设计意图。

## 4. 怎么用

### 4.1 推到 GitHub

```bash
cd ponwrt-hg5582a-build
git init -b main
git add .
git commit -m "PonWrt HG5582A build with PON line-mode fix"
git remote add origin git@github.com:<你的用户名>/ponwrt-hg5582a-build.git
git push -u origin main
```

### 4.2 触发编译

仓库页面 → **Actions** → 左侧 **PonWrt Builder (HG5582A)** → **Run workflow**。

- 勾 `ssh` 可在编译进入某一步后开一个 upterm 会话进去排查（可选）。
- 首次编译约 2–3 小时；`dl` 目录有缓存，后续会快一些。

### 4.3 下载产物

run 页面底部 **Artifacts** → `ponwrt-hg5582a-<序号>`：

- `*fiberhome_hg5382a*squashfs-sysupgrade.itb` —— 刷机用固件
- `*hg5382a*.manifest` / `*.sha256` —— 包清单与校验值
- `airoha-ponctl*` —— 单独重编的 PON 控制包（可选，用于包级更新）

### 4.4 刷机

LuCI → 系统 → 备份/刷写固件 → 选择 `sysupgrade.itb`。

- **勾「保留配置」**：`/etc/config/pon` 里的 `mode='epon-10g-1g'` 保留，开机自动切好。
- **不保留配置**：开机是驱动默认的 `xgpon`，进 LuCI 的 PON 页面把模式选成
  `epon-10g-1g` 保存即可 —— 现在它会**立即生效**，不用再重启。

## 5. 刷完之后怎么验证

```sh
# 模式应当一致了（判断修复是否生效的唯一判据）
ponctl --device pon0 mode
#   configured=epon-10g-1g
#   active=epon-10g-1g        <- 与上一行一致即成功

cat /sys/kernel/debug/airoha-xpon-pon0/line
#   lifecycle: operational
#   mpcp_state: registered
#   service_ready: 1

dmesg | grep -iE 'pon|epon' | tail -20
#   EPON PCS synchronized
#   EPON LLID0 registered: LLID=0x0030
```

如果 `active` 仍是 `xgpon`，说明补丁没进固件。回看编译日志里这一行：

```
==> Patching feeds/pon_userspace/airoha-ponctl/files/pon.init
```

## 6. 本地自查

不需要编译环境，也能验证改动本身：

```bash
# 判定逻辑的 10 个用例（含开机、LuCI 改模式、稳态不抖动、身份变更等）
sh tests/check-pon-init.sh

# 补丁能否干净地应用到上游原版
patch -p1 --dry-run -d feeds/pon_userspace < fix/0001-pon-init-apply-stored-mode-immediately.patch
```

## 7. 文件说明

```
.
├── .github/workflows/ponwrt-builder.yml              # 云编译工作流（15 步）
├── feeds.conf.default                                # feed 列表（含必需的 pon_drivers / pon_userspace）
├── diy-part1.sh                                      # feeds update 之前（占位，可加第三方 feed）
├── diy-part2.sh                                      # ★ feeds 安装之后：打补丁 + 锁定设备 profile
├── configs/hg5582a.config                            # 叠加在上游配置之上的 Kconfig 片段
├── fix/
│   ├── 0001-pon-init-apply-stored-mode-immediately.patch   # 改动本身
│   └── pon.init                                            # 修复后的完整文件
├── tests/check-pon-init.sh                           # 判定逻辑单元测试
└── README.md
```

- `diy-part2.sh` 优先用 patch（能感知上游漂移），打不上时自动回退为整文件替换，
  两种情况都会 `grep` + `sh -n` 断言，**打不上就中止构建**，不会悄悄出一个没修的固件。
- `configs/hg5582a.config` 在 `scripts/kconfig.pl` 合并官方 `an7581.config` +
  `release.config` 之后追加，用于选定设备 profile 并补齐 LuCI / ttyd。
- `fix/pon.init` 与 patch 内容一致，二选一即可。

## 8. 注意事项

- **HG5582A 的电话口仍然不可用**。设备结构上缺 SPI/ZSI 控制器，原厂 `slic3.ko`
  （vermagic 5.4.55）无法移植到 6.18 内核，与本修复无关。
- 本工程**不包含引导**（preloader / FIP）。设备已有 pbs05 系引导，直接刷 `sysupgrade.itb`；
  **不要混用官方 Loong1996 那套引导**（哈希不同源）。
- 编译目标是 `pbs05/ponwrt` 的 `master` 分支。上游若更新了 `pon.init`，patch 会失败并回退为
  整文件替换，日志里会有一条 `::warning::`。
- IPTV 的 VLAN 值（默认 `45`）**没有**改 —— 那个值按地区线路而定（本机实测是 `50`），
  写死在固件里会坑到别的线路。刷完在 LuCI 的 IPTV 页面按当地实际值填。
