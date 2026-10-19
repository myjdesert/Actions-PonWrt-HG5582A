-- Licensed to the public under the Apache License 2.0.
--
-- Read-only collector for the SoC status page. Everything comes from sysfs or
-- /proc, so it works on any kernel without extra userspace helpers.

local sys = require "luci.sys"

local M = {}

local function slurp(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local v = f:read("*a")
	f:close()
	if not v then return nil end
	return (v:gsub("%s+$", ""))
end

local function num(v)
	return tonumber(v or "")
end

function M.temps()
	local out = {}
	local i = 0
	while i < 16 do
		local base = "/sys/class/thermal/thermal_zone" .. i
		local name = slurp(base .. "/type")
		local raw  = num(slurp(base .. "/temp"))
		if name and raw then
			out[#out + 1] = {
				name  = name,
				value = raw / 1000,
			}
		end
		i = i + 1
	end

	table.sort(out, function(a, b) return a.value > b.value end)
	return out
end

function M.cpus()
	local out = {}
	local i = 0
	while i < 16 do
		local base = "/sys/devices/system/cpu/cpu" .. i .. "/cpufreq"
		local cur  = num(slurp(base .. "/scaling_cur_freq"))
		if cur then
			out[#out + 1] = {
				id  = i,
				cur = cur / 1000,                       -- MHz
				max = (num(slurp(base .. "/scaling_max_freq")) or 0) / 1000,
				min = (num(slurp(base .. "/scaling_min_freq")) or 0) / 1000,
			}
		end
		i = i + 1
	end
	return out
end

function M.governor()
	return slurp("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") or "?"
end

function M.governors()
	local v = slurp("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors") or ""
	local out = {}
	for g in v:gmatch("%S+") do out[#out + 1] = g end
	return out
end

function M.load()
	local v = slurp("/proc/loadavg") or ""
	local a, b, c = v:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
	return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

function M.memory()
	local v = slurp("/proc/meminfo") or ""
	local total = num(v:match("MemTotal:%s*(%d+)")) or 0
	local avail = num(v:match("MemAvailable:%s*(%d+)"))
		or num(v:match("MemFree:%s*(%d+)")) or 0
	local used  = math.max(total - avail, 0)
	return {
		total_kb = total,
		avail_kb = avail,
		used_kb  = used,
		pct      = total > 0 and (used * 100 / total) or 0,
	}
end

function M.uptime()
	local v = slurp("/proc/uptime") or ""
	return tonumber(v:match("([%d%.]+)")) or 0
end

local function cpu_stat()
	local v = slurp("/proc/stat") or ""
	local line = v:match("cpu%s+([^\n]+)")
	if not line then return nil end
	local total, idle = 0, 0
	local n = 0
	for field in line:gmatch("%d+") do
		n = n + 1
		local x = tonumber(field)
		total = total + x
		if n == 4 or n == 5 then idle = idle + x end
	end
	return total, idle
end

-- Two samples of /proc/stat 300 ms apart. Blocks the render, but 300 ms is
-- below the point where LuCI feels slow and avoids needing a background job.
function M.cpu_usage()
	local t1, i1 = cpu_stat()
	if not t1 then return nil end
	sys.exec("sleep 0.3")
	local t2, i2 = cpu_stat()
	if not t2 or t2 <= t1 then return nil end
	return (1 - (i2 - i1) / (t2 - t1)) * 100
end

function M.storage()
	local out = {}
	local f = io.open("/proc/mounts", "r")
	if not f then return out end
	for line in f:lines() do
		local dev, mount, fstype = line:match("^(%S+)%s+(%S+)%s+(%S+)")
		if dev and mount then
			local interesting = false
			if dev:match("^/dev/sd") or dev:match("^/dev/mmcblk")
				or dev:match("^/dev/nvme") then
				interesting = true
			end
			if fstype == "overlay" or mount == "/" or mount:match("^/mnt/") then
				interesting = true
			end
			if interesting then
				out[#out + 1] = {
					dev    = dev,
					mount  = mount,
					fstype = fstype,
				}
			end
		end
	end
	f:close()
	return out
end

-- df gives the size/usage numbers that /proc/mounts lacks.
function M.df()
	local out = {}
	local raw = sys.exec("df -k 2>/dev/null")
	if not raw or raw == "" then return out end
	for line in raw:gmatch("[^\n]+") do
		local fs, total, used, avail, mount =
			line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+)$")
		if fs and fs ~= "Filesystem" then
			out[mount] = {
				total_kb = tonumber(total),
				used_kb  = tonumber(used),
				avail_kb = tonumber(avail),
			}
		end
	end
	return out
end

function M.collect()
	return {
		temps     = M.temps(),
		cpus      = M.cpus(),
		governor  = M.governor(),
		governors = M.governors(),
		load      = M.load(),
		memory    = M.memory(),
		uptime    = M.uptime(),
		usage     = M.cpu_usage(),
		storage   = M.storage(),
		df        = M.df(),
	}
end

function M.human_kb(kb)
	kb = tonumber(kb) or 0
	if kb >= 1024 * 1024 then
		return string.format("%.1f GB", kb / 1024 / 1024)
	elseif kb >= 1024 then
		return string.format("%.0f MB", kb / 1024)
	end
	return string.format("%d KB", kb)
end

function M.human_uptime(sec)
	sec = math.floor(tonumber(sec) or 0)
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	if d > 0 then
		return string.format("%dd %dh %dm", d, h, m)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

return M
