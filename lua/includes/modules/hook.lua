local gmod = gmod
local floor = math.floor
local clamp = math.Clamp
local file = file
local timer = timer
local pairs = pairs
local next = next
local setmetatable = setmetatable
local isstring = isstring
local isentity = isentity
local isnumber = isnumber
local isbool = isbool
local isfunction = isfunction
local type = type
local concat = table.concat
local gsub = string.gsub
local CompileString = CompileString
local xpcall = xpcall
local error = error
local ErrorNoHaltWithStack = ErrorNoHaltWithStack
local ErrorNoHalt = ErrorNoHalt
local print = print

local _GLOBAL = _G

local EMPTY_FUNC = function() end

do
	-- this is for addons that think every server only has ulx and supplies numbers for priorities instead of using the constants
	HOOK_MONITOR_HIGH = -2
	HOOK_HIGH = -1
	HOOK_NORMAL = 0
	HOOK_LOW = 1
	HOOK_MONITOR_LOW = 2

	PRE_HOOK = {-4}
	PRE_HOOK_RETURN = {-3}
	NORMAL_HOOK = {0}
	POST_HOOK_RETURN = {3}
	POST_HOOK = {4}
end

local PRE_HOOK = PRE_HOOK
local PRE_HOOK_RETURN = PRE_HOOK_RETURN
local NORMAL_HOOK = NORMAL_HOOK
local POST_HOOK_RETURN = POST_HOOK_RETURN
local POST_HOOK = POST_HOOK

local NORMAL_PRIORITIES_ORDER = {
	[PRE_HOOK] = 1, [HOOK_MONITOR_HIGH] = 2, [PRE_HOOK_RETURN] = 3, [HOOK_HIGH] = 4,
	[NORMAL_HOOK] = 5, [HOOK_NORMAL] = 5, [HOOK_LOW] = 6, [HOOK_MONITOR_LOW] = 7,
	-- Special hooks, they don't use an order
}

local EVENTS_LISTS = {
	-- Special hooks
	[POST_HOOK_RETURN] = 2,
	[POST_HOOK] = 3,
}
for k, v in pairs(NORMAL_PRIORITIES_ORDER) do
	EVENTS_LISTS[k] = 1
end

local MAIN_PRIORITIES = {[PRE_HOOK] = true, [PRE_HOOK_RETURN] = true, [NORMAL_HOOK] = true, [POST_HOOK_RETURN] = true, [POST_HOOK] = true}

local PRIORITIES_NAMES = {
	[PRE_HOOK] = "PRE_HOOK", [HOOK_MONITOR_HIGH] = "HOOK_MONITOR_HIGH", [PRE_HOOK_RETURN] = "PRE_HOOK_RETURN",
	[HOOK_HIGH] = "HOOK_HIGH", [NORMAL_HOOK] = "NORMAL_HOOK", [HOOK_NORMAL] = "HOOK_NORMAL",
	[HOOK_LOW] = "HOOK_LOW", [HOOK_MONITOR_LOW] = "HOOK_MONITOR_LOW", [POST_HOOK_RETURN] = "POST_HOOK_RETURN", [POST_HOOK] = "POST_HOOK",
}

module("hook")

Author = "coomunity print (super koders)"
Version = "1.0.0"

local events = {}
local object_hooks = {}
local dispatchers

-- Fixed signatures cannot distinguish omitted arguments from trailing nils.
local function argument_count(a1, a2, a3, a4, a5, a6, a7, a8)
	if a8 ~= nil then return 8 end
	if a7 ~= nil then return 7 end
	if a6 ~= nil then return 6 end
	if a5 ~= nil then return 5 end
	if a4 ~= nil then return 4 end
	if a3 ~= nil then return 3 end
	if a2 ~= nil then return 2 end
	if a1 ~= nil then return 1 end
	return 0
end

