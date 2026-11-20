-- Where the advert can go, and opening the chat box pre-filled. Nothing is ever sent automatically: you press Enter.
local _, ns = ...
local Advertise = {}
ns.Advertise = Advertise

local OpenChat = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)

-- Fixed targets first (Say, Party, Guild), then joined channels by name (their numbers differ per character).
local FIXED = {
	{ key = "SAY", label = "Say", slash = "/s" },
	{ key = "PARTY", label = "Party", slash = "/p", available = function() return IsInGroup() end, hint = "you're not in a group" },
	{ key = "GUILD", label = "Guild", slash = "/g", available = function() return IsInGuild() end, hint = "you're not in a guild" },
}
local IS_FIXED = {}
for _, f in ipairs(FIXED) do IS_FIXED[f.key] = true end

-- { [name] = number } of the channels you have joined.
local function JoinedChannels()
	local joined, raw = {}, { GetChannelList() }
	for i = 1, #raw, 3 do
		local id, name, disabled = raw[i], raw[i + 1], raw[i + 2]
		if name and not disabled then joined[name] = id end
	end
	return joined
end

-- Everything Settings offers as a checkbox: { key, label }. Ticked channels you have left are kept in the list.
function Advertise.Choices()
	local list = {}
	for _, f in ipairs(FIXED) do list[#list + 1] = { key = f.key, label = f.label } end
	local joined, names = JoinedChannels(), {}
	for name in pairs(joined) do names[#names + 1] = name end
	for key, on in pairs(ns.db.channels) do
		if on and not IS_FIXED[key] and not joined[key] then names[#names + 1] = key end
	end
	table.sort(names, function(a, b) return (joined[a] or 99) < (joined[b] or 99) end)
	for _, name in ipairs(names) do
		local id = joined[name]
		list[#list + 1] = { key = name, label = id and ("%d. %s"):format(id, name) or (name .. " (not joined)") }
	end
	return list
end

-- The ticked targets, in the same order: { key, label, slash = "/4" or nil, hint = why not }.
function Advertise.Targets()
	local targets = {}
	for _, f in ipairs(FIXED) do
		if ns.db.channels[f.key] then
			local ok = not f.available or f.available()
			targets[#targets + 1] = { key = f.key, label = f.label, slash = ok and f.slash or nil, hint = not ok and f.hint or nil }
		end
	end
	local joined, names = JoinedChannels(), {}
	for key, on in pairs(ns.db.channels) do
		if on and not IS_FIXED[key] then names[#names + 1] = key end
	end
	table.sort(names, function(a, b) return (joined[a] or 99) < (joined[b] or 99) end)
	for _, name in ipairs(names) do
		local id = joined[name]
		targets[#targets + 1] = { key = name, label = name, slash = id and ("/" .. id) or nil,
			hint = not id and "you haven't joined this channel" or nil }
	end
	return targets
end

-- Opens the chat box with "/4 <message>" in it (editable). Returns false if this client can't.
function Advertise.Open(target, msg)
	if not (OpenChat and target.slash and msg) then return false end
	OpenChat(target.slash .. " " .. msg)
	return true
end
