-- Enchant list (Data.lua) + names, icons and reagents read from the client.
local _, ns = ...
local Recipes = {}
ns.Recipes = Recipes

local function SortMats(mats)
	table.sort(mats, function(a, b) return a[1] < b[1] end)
	return mats
end

-- Reagents from the client: C_TradeSkillUI.GetRecipeSchematic works for recipes the character doesn't know
-- (checked on Forever 2026-11-13). Returns { {itemID, count}, ... } sorted by itemID, or nil.
function Recipes.Live(spellID)
	local GetSchematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
	if not GetSchematic then return nil end
	local ok, schematic = pcall(GetSchematic, spellID, false)
	if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return nil end
	local mats = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local reagent = slot.reagents and slot.reagents[1]
		if slot.required ~= false and reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
			mats[#mats + 1] = { reagent.itemID, slot.quantityRequired }
		end
	end
	if #mats == 0 then return nil end
	return SortMats(mats)
end

-- Reagents from Data.lua, as a sorted copy.
function Recipes.Shipped(spellID)
	local entry = ns.Enchants[spellID]
	if not entry then return nil end
	local mats = {}
	for i, m in ipairs(entry[2]) do mats[i] = { m[1], m[2] } end
	return SortMats(mats)
end

-- Returns mats, source ("client" or "list").
function Recipes.Mats(spellID)
	local live = Recipes.Live(spellID)
	if live then return live, "client" end
	return Recipes.Shipped(spellID), "list"
end

function Recipes.Info(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	local entry = ns.Enchants[spellID]
	return info and info.name, info and info.iconID, entry and entry[1]
end

-- Search words of a text, lower case ("Boots - Minor" -> { "boots", "minor" }).
function Recipes.Words(text)
	local words = {}
	for word in (text or ""):lower():gmatch("[^%s%-]+") do words[#words + 1] = word end
	return words
end

-- True when every word appears in the (lower-case) haystack; true for no words.
function Recipes.MatchWords(haystack, words)
	for _, word in ipairs(words) do
		if not haystack:find(word, 1, true) then return false end
	end
	return true
end

-- Enchants matching text: a spell ID, the exact name, or words that all appear in the name in any order
-- ("boots minor stamina"); case-insensitive. Sorted by name.
function Recipes.Find(text)
	text = strtrim(text or "")
	local id = tonumber(text)
	if id then return ns.Enchants[id] and { id } or {} end
	local needle = text:lower()
	local words = Recipes.Words(needle)
	local found = {}
	for spellID in pairs(ns.Enchants) do
		local name = Recipes.Info(spellID)
		if name then
			local lower = name:lower()
			if lower == needle then return { spellID } end
			if #words > 0 and Recipes.MatchWords(lower, words) then found[#found + 1] = spellID end
		end
	end
	table.sort(found, function(a, b) return (Recipes.Info(a)) < (Recipes.Info(b)) end)
	return found
end

local function SameMats(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then return false end
	end
	return true
end

-- Compares the client's reagents with Data.lua. Returns same, changed{spellID}, noLive{spellID}, noName{spellID}.
function Recipes.Compare()
	local same, changed, noLive, noName = 0, {}, {}, {}
	for spellID in pairs(ns.Enchants) do
		if not Recipes.Info(spellID) then noName[#noName + 1] = spellID end
		local live = Recipes.Live(spellID)
		if not live then
			noLive[#noLive + 1] = spellID
		elseif SameMats(live, Recipes.Shipped(spellID)) then
			same = same + 1
		else
			changed[#changed + 1] = spellID
		end
	end
	return same, changed, noLive, noName
end