-- A call keeps its list and its initial length. After a structural edit,
-- the old list resolves callbacks through the current registration.
local retired_list_meta = {
	__index = function(list, index)
		local node = list.nodes[index]
		local current = node.event[node.name]
		if current and current.priority == node.priority then
			return node.event[0][EVENTS_LISTS[node.priority]][current.index]
		end
		return EMPTY_FUNC
	end
}

local function new_list(length)
	return {[0] = length, nodes = {}}
end

local function move_entry(source, target, from, to)
	local node = source.nodes[from]
	target.nodes[to] = node
	target[to] = source[from]
	node.index = to
	source[from] = nil
end

local function new_event(name)
	-- Hook names cannot be numbers, so slot 0 holds the three lists.
	local event = {[0] = {
		new_list(0), -- normal hooks
		new_list(0), -- post return hooks
		new_list(0), -- post hooks
		0, -- combined post hook count
	}}
	events[name] = event
	return event
end

function GetTable()
	local new_table = {}
	for event_name, event in pairs(events) do
		local hooks = {}
		for i = 1, 3 do
			local list = event[0][i]
			for j = 1, list[0 --[[length]]] do
				local node = list.nodes[j]
				hooks[node.name] = node.real_func
			end
		end
		new_table[event_name] = hooks
	end
	return new_table
end

local function remove_hook(event_name, name)
	local event = events[event_name]
	if not event then return end -- no event with that name

	local removed = event[name]
	if not removed then return end -- no hook with that name

	local lists = event[0 --[[lists]]]
	local list_index = EVENTS_LISTS[removed.priority]
	local old_list = lists[list_index]
	local updated_list = new_list(old_list[0 --[[length]]] - 1)
	local removed_index = removed.index
	for i = 1, removed_index - 1 do
		move_entry(old_list, updated_list, i, i)
	end
	for i = removed_index + 1, old_list[0 --[[length]]] do
		move_entry(old_list, updated_list, i, i - 1)
	end
	old_list[removed_index] = nil
	setmetatable(old_list, retired_list_meta)
	lists[list_index] = updated_list
	if list_index ~= 1 then
		lists[4 --[[post count]]] = lists[4 --[[post count]]] - 1
	end
	event[name] = nil
	removed.real_func = nil

	local subscriptions = object_hooks[name]
	if subscriptions then
		subscriptions[event_name] = nil
		if not next(subscriptions) then
			object_hooks[name] = nil
		end
	end
end
local function remove_object_hooks(name)
	local subscriptions = object_hooks[name]
	if not subscriptions then return end

	object_hooks[name] = nil
	for event_name in pairs(subscriptions) do
		remove_hook(event_name, name)
	end
end

function Remove(event_name, name)
	if not isstring(event_name) then ErrorNoHaltWithStack("bad argument #1 to 'Remove' (string expected, got " .. type(event_name) .. ")") return end

	if not isstring(name) and (name == nil or isnumber(name) or isbool(name) or isfunction(name) or not name.IsValid) then
		ErrorNoHaltWithStack("bad argument #2 to 'Remove' (string expected, got " .. type(name) .. ")")
		return
	end

	remove_hook(event_name, name)
end

