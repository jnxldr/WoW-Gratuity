-- Enchant list window: search, slot filter, mats and AH cost per enchant. Stock Blizzard templates only.
local _, ns = ...
local Recipes, Price, Tip = ns.Recipes, ns.Price, ns.Tip

local List = {}
ns.List = List

local ROW_HEIGHT = 40
local MAX_MATS = 6 -- most reagents any enchant has is 5
local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
local GetItemNameByID = C_Item and C_Item.GetItemNameByID or function(id) return (GetItemInfo(id)) end
local RequestItem = C_Item and C_Item.RequestLoadItemDataByID or function() end
local InsertLink = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)

local LIST_WIDTH = 404 -- left half; the detail pane fills the right
local SOFT = { 0.82, 0.82, 0.82 }

local frame
local entries, slots -- built on first open: { spellID, name, short, icon, slot, mats }, sorted slot names
local state = { text = "", slot = nil, selected = nil }

local function BuildEntries()
	entries, slots = {}, {}
	local seenSlot = {}
	for spellID in pairs(ns.Enchants) do
		local name, icon, slot = Recipes.Info(spellID)
		local mats = Recipes.Mats(spellID)
		if name and mats then
			-- short: the list drops the "Enchant " every name starts with ("Boots - Minor Stamina")
			entries[#entries + 1] = { spellID = spellID, name = name, short = (name:gsub("^Enchant ", "")), icon = icon,
				slot = slot, mats = mats }
			if not seenSlot[slot] then
				seenSlot[slot] = true
				slots[#slots + 1] = slot
			end
			for _, m in ipairs(mats) do RequestItem(m[1]) end -- so mat names are searchable
		end
	end
	table.sort(entries, function(a, b)
		if a.slot ~= b.slot then return a.slot < b.slot end
		return a.name < b.name
	end)
	table.sort(slots)
end

-- Lower-case text a search is matched against: enchant name, slot and mat names.
local function Haystack(e)
	local parts = { e.name, e.slot }
	for _, m in ipairs(e.mats) do parts[#parts + 1] = GetItemNameByID(m[1]) or "" end
	return table.concat(parts, " "):lower()
end

local function RowOnEnter(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(row.entry.spellID)
	GameTooltip:AddLine("Click: show the tip. Shift-click: link in chat.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function RowOnClick(row)
	local spellID = row.entry.spellID
	if IsModifiedClick("CHATLINK") and InsertLink then
		local link = C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(spellID)
		if link then InsertLink(link) end
		return
	end
	List.Select(spellID)
end

-- Shows an enchant on the right and marks its row. Remembered, so the window reopens on it.
function List.Select(spellID)
	state.selected = spellID
	ns.db.lastSpell = spellID
	ns.Detail.Show(spellID)
	if frame then
		frame.ScrollBox:ForEachFrame(function(row)
			if row.Selected then row.Selected:SetShown(row.entry and row.entry.spellID == spellID) end
		end)
	end
end

local function CreateRowParts(row)
	row:SetHeight(ROW_HEIGHT)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(32, 32)
	row.Icon:SetPoint("LEFT", 4, 0)

	-- The tip is the main number (gold); the mats cost sits under it, smaller.
	row.Tip = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Tip:SetPoint("TOPRIGHT", -8, -5)
	row.Tip:SetJustifyH("RIGHT")
	row.Cost = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Cost:SetTextColor(unpack(SOFT))
	row.Cost:SetPoint("BOTTOMRIGHT", -8, 6)
	row.Cost:SetJustifyH("RIGHT")

	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -1)
	row.Name:SetPoint("RIGHT", row.Tip, "LEFT", -8, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

	row.Mats = {}
	for i = 1, MAX_MATS do
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(14, 14)
		if i == 1 then
			icon:SetPoint("BOTTOMLEFT", row.Icon, "BOTTOMRIGHT", 8, 1)
		else
			icon:SetPoint("LEFT", row.Mats[i - 1].count, "RIGHT", 8, 0)
		end
		local count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		count:SetPoint("LEFT", icon, "RIGHT", 2, 0)
		row.Mats[i] = { icon = icon, count = count }
	end

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row.Selected = row:CreateTexture(nil, "BACKGROUND")
	row.Selected:SetAllPoints()
	row.Selected:SetColorTexture(1, 0.82, 0, 0.14)
	row.Selected:Hide()

	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnEnter", RowOnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", RowOnClick)
end

local function InitRow(row, e)
	if not row.Icon then CreateRowParts(row) end
	row.entry = e
	row.Selected:SetShown(e.spellID == state.selected)
	row.Icon:SetTexture(e.icon)
	row.Name:SetText(e.short)
	for i, part in ipairs(row.Mats) do
		local m = e.mats[i]
		part.icon:SetShown(m ~= nil)
		part.count:SetShown(m ~= nil)
		if m then
			part.icon:SetTexture(GetItemIcon(m[1]))
			part.count:SetText(m[2])
		end
	end
	local total, priced, count = Tip.Base(e.mats)
	if priced == 0 then
		row.Tip:SetText("|cff999999no price|r")
		row.Cost:SetText("")
	else
		local partial = priced < count and " |cffff8000+?|r" or ""
		local tip = Tip.Compute(total, ns.db.tipPct, ns.db.rounding, ns.db.minTip)
		row.Tip:SetText(Tip.MoneyIcons(tip) .. partial)
		row.Cost:SetText("mats " .. Tip.MoneyIcons(total) .. partial)
	end
end

-- Sort orders for the list (saved as ns.db.listSort). entries are already in slot-then-name order.
local SORTS = {
	{ key = "slot", label = "Sort: slot" },
	{ key = "name", label = "Sort: name" },
	{ key = "cheap", label = "Sort: cheapest" },
	{ key = "dear", label = "Sort: dearest" },
}

-- Sorts a list of entries in place. By cost: mats at AH (own prices and vendor included); enchants with no price at all go
-- last, partly priced ones by what is known; ties by name.
local function SortEntries(list, key)
	if key == "name" then
		table.sort(list, function(a, b) return a.name < b.name end)
	elseif key == "cheap" or key == "dear" then
		local cost = {}
		for _, e in ipairs(list) do
			local total, priced = Tip.Base(e.mats)
			cost[e] = priced > 0 and total or false
		end
		table.sort(list, function(a, b)
			local ca, cb = cost[a], cost[b]
			if ca and cb and ca ~= cb then
				if key == "cheap" then return ca < cb end
				return ca > cb
			end
			if (ca and true) ~= (cb and true) then return ca and true or false end
			return a.name < b.name
		end)
	else
		table.sort(list, function(a, b)
			if a.slot ~= b.slot then return a.slot < b.slot end
			return a.name < b.name
		end)
	end
end

local function FindEntry(spellID)
	for _, e in ipairs(entries) do
		if e.spellID == spellID then return e end
	end
end

-- Rebuilds the visible list from the search text and slot filter. keepScroll: price refresh, not a new filter.
function List.Refresh(keepScroll)
	if not frame then return end
	local words = Recipes.Words(state.text)
	local shownList = {}
	for _, e in ipairs(entries) do
		if (not state.slot or e.slot == state.slot) and (#words == 0 or Recipes.MatchWords(Haystack(e), words)) then
			shownList[#shownList + 1] = e
		end
	end
	SortEntries(shownList, ns.db.listSort)
	local provider = CreateDataProvider()
	for _, e in ipairs(shownList) do provider:Insert(e) end
	local shown = #shownList
	local retain = keepScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
	frame.ScrollBox:SetDataProvider(provider, retain)
	frame.Count:SetText(("%d of %d enchants"):format(shown, #entries))
	-- Never an empty right side: on first open show the last enchant you looked at, else the top of the list.
	if not state.selected then
		local last = ns.db.lastSpell and FindEntry(ns.db.lastSpell)
		local first = last or shownList[1] or entries[1]
		if first then List.Select(first.spellID) end
	end
end

local function Create()
	frame = CreateFrame("Frame", "GratuityList", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetTitle("Enchant Gratuity")
	frame:SetSize(LIST_WIDTH + 8 + 400, 600)
	frame:SetPoint("CENTER")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, frame:GetName()) -- Escape closes it

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetSize(128, 20)
	search:SetPoint("TOPLEFT", 18, -32)
	search:HookScript("OnTextChanged", function(self)
		state.text = self:GetText() or ""
		List.Refresh()
	end)
	frame.Search = search

	local sort = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	sort:SetWidth(125)
	sort:SetPoint("TOPRIGHT", frame, "TOPLEFT", LIST_WIDTH + 4, -30)
	sort:SetupMenu(function(_, root)
		for _, s in ipairs(SORTS) do
			root:CreateRadio(s.label, function() return (ns.db.listSort or "slot") == s.key end, function()
				ns.db.listSort = s.key
				List.Refresh()
			end)
		end
	end)

	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	frame.SlotDropdown = dropdown
	dropdown:SetWidth(120)
	dropdown:SetPoint("RIGHT", sort, "LEFT", -6, 0)
	dropdown:SetupMenu(function(_, root)
		local function Add(label, value)
			root:CreateRadio(label, function() return state.slot == value end, function()
				state.slot = value
				List.Refresh()
			end)
		end
		Add("All slots", nil)
		for _, slot in ipairs(slots) do Add(slot, slot) end
	end)

	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", 8, -60)
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", LIST_WIDTH + 4, 28)

	-- Right half: the detail pane in its own inset, from the top of the window.
	local right = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	right:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_WIDTH + 12, -30)
	right:SetPoint("BOTTOMRIGHT", -8, 28)
	ns.Detail.Create(right)

	local scrollBox = CreateFrame("Frame", nil, frame.Inset, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 4, -4)
	scrollBox:SetPoint("BOTTOMRIGHT", -22, 4)
	local scrollBar = CreateFrame("EventFrame", nil, frame.Inset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	frame.ScrollBox = scrollBox

	frame.Count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.Count:SetTextColor(unpack(SOFT))
	frame.Count:SetPoint("BOTTOMLEFT", 14, 9)
	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetTextColor(unpack(SOFT))
	hint:SetPoint("BOTTOMRIGHT", -14, 9)
	hint:SetText("Right-click a mat to set your own price · Shift-click an enchant to link it")

	frame:SetScript("OnShow", function() List.Refresh(true) end)
	Price.OnUpdate(function()
		if frame:IsShown() then List.Refresh(true) end
	end)
	frame:Hide()
end

-- Opens the window on an enchant (1.2: clicking an enchant link in chat). Clears a search or slot filter that would hide
-- it and scrolls its row into view. Returns false if it isn't one of the enchants in the list.
function List.Open(spellID)
	if not entries then BuildEntries() end
	local e = FindEntry(spellID)
	if not e then return false end
	if not frame then Create() end
	local words = Recipes.Words(state.text)
	local hidden = (state.slot and e.slot ~= state.slot) or (#words > 0 and not Recipes.MatchWords(Haystack(e), words))
	if hidden then
		state.slot, state.text = nil, ""
		frame.Search:SetText("")
		frame.SlotDropdown:GenerateMenu()
	end
	state.selected = spellID -- so a first OnShow doesn't pick the last enchant instead
	frame:Show()
	List.Refresh(not hidden)
	List.Select(spellID)
	local box = frame.ScrollBox
	if box.ScrollToElementDataByPredicate then
		pcall(box.ScrollToElementDataByPredicate, box, function(data) return data.spellID == spellID end,
			ScrollBoxConstants and ScrollBoxConstants.AlignCenter, nil,
			ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation)
	end
	return true
end

function List.Toggle()
	if not entries then BuildEntries() end
	if not frame then Create() end
	frame:SetShown(not frame:IsShown())
end
