--[[--
==============================================================================
validate-atoms.lua - check the atoms of a Reactor repository
==============================================================================

Usage:
	lua Tools/validate-atoms.lua [repository folder]

Runs with plain Lua 5.1 to 5.4 (GitHub Actions, a terminal) or with Fusion's
fuscript. It checks every Atoms/<id>/<id>.atom file:

- the file parses as an Atom { ... } table
- Name, Author, Category, Version and Deploy are set (a linked atom stub with a
  Source table only needs Name, Author and Source)
- Deploy paths stay inside the Reactor Deploy folder (no absolute paths, drive
  letters, PathMaps or ".." segments) and every listed file exists
- Date is { year, month, day }

Errors make the script exit with code 1. Install scripts are listed as notes,
because users will be asked to approve them.

--]]--

local root = (arg and arg[1] or "."):gsub("[/\\]+$", "")
local errors, notes, checked = 0, 0, 0

local function errorf(id, fmt, ...)
	errors = errors + 1
	print(("ERROR  %s: " .. fmt):format(id, ...))
end

local function notef(id, fmt, ...)
	notes = notes + 1
	print(("note   %s: " .. fmt):format(id, ...))
end

local function readfile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

-- List folder names without depending on lfs
local function listdirs(path)
	local cmd = package.config:sub(1, 1) == "\\" and ('dir /b /ad "' .. path:gsub("/", "\\") .. '" 2>nul') or ('ls -1 "' .. path .. '" 2>/dev/null')
	local p = io.popen(cmd)
	local out = {}
	for line in p:lines() do
		line = line:gsub("[\r\n]+$", "")
		if line ~= "" then
			out[#out + 1] = line
		end
	end
	p:close()
	table.sort(out)
	return out
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() return true end
	return false
end

-- Evaluate an atom file without giving it access to anything
local function parse(text, name)
	local env = { Atom = function(t) return t end }
	local chunk, err
	if setfenv then
		chunk, err = loadstring("return " .. text, name)
		if chunk then setfenv(chunk, env) end
	else
		chunk, err = load("return " .. text, name, "t", env)
	end
	if not chunk then return nil, err end
	local ok, result = pcall(chunk)
	if not ok then return nil, result end
	return result
end

-- Same rules as IsSafeDeployPath() in Reactor.lua
local function safe(path)
	if type(path) ~= "string" or path == "" then return false end
	local p = path:gsub("\\", "/")
	if p:match("^/") or p:match("^~") or p:find(":") then return false end
	for part in p:gmatch("[^/]+") do
		if part == ".." then return false end
	end
	return true
end

-- Walk a Deploy table the way GetDeployFiles() does: string keys (Windows, Mac, Linux,
-- Fusion, Resolve, v18+, ...) become folder prefixes of the files below them
local function deployfiles(tbl, prefix, out)
	for key, v in pairs(tbl) do
		if type(key) == "string" and type(v) == "table" then
			deployfiles(v, prefix .. key .. "/", out)
		elseif type(key) == "number" then
			out[#out + 1] = { Local = v, Remote = prefix .. tostring(v) }
		end
	end
	return out
end

for _, id in ipairs(listdirs(root .. "/Atoms")) do
	local dir = root .. "/Atoms/" .. id .. "/"
	local text = readfile(dir .. id .. ".atom")

	if not text then
		errorf(id, "missing %s.atom in Atoms/%s/", id, id)
	else
		checked = checked + 1
		local atom, err = parse(text, id .. ".atom")

		if type(atom) ~= "table" then
			errorf(id, "does not parse as an Atom { ... } table: %s", tostring(err))
		else
			local linked = type(atom.Source) == "table"

			for _, field in ipairs(linked and { "Name", "Author" } or { "Name", "Author", "Category", "Version", "Deploy" }) do
				if atom[field] == nil then
					errorf(id, "%s is missing", field)
				end
			end

			if atom.Version ~= nil and type(atom.Version) ~= "number" then
				errorf(id, "Version must be a number, like 1.2")
			end

			if atom.Date ~= nil and not (type(atom.Date) == "table" and tonumber(atom.Date[1]) and tonumber(atom.Date[2]) and tonumber(atom.Date[3])) then
				errorf(id, "Date must be { year, month, day }")
			end

			if linked and not atom.Source.ID then
				errorf(id, "Source needs an ID, like \"owner/repo\"")
			end

			if type(atom.Deploy) == "table" then
				for _, file in ipairs(deployfiles(atom.Deploy, "", {})) do
					if not safe(file.Local) then
						errorf(id, "unsafe Deploy path %q (Reactor will refuse to install it)", tostring(file.Local))
					elseif not linked and not exists(dir .. file.Remote) then
						errorf(id, "Deploy lists %s but Atoms/%s/%s does not exist", file.Local, id, file.Remote)
					end
				end
			elseif atom.Deploy ~= nil then
				errorf(id, "Deploy must be a table of file paths")
			end

			if atom.InstallScript or atom.UninstallScript then
				notef(id, "has an install or uninstall script; users will be asked to approve it")
			end
		end
	end
end

print(("\n%d atoms checked, %d errors, %d notes"):format(checked, errors, notes))
os.exit(errors > 0 and 1 or 0)