function Add(event_name, name, func, priority)
	if not isstring(event_name) then ErrorNoHaltWithStack("bad argument #1 to 'Add' (string expected, got " .. type(event_name) .. ")") return end
	if not isfunction(func) then ErrorNoHaltWithStack("bad argument #3 to 'Add' (function expected, got " .. type(func) .. ")") return end

	local real_func = func
	local object_hook = not isstring(name)
	if object_hook and (name == nil or isnumber(name) or isbool(name) or isfunction(name) or not name.IsValid) then
		ErrorNoHaltWithStack("bad argument #2 to 'Add' (string expected, got " .. type(name) .. ")")
		return
	end

	if object_hook and isentity(name) and not name:IsValid() then return end

	if isnumber(priority) then
		priority = floor(priority)
		if priority < -2 then priority = -2 end
		if priority > 2 then priority = 2 end
	elseif not MAIN_PRIORITIES[priority] then
		if priority ~= nil then
			ErrorNoHaltWithStack("bad argument #4 to 'Add' (priority expected, got " .. type(priority) .. ")")
		end
		priority = NORMAL_HOOK
	end

	local monitor = priority == PRE_HOOK or priority == -2 or priority == 2
	if object_hook then
		func = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
			local isvalid = name.IsValid
			if not isvalid or not isvalid(name) then
				remove_object_hooks(name)
				return
			end
			-- Post hooks receive the results table ahead of the eight event arguments.
			if a9 ~= nil then
				return real_func(name, a1, a2, a3, a4, a5, a6, a7, a8, a9)
			end
			local invoke = dispatchers[argument_count(a1, a2, a3, a4, a5, a6, a7, a8)].with_prefix
			if monitor then
				invoke(real_func, name, a1, a2, a3, a4, a5, a6, a7, a8)
				return
			end
			return invoke(real_func, name, a1, a2, a3, a4, a5, a6, a7, a8)
		end
	elseif monitor then
		func = function(a1, a2, a3, a4, a5, a6, a7, a8)
			local invoke = dispatchers[argument_count(a1, a2, a3, a4, a5, a6, a7, a8)].invoke
			invoke(real_func, a1, a2, a3, a4, a5, a6, a7, a8)
		end
	end

	local event = events[event_name] or new_event(event_name)
	local lists = event[0 --[[lists]]]
	local list_index = EVENTS_LISTS[priority]
	local current = event[name]
	if current then
		if current.priority == priority then
			lists[list_index][current.index] = func
			current.real_func = real_func
			return
		end
		remove_hook(event_name, name)
	end

	local hook_list = lists[list_index]
	local length = hook_list[0 --[[length]]]
	local index = length + 1
	local order = NORMAL_PRIORITIES_ORDER[priority]
	if order then
		while index > 1 and NORMAL_PRIORITIES_ORDER[hook_list.nodes[index - 1].priority] > order do
			index = index - 1
		end
	end

	-- Appending leaves existing iterations intact because they captured the length.
	-- Inserting earlier requires a new list so active calls keep their order.
	if index <= length then
		local updated_list = new_list(length + 1)
		for i = 1, index - 1 do
			move_entry(hook_list, updated_list, i, i)
		end
		for i = index, length do
			move_entry(hook_list, updated_list, i, i + 1)
		end
		setmetatable(hook_list, retired_list_meta)
		hook_list = updated_list
		lists[list_index] = hook_list
	end

	local node = {
		event = event,
		name = name,
		priority = priority,
		real_func = real_func,
		index = index,
	}
	hook_list.nodes[index] = node
	hook_list[index] = func
	hook_list[0 --[[length]]] = length + 1
	event[name] = node
	if object_hook then
		local subscriptions = object_hooks[name]
		if not subscriptions then
			subscriptions = {}
			object_hooks[name] = subscriptions
		end
		subscriptions[event_name] = true
	end
	if list_index ~= 1 then
		lists[4 --[[post count]]] = lists[4 --[[post count]]] + 1
	end
end

