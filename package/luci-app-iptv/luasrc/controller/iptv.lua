-- Licensed to the public under the Apache License 2.0.

local fs = require "luci.fs"

module("luci.controller.iptv", package.seeall)

function index()
	if not fs.access("/etc/config/iptv") then
		return
	end

	entry({"admin", "network", "iptv"},
		cbi("iptv"),
		_("IPTV Bridge"), 60).dependent = false
end
