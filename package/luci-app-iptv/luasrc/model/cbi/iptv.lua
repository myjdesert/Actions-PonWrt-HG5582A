-- Licensed to the public under the Apache License 2.0.

local sys  = require "luci.sys"
local fs   = require "luci.fs"
local uci  = require "luci.model.uci".cursor()

local m, s, o

m = Map("iptv", translate("IPTV Bridge"),
	translate("Bridge the IPTV service and multicast VLANs from the PON uplink " ..
		"to one LAN port. The service VLAN is delivered untagged (this is where " ..
		"the router dials PPPoE), the multicast VLAN stays tagged."))

m.apply_on_parse = true

m.on_after_commit = function(self)
	-- network reload drops uhttpd's connection for a moment; delay it so the
	-- browser gets the "changes applied" response first.
	luci.sys.call("setsid sh -c 'sleep 2; /etc/init.d/iptv reload' >/dev/null 2>&1 &")
end

s = m:section(NamedSection, "config", "iptv", translate("Bridge settings"))
s.addremove = false
s.anonymous = false

o = s:option(Flag, "enabled", translate("Enable IPTV bridge"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "uplink", translate("PON uplink device"),
	translate("The PON netdev that carries the tagged VLANs, normally pon0."))
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

o = s:option(ListValue, "lan_port", translate("LAN port to the set-top box / router"),
	translate("This port is taken out of the management bridge (br-lan) and " ..
		"dedicated to IPTV."))
for _, p in ipairs(ports) do
	local speed = ""
	local f = io.open("/sys/class/net/" .. p .. "/speed", "r")
	if f then
		local v = f:read("*l")
		f:close()
		if v and tonumber(v) and tonumber(v) > 0 then
			speed = " (" .. v .. " Mb/s)"
		end
	end
	o:value(p, p .. speed)
end
o.default = "lan2"
o.rmempty = false

o = s:option(Value, "service_vlan", translate("Service VLAN (unicast / PPPoE)"),
	translate("Two-way unicast traffic. Guangdong Telecom uses <b>45</b>. " ..
		"Putting the multicast VLAN here is what breaks PPPoE dial-up."))
o.default = "45"
o.datatype = "range(1,4094)"
o.rmempty = false

o = s:option(Value, "multicast_vlan", translate("Multicast VLAN"),
	translate("Downstream live TV. Guangdong Telecom uses <b>50</b>. " ..
		"Leave empty if the line carries a single VLAN. When set, the bridge " ..
		"switches to VLAN filtering and this VLAN leaves the LAN port tagged."))
o.default = "50"
o.datatype = "range(1,4094)"

o = s:option(Value, "igmp_vlan", translate("IGMP VLAN (optional)"),
	translate("Only set this if IGMP reports must travel on a VLAN of their own. " ..
		"On a PPPoE-based IPTV line IGMP is tunnelled inside the PPPoE session, " ..
		"so it follows the service VLAN and this field stays empty."))
o.datatype = "range(1,4094)"

local function sh(cmd)
	local v = sys.exec(cmd)
	if not v then
		return ""
	end
	return (v:gsub("%s+$", ""))
end

s = m:section(TypedSection, "iptv", translate("Current state"))
s.anonymous = true
s.addremove = false

o = s:option(DummyValue, "_pon", translate("PON"))
o.rawhtml = true
o.cfgvalue = function()
	local st = sh("ponctl status 2>/dev/null")
	if st == "" then
		return "ponctl not available"
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
		"service_ready <b class='%s'>%s</b> &nbsp; lifecycle %s &nbsp; " ..
		"LLID %s &nbsp; Rx %s dBm",
		cls, ready, life, llid, opt)
end

o = s:option(DummyValue, "_vlans", translate("VLAN table"))
o.rawhtml = true
o.cfgvalue = function()
	local lp = uci:get("iptv", "config", "lan_port") or "lan2"
	local out = sh("bridge vlan show 2>/dev/null | grep -E '" .. lp .. "|ct-iptv'")
	if out == "" then
		return "<em>bridge not up yet</em>"
	end
	return "<pre style='font-size:12px;line-height:1.35;margin:0'>" ..
		out:gsub("&", "&amp;"):gsub("<", "&lt;") .. "</pre>"
end

o = s:option(DummyValue, "_nft", translate("Bridge filter"))
o.rawhtml = true
o.cfgvalue = function()
	if not fs.access("/etc/iptv.nft") then
		return "<em>none</em>"
	end
	local n = sh("nft list table bridge iptv 2>/dev/null | wc -l")
	return string.format("<em>/etc/iptv.nft loaded (%s lines)</em>", n)
end

return m
