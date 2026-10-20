-- Licensed to the public under the Apache License 2.0.

-- luci.fs was removed when LuCI moved to ucode; nixio.fs is the drop-in
-- replacement. This must not fail: the dispatcher walks every controller to
-- build the menu, so a missing module here takes down every page including
-- the login screen with "Unhandled exception during request dispatching".
local fs = require "nixio.fs"

module("luci.controller.iptv", package.seeall)

function index()
	if not fs.access("/etc/config/iptv") then
		return
	end

	entry({"admin", "network", "iptv"},
		cbi("iptv"),
		_("IPTV Bridge"), 60).dependent = false
end
