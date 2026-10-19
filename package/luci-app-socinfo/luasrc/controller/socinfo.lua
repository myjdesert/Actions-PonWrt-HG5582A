-- Licensed to the public under the Apache License 2.0.

module("luci.controller.socinfo", package.seeall)

function index()
	entry({"admin", "status", "socinfo"},
		template("socinfo/status"),
		_("SoC Status"), 30).dependent = false
end
