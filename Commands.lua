-- /gratuity: opens the list window; text commands for details and checks.
local _, ns = ...
local Print, Recipes, Price, Tip = ns.Print, ns.Recipes, ns.Price, ns.Tip

local MAX_LIST = 15
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetItemNameByID = C_Item and C_Item.GetItemNameByID or function(id) return (GetItemInfo(id)) end

-- Calls back once every item's data is loaded (or after 3 s, whichever comes first) with { [itemID] = link or "item:<id>" }.
local function WithItems(ids, callback)
	local links, pending, done = {}, #ids, false
	local function finish()
		if done then return end
		done = true
		for _, id in ipairs(ids) do links[id] = links[id] or ("item:" .. id) end
		callback(links)
	end
	if pending == 0 then return finish() end
	for _, id in ipairs(ids) do
		local item = Item:CreateFromItemID(id)
		if item:IsItemEmpty() then
			pending = pending - 1
		else
			item:ContinueOnItemLoad(function()
				links[id] = item:GetItemLink()
				pending = pending - 1
				if pending == 0 then finish() end
			end)
		end
	end
	if pending == 0 then finish() else C_Timer.After(3, finish) end
end

local function Money(copper)
	return copper and Tip.MoneyIcons(copper) or "|cff999999no price|r"
end

local function AgeDays(source, age, secs)
	if source == "vendor" then return "vendor" end
	if source == "manual" then return "your price" end
	if source == "none" then return "none on the AH" end
	if source ~= "ah" then return "" end
	if secs then return "AH, " .. Price.FormatDuration(secs) .. " ago" end
	if age == nil then return "AH, over 21 d" end
	return age == 0 and "AH, today" or ("AH, %d d"):format(age)
end

local function Dump(spellID)
	local name, _, slot = Recipes.Info(spellID)
	local mats, source = Recipes.Mats(spellID)
	if not mats then
		Print(("%s (%d): no reagents known"):format(name or "?", spellID))
		return
	end
	local ids = {}
	for i, m in ipairs(mats) do ids[i] = m[1] end
	WithItems(ids, function(links)
		local base, priced, count, _, lines = Tip.Base(mats)
		Print(("%s (spell %d, %s), mats from the %s"):format(name or "?", spellID, slot or "?", source))
		local matText = {}
		for i, l in ipairs(lines) do
			local itemID, n, unit, src, age, cost, secs = unpack(l, 1, 7)
			local have = GetItemCount(itemID, true)
			print(("   %d x %s  %s each = %s  (%s)  have %d"):format(n, links[itemID], Money(unit), Money(cost),
				AgeDays(src, age, secs), have))
			local itemName = GetItemNameByID(itemID) or ("item " .. itemID)
			matText[i] = n .. "x " .. itemName
		end
		local pct = ns.db.tipPct
		local tip = Tip.Compute(base, pct, ns.db.rounding, ns.db.minTip)
		local incomplete = priced < count and (" |cffff8000(%d of %d mats priced)|r"):format(priced, count) or ""
		print(("   Mats at AH: %s%s"):format(Money(base), incomplete))
		print(("   Tip at %s%%: %s  ->  mats + tip %s"):format(pct, Money(tip), Money(base + tip)))
		print("   " .. Price.AgeLine())
		local GetRecipeLink = C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink
		local ok, link = false, nil
		if GetRecipeLink then ok, link = pcall(GetRecipeLink, spellID) end
		local msg, trimmed = Tip.Message(ns.db.template, {
			enchant = name or ("spell " .. spellID),
			link = ok and type(link) == "string" and link or name or ("spell " .. spellID),
			mats = table.concat(matText, ", "),
			pct = pct,
			tip = Tip.MoneyText(tip),
			base = Tip.MoneyText(base),
			age = Price.AgeShort(),
		})
		print("   Message: " .. msg .. (trimmed and " |cffff8000(trimmed to 255)|r" or ""))
	end)
end

local function CmdDump(arg)
	if arg == "" then return Print("usage: /gratuity dump <enchant name, part of it, or spell ID>") end
	local found = Recipes.Find(arg)
	if #found == 0 then return Print("no enchant matches '" .. arg .. "'") end
	if #found == 1 then return Dump(found[1]) end
	Print(("%d enchants match '%s'%s:"):format(#found, arg, #found > MAX_LIST and (", first " .. MAX_LIST) or ""))
	for i = 1, math.min(#found, MAX_LIST) do
		print(("   %d  %s"):format(found[i], (Recipes.Info(found[i]))))
	end
	print(("   Pick one: /gratuity dump %d, or add a word (e.g. the slot)."):format(found[1]))
end

local function CmdCheck()
	local same, changed, noLive, noName = Recipes.Compare()
	local total = same + #changed + #noLive
	Print(("%d enchants (list from build %s): %d match the client, %d differ, %d without client reagents, %d without a name")
		:format(total, ns.DataBuild, same, #changed, #noLive, #noName))
	local function List(title, ids)
		if #ids == 0 then return end
		table.sort(ids)
		print("   " .. title .. ":")
		for i = 1, math.min(#ids, MAX_LIST) do
			print(("      %d  %s"):format(ids[i], Recipes.Info(ids[i]) or "?"))
		end
		if #ids > MAX_LIST then print(("      ... and %d more"):format(#ids - MAX_LIST)) end
	end
	List("differ (Gratuity uses the game's mats)", changed)
	List("no client reagents (the list's are used)", noLive)
	List("no name from the client", noName)
end

local function CmdTip(arg)
	local pct = tonumber(arg)
	if not pct or pct < 0 or pct > 1000 then
		return Print(("tip is %s%%. Set with /gratuity tip <percent>"):format(ns.db.tipPct))
	end
	ns.db.tipPct = pct
	Print(("tip set to %s%%"):format(pct))
end

local COMMANDS = {
	dump = CmdDump,
	check = CmdCheck,
	tip = CmdTip,
	age = function() Print((Price.AgeLine())) end,
	prices = function()
		if ns.AH.Progress() then ns.AH.StopFullCheck() else ns.AH.StartFullCheck() end
	end,
	options = function() ns.Settings.Open() end,
	minimap = function()
		ns.Launcher.SetShown(not ns.Launcher.IsShown())
		Print("minimap button " .. (ns.Launcher.IsShown() and "shown" or "hidden"))
	end,
}

SLASH_GRATUITY1 = "/gratuity"
SlashCmdList.GRATUITY = function(msg)
	local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	local fn = COMMANDS[cmd:lower()]
	if fn then return fn(arg) end
	if cmd == "" then return ns.List.Toggle() end
	Print("commands:")
	print("   /gratuity  - open or close the enchant list")
	print("   /gratuity options  - settings (also right-click the minimap button)")
	print("   /gratuity minimap  - show or hide the minimap button")
	print("   /gratuity dump <words|spellID>  - mats, AH cost, tip and message (e.g. boots minor stamina)")
	print("   /gratuity check  - compare the client's reagents with the shipped list")
	print("   /gratuity age  - how old the AH prices are")
	print("   /gratuity prices  - at the AH: check all mat prices (again: stop); same as the button under the AH")
	print("   /gratuity tip <percent>  - default tip % (now " .. ns.db.tipPct .. "%)")
end
