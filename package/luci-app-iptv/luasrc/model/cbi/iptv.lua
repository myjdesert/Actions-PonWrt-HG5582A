-- Licensed to the public under the Apache License 2.0.
--
-- Text is written directly in Chinese on purpose. LuCI's translate() only
-- substitutes when a compiled .lmo is installed, and this app ships without
-- an i18n package, so wrapping the strings in translate() would just leave
-- the page in English forever.

local sys  = require "luci.sys"
local fs   = require "nixio.fs"
local uci  = require "luci.model.uci".cursor()

local m, s, o

m = Map("iptv", "IPTV 桥接",
	"把 PON 上行口的 IPTV 业务 VLAN 与组播 VLAN 桥接到指定 LAN 口。" ..
	"业务 VLAN 剥掉标签输出（路由器在这条上拨 PPPoE），组播 VLAN 保留标签输出。")

m.apply_on_parse = true

m.on_after_commit = function(self)
	-- 重载 network 会短暂中断 uhttpd 的连接，延后执行让浏览器先收到响应
	luci.sys.call("setsid sh -c 'sleep 2; /etc/init.d/iptv reload' >/dev/null 2>&1 &")
end

s = m:section(NamedSection, "config", "iptv", "桥接设置")
s.addremove = false
s.anonymous = false

o = s:option(Flag, "enabled", "启用 IPTV 桥接")
o.default = "1"
o.rmempty = false

o = s:option(Value, "uplink", "PON 上行接口",
	"承载带标签 VLAN 的 PON 接口，通常是 pon0。")
o.default = "pon0"
o.datatype = "ifname"
o.rmempty = false

local ports = {}
for _, p in ipairs({ "lan1", "lan2", "lan3", "lan4" }) do
	if fs.access("/sys/class/net/" .. p) then
		ports[#ports + 1] = p
	end
end
if #ports == 0 then
	ports = { "lan1", "lan2", "lan3", "lan4" }
end

o = s:option(ListValue, "lan_port", "接机顶盒 / 路由器的 LAN 口",
	"该口会从管理网桥 br-lan 中移出，专供 IPTV 使用。")
for _, p in ipairs(ports) do
	local speed = ""
	local f = io.open("/sys/class/net/" .. p .. "/speed", "r")
	if f then
		local v = f:read("*l")
		f:close()
		if v and tonumber(v) and tonumber(v) > 0 then
			speed = "（" .. v .. " Mb/s）"
		end
	end
	o:value(p, p .. speed)
end
o.default = "lan2"
o.rmempty = false

o = s:option(Value, "service_vlan", "业务 VLAN（单播 / PPPoE）",
	"双向单播流量，广东电信为 <b>45</b>。" ..
	"把组播 VLAN 填在这里会导致 PPPoE 拨号失败。")
o.default = "45"
o.datatype = "range(1,4094)"
o.rmempty = false

o = s:option(Value, "multicast_vlan", "组播 VLAN",
	"下行直播流，广东电信为 <b>50</b>。" ..
	"线路只有单个 VLAN 时留空。填入后网桥会开启 VLAN 过滤，" ..
	"该 VLAN 带标签从 LAN 口输出。")
o.default = "50"
o.datatype = "range(1,4094)"

o = s:option(Value, "igmp_vlan", "IGMP VLAN（可选）",
	"只有 IGMP 报文必须走独立 VLAN 时才填。" ..
	"PPPoE 型 IPTV 线路的 IGMP 封装在 PPPoE 会话内，随业务 VLAN 走，此处留空。")
o.datatype = "range(1,4094)"

local function sh(cmd)
	local v = sys.exec(cmd)
	if not v then
		return ""
	end
	return (v:gsub("%s+$", ""))
end

s = m:section(TypedSection, "iptv", "当前状态")
s.anonymous = true
s.addremove = false

o = s:option(DummyValue, "_pon", "PON 状态")
o.rawhtml = true
o.cfgvalue = function()
	local st = sh("ponctl status 2>/dev/null")
	if st == "" then
		return "<em>ponctl 不可用</em>"
	end

	local ready, life, llid, opt = "?", "?", "?", "?"
	for k, v in st:gmatch("([%w_]+):%s*([^\n]+)") do
		if k == "service_ready" then ready = v
		elseif k == "lifecycle" then life = v
		elseif k == "llid" then llid = v
		elseif k == "rx_power_dbm" then opt = v end
	end

	local cls = (ready == "1") and "green" or "red"
	return string.format(
		"业务就绪 service_ready <b class='%s'>%s</b> &nbsp; " ..
		"生命周期 %s &nbsp; LLID %s &nbsp; 收光 %s dBm",
		cls, ready, life, llid, opt)
end

o = s:option(DummyValue, "_vlans", "VLAN 表")
o.rawhtml = true
o.cfgvalue = function()
	local lp = uci:get("iptv", "config", "lan_port") or "lan2"
	local out = sh("bridge vlan show 2>/dev/null | grep -E '" .. lp .. "|ct-iptv'")
	if out == "" then
		return "<em>网桥尚未建立</em>"
	end
	return "<pre style='font-size:12px;line-height:1.35;margin:0'>" ..
		out:gsub("&", "&amp;"):gsub("<", "&lt;") .. "</pre>"
end

o = s:option(DummyValue, "_nft", "网桥过滤")
o.rawhtml = true
o.cfgvalue = function()
	if not fs.access("/etc/iptv.nft") then
		return "<em>未加载</em>"
	end
	local n = sh("nft list table bridge iptv 2>/dev/null | wc -l")
	return string.format("<em>/etc/iptv.nft 已加载（%s 条规则）</em>", n)
end

return m