-- All generated calls have a fixed signature. The argument count is selected
-- once at the public entry point, outside the hook loops.
local DISPATCH_TEMPLATE = [=[
	do
		local function scan(callbacks, length@PARAMS@)
			local bulk = length - length % @WIDTH@
			for i = 1, bulk, @WIDTH@ do
				@BLOCK@
			end
			for i = bulk + 1, length do
				local a, b, c, d, e, f = callbacks[i](@ARGS@)
				if a ~= nil then return i, a, b, c, d, e, f end
			end
		end

		local function post(lists, name, a, b, c, d, e, f@PARAMS@)
			local results = {name, a, b, c, d, e, f}
			local callbacks = lists[2]
			for i = 1, callbacks[0] do
				local n_a, n_b, n_c, n_d, n_e, n_f = callbacks[i](results@PARAMS@)
				if n_a ~= nil then
					a, b, c, d, e, f = n_a, n_b, n_c, n_d, n_e, n_f
					results = {callbacks.nodes[i].name, a, b, c, d, e, f}
					break
				end
			end
			callbacks = lists[3]
			for i = 1, callbacks[0] do
				callbacks[i](results@PARAMS@)
			end
			return a, b, c, d, e, f
		end

		local function call(event_name, gm@PARAMS@)
			local event = events[event_name]
			if not event then
				local method = gm and gm[event_name]
				if method then return method(gm@PARAMS@) end
				return
			end

			local lists = event[0]
			local callbacks = lists[1]
			local length = callbacks[0]
			if length >= 32 then
				local index, a, b, c, d, e, f = scan(callbacks, length@PARAMS@)
				if index then
					if lists[4] == 0 then return a, b, c, d, e, f end
					return post(lists, callbacks.nodes[index].name, a, b, c, d, e, f@PARAMS@)
				end
			else
				for i = 1, length do
					local a, b, c, d, e, f = callbacks[i](@ARGS@)
					if a ~= nil then
						if lists[4] == 0 then return a, b, c, d, e, f end
						return post(lists, callbacks.nodes[i].name, a, b, c, d, e, f@PARAMS@)
					end
				end
			end

			local method = gm and gm[event_name]
			if method then
				local a, b, c, d, e, f = method(gm@PARAMS@)
				if lists[4] == 0 then return a, b, c, d, e, f end
				return post(lists, gm, a, b, c, d, e, f@PARAMS@)
			end
			if lists[4] == 0 then return nil, nil, nil, nil, nil, nil end
			return post(lists, nil, nil, nil, nil, nil, nil, nil@PARAMS@)
		end

		local function protected_call(event_name, gm@PARAMS@)
			local event = events[event_name]
			if not event then
				local method = gm and gm[event_name]
				if method then protect(method, report_error, gm@PARAMS@) end
				return
			end

			local lists = event[0]
			local callbacks = lists[1]
			for i = 1, callbacks[0] do
				protect(callbacks[i], report_error@PARAMS@)
			end
			local method = gm and gm[event_name]
			if method then protect(method, report_error, gm@PARAMS@) end
			if lists[4] == 0 then return end

			local results = {}
			callbacks = lists[2]
			for i = 1, callbacks[0] do
				protect(callbacks[i], report_error, results@PARAMS@)
			end
			callbacks = lists[3]
			for i = 1, callbacks[0] do
				protect(callbacks[i], report_error, results@PARAMS@)
			end
		end

		dispatchers[@ARITY@] = {
			call = call,
			protected_call = protected_call,
			invoke = function(func@PARAMS@) return func(@ARGS@) end,
			with_prefix = function(func, prefix@PARAMS@) return func(prefix@PARAMS@) end,
		}
	end
]=]

local SCAN_STEP = [=[
	do
		local a, b, c, d, e, f = callbacks[@INDEX@](@ARGS@)
		if a ~= nil then return @INDEX@, a, b, c, d, e, f end
	end
]=]

local function build_dispatchers()
	local width = 8
	local source = {"return function(events, protect, report_error)", "local dispatchers = {}"}
	local parameters = {}
	for arity = 0, 8 do
		local args = concat(parameters, ", ")
		local block = {}
		for offset = 0, width - 1 do
			local index = offset == 0 and "i" or "i + " .. offset
			block[#block + 1] = gsub(SCAN_STEP, "@(%u+)@", {INDEX = index, ARGS = args})
		end
		source[#source + 1] = gsub(DISPATCH_TEMPLATE, "@(%u+)@", {
			ARITY = arity,
			WIDTH = width,
			ARGS = args,
			PARAMS = arity == 0 and "" or ", " .. args,
			BLOCK = concat(block),
		})
		parameters[#parameters + 1] = "a" .. (arity + 1)
	end
	source[#source + 1] = "return dispatchers end"

	local chunk = CompileString(concat(source, "\n"), "srlion/hook_fixed_dispatch", false)
	if not isfunction(chunk) then error(chunk) end
	return chunk()(events, xpcall, ErrorNoHaltWithStack)
end

dispatchers = build_dispatchers()

function Call(event_name, gm, a1, a2, a3, a4, a5, a6, a7, a8)
	local dispatch = dispatchers[argument_count(a1, a2, a3, a4, a5, a6, a7, a8)]
	return dispatch.call(event_name, gm, a1, a2, a3, a4, a5, a6, a7, a8)
end

function ProtectedCall(event_name, gm, a1, a2, a3, a4, a5, a6, a7, a8)
	local dispatch = dispatchers[argument_count(a1, a2, a3, a4, a5, a6, a7, a8)]
	return dispatch.protected_call(event_name, gm, a1, a2, a3, a4, a5, a6, a7, a8)
end

local gamemode_cache
function Run(name, a1, a2, a3, a4, a5, a6, a7, a8)
	if not gamemode_cache then
		gamemode_cache = gmod and gmod.GetGamemode() or nil
	end
	return Call(name, gamemode_cache, a1, a2, a3, a4, a5, a6, a7, a8)
end

function ProtectedRun(name, a1, a2, a3, a4, a5, a6, a7, a8)
	if not gamemode_cache then
		gamemode_cache = gmod and gmod.GetGamemode() or nil
	end
	return ProtectedCall(name, gamemode_cache, a1, a2, a3, a4, a5, a6, a7, a8)
end

Add("EntityRemoved", "SrlionHookLibrary.EntityCleanup", function(entity, full_update)
	if full_update or not object_hooks[entity] then return end

	-- EntityRemoved runs before the entity is gone. Defer cleanup so its own
	-- removal hooks can still run, even if one of the callbacks raises an error.
	timer.Simple(0, function()
		remove_object_hooks(entity)
	end)
end, PRE_HOOK)

function Debug(event_name)
	local event = events[event_name]
	if not event then
		print("No event with that name")
		return
	end

	local lists = event[0]
	print("------START------")
	print("event:", event_name)
	for i = 1, 3 do
		local list = lists[i]
		for j = 1, list[0 --[[length]]] do
			local node = list.nodes[j]
			print("----------")
			print("   name:", node.name)
			print("   func:", list[j])
			print("   real_func:", node.real_func)
			print("   priority:", PRIORITIES_NAMES[node.priority])
			print("   idx:", j)
		end
	end
	print("-------END-------")
end

do -- ulx and dlib
	-- ulx/ulib support
	if file.Exists("ulib/shared/hook.lua", "LUA") then
		local old_include = _GLOBAL.include
		function _GLOBAL.include(f)
			if f == "ulib/shared/hook.lua" then
				timer.Simple(0, function()
					print("Srlion Hook Library: Stopped ULX/ULib from loading it's hook library!")
				end)
				_GLOBAL.include = old_include
				return
			end
			return old_include(f)
		end

		-- this could make an issue with addons that retrieve all hooks and call them, as POST_HOOK(_RETURN)
		-- will be called randomly and their first argument won't be the "returned values" table
		function GetULibTable()
			local new_events = {}

			for event_name, event in pairs(events) do
				local hooks = {[-2] = {}, [-1] = {}, [0] = {}, [1] = {}, [2] = {}}
				for i = 1, 3 do
					local list = event[0][i]
					for j = 1, list[0 --[[length]]] do
						local node = list.nodes[j]
						local priority = node.priority
						priority = isnumber(priority) and priority or priority[1]
						priority = clamp(priority, -2, 2) -- just to make sure it's in the range
						hooks[priority][node.name] = node.real_func
					end
				end
				new_events[event_name] = hooks
			end

			return new_events
		end
	end

	-- bloated hooks warning
	if file.Exists("dlib/modules/hook.lua", "LUA") then
		timer.Simple(0, function()
			ErrorNoHalt("Srlion Hook Library: DLib is installed, you should remove the bloated addon!\n")
			ErrorNoHalt("Srlion Hook Library: DLIB is also slower than default hook library, check github.com/srlion/Hook-Library for more info! THIS MEANS IT MAKES YOUR SERVER SLOWER!\n")
		end)
	end
end
