-- Detail pane, the right half of the Gratuity window (1.1). Laid out in the order a buyer decides: the tip first,
-- then the mats it comes from, then the advert. Stock Blizzard templates only.
local _, ns = ...
local Recipes, Price, Tip, Advertise = ns.Recipes, ns.Price, ns.Tip, ns.Advertise

local Detail = {}
ns.Detail = Detail

local PAD = 12
local MAX_MATS = 6
local MAT_ROW = 22
local QUICK_PCTS = { 10, 15, 20, 25 }
local SOFT = { 0.82, 0.82, 0.82 } -- secondary text, readable on the dark-grey frame
local AGE_ORANGE_DAYS, AGE_RED_DAYS = 1, 3 -- an item's AH price this many days old is tagged orange / red

local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
local GetItemNameByID = C_Item and C_Item.GetItemNameByID or function(id) return (GetItemInfo(id)) end
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local InsertLink = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)

-- The tip is the answer: its own large gold font (no stock "huge" font is in use on Forever).
local TipFont = CreateFont("GratuityTipFont")
do
	local path, _, flags = GameFontNormalLarge:GetFont()
	TipFont:SetFont(path, 28, flags or "")
	TipFont:SetTextColor(1, 0.82, 0)
end

local pane
local current = { spellID = nil }

-- Short tag after a mat's name; second return: true if the AH price counts as old (red).
local function AgeTag(source, age)
	if source == "manual" then return "|cff66ccffyour price|r" end
	if source == "none" then return "|cff999999none on the AH|r" end
	if source ~= "ah" then return nil end
	if age == nil then return "|cffff2020over 21 d old|r", true end
	if age >= AGE_RED_DAYS then return ("|cffff2020%d d old|r"):format(age), true end
	if age >= AGE_ORANGE_DAYS then return ("|cffff8000%d d old|r"):format(age) end
	return nil
end

local function SourceLong(source, age, secs, origin)
	if source == "vendor" then return origin == "auctionator" and "vendor (Auctionator)" or "vendor" end
	if source == "manual" then return "your price" end
	if source == "none" then return "none on the AH, checked " .. Price.FormatDuration(secs or 0) .. " ago" end
	if source ~= "ah" then return "no price" end
	if secs then return "AH, checked " .. Price.FormatDuration(secs) .. " ago" end
	if age == nil then return "AH (Auctionator), over 21 days old" end
	return age == 0 and "AH (Auctionator), today" or ("AH (Auctionator), %d day%s old"):format(age, age == 1 and "" or "s")
end

-- "75c", "1s 20c", "2g 5s" -> copper; "" -> false (clear); anything else -> nil.
local function ParseMoney(text)
	text = strtrim(text or ""):lower()
	if text == "" then return false end
	local copper, found = 0, false
	local rest = text:gsub("(%d+)%s*([gsc])", function(n, unit)
		copper = copper + tonumber(n) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
		found = true
		return ""
	end)
	if not found or strtrim(rest) ~= "" then return nil end
	return copper
end

local function SetManualPrice(itemID, text)
	local name = GetItemNameByID(itemID) or ("item " .. itemID)
	local copper = ParseMoney(text)
	if copper == nil then
		return ns.Print(("'%s' isn't a price. Use g, s and c, e.g. 75c, 1s 20c or 2g."):format(text or ""))
	end
	if copper then
		ns.db.manualPrices[itemID] = copper
		ns.Print(("%s: your price %s each"):format(name, Tip.MoneyIcons(copper)))
	else
		ns.db.manualPrices[itemID] = nil
		ns.Print(name .. ": back to the AH price")
	end
	Detail.Update()
	if ns.List then ns.List.Refresh(true) end
end

local function PopupEditBox(popup)
	return popup.GetEditBox and popup:GetEditBox() or popup.EditBox or popup.editBox
end

StaticPopupDialogs.GRATUITY_PRICE = {
	text = "Your price for %s, each (e.g. 75c, 1s 20c, 2g).\nLeave empty to use the AH price.",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 20,
	OnShow = function(self, itemID)
		local box = PopupEditBox(self)
		local manual = ns.db.manualPrices[itemID]
		box:SetText(manual and Tip.MoneyText(manual) or "")
		box:HighlightText()
		box:SetFocus()
	end,
	OnAccept = function(self, itemID) SetManualPrice(itemID, PopupEditBox(self):GetText()) end,
	EditBoxOnEnterPressed = function(box, itemID)
		SetManualPrice(itemID, box:GetText())
		box:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- The enchanting trade link ("|Henchant:7863|h[Enchanting: ...]|h"), what enchanters post; nil if unavailable.
local function RecipeLink()
	local GetRecipeLink = C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink
	if not (current.spellID and GetRecipeLink) then return nil end
	local ok, link = pcall(GetRecipeLink, current.spellID)
	return ok and type(link) == "string" and link or nil
end

-- Mats you still need ({ name, quantity }), and a tooltip line per mat.
local function MissingMats()
	local missing, lines = {}, {}
	for _, m in ipairs(current.mats or {}) do
		local itemID, need = m[1], m[2]
		local have = GetItemCount(itemID, true) or 0
		local name = GetItemNameByID(itemID)
		if have < need and name then
			missing[#missing + 1] = { name, need - have }
			lines[#lines + 1] = ("%d x %s (have %d of %d)"):format(need - have, name, have, need)
		end
	end
	return missing, lines
end

local function ButtonTooltip(button, title, ...)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(title, 1, 1, 1)
	for i = 1, select("#", ...) do
		GameTooltip:AddLine((select(i, ...)), nil, nil, nil, true)
	end
	GameTooltip:Show()
end

local function SetPct(pct, fromBox)
	ns.db.tipPct = pct -- remembered: the next enchant (and the list's tip column) use it too
	if not fromBox then pane.PctBox:SetText(tostring(pct)) end
	Detail.Update()
	if ns.List then ns.List.Refresh(true) end
end

-- Advertise buttons flow left to right under the message box and wrap downwards. Returns the height they use.
local function LayoutAdvertise()
	local ask = pane.Ask
	local targets = Advertise.Targets()
	local width = ask:GetWidth()
	if width < 100 then width = 360 end -- not laid out yet on the very first draw
	local x, row = 0, 0
	for i, t in ipairs(targets) do
		local b = pane.AdButtons[i]
		if not b then
			b = CreateFrame("Button", nil, ask, "UIPanelButtonTemplate")
			b:SetHeight(22)
			b:SetMotionScriptsWhileDisabled(true)
			b:SetScript("OnClick", function(self)
				if not Advertise.Open(self.target, current.message) then
					ns.Print("can't open the chat box for " .. self.target.label)
				end
			end)
			b:SetScript("OnEnter", function(self)
				local tt = self.target
				if tt.slash then
					ButtonTooltip(self, "Advertise in " .. tt.label, ("Opens the chat box with %s and the message. Edit it "
						.. "if you like, then press Enter to send."):format(tt.slash))
				else
					ButtonTooltip(self, tt.label, "Not available: " .. (tt.hint or "?") .. ".")
				end
			end)
			b:SetScript("OnLeave", GameTooltip_Hide)
			pane.AdButtons[i] = b
		end
		b.target = t
		b:SetText(t.label)
		local w = b:GetFontString():GetStringWidth() + 28
		b:SetWidth(w)
		if x > 0 and x + w > width then x, row = 0, row + 1 end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", pane.MessageBox, "BOTTOMLEFT", x, -6 - row * 26)
		b:SetEnabled(t.slash ~= nil and current.message ~= nil)
		b:Show()
		x = x + w + 4
	end
	for i = #targets + 1, #pane.AdButtons do pane.AdButtons[i]:Hide() end
	pane.AdNone:SetShown(#targets == 0)
	return #targets == 0 and 20 or (row + 1) * 26 + 2
end

-- Recomputes the pane for the current enchant and the remembered tip %.
function Detail.Update()
	if not (pane and pane:IsVisible() and current.spellID) then return end
	local base, priced, count, _, lines = Tip.Base(current.mats)
	local pct = ns.db.tipPct
	local tip = Tip.Compute(base, pct, ns.db.rounding, ns.db.minTip)

	-- Tip block
	if priced == 0 then
		pane.TipAmount:SetText("|cff999999no prices yet|r")
		pane.TipBasis:SetText("Open the AH and Gratuity checks these mats, or right-click a mat to set your own price.")
	else
		local partial = priced < count and " |cffff8000+?|r" or ""
		pane.TipAmount:SetText(Tip.MoneyIcons(tip) .. partial)
		pane.TipBasis:SetText(("%s%% of %s in mats · %s"):format(pct, Tip.MoneyIcons(base), Price.AgeShortColored()))
	end
	local custom = true
	for _, b in ipairs(pane.PctButtons) do
		if b.pct == pct then
			b:LockHighlight()
			custom = false
		else
			b:UnlockHighlight()
		end
	end
	pane.CustomGlow:SetShown(custom)
	if custom then pane.CustomLabel:SetTextColor(1, 0.82, 0) else pane.CustomLabel:SetTextColor(unpack(SOFT)) end
	if not pane.PctBox:HasFocus() then pane.PctBox:SetText(tostring(pct)) end

	-- Mats
	local matText = {}
	local toBuy, toBuyUnpriced, anyHave, anyOld = 0, false, false, false
	for i, row in ipairs(pane.MatRows) do
		local l = lines[i]
		row:SetShown(l ~= nil)
		if l then
			local itemID, n, unit, source, age, cost, secs, origin = unpack(l, 1, 8)
			local name = GetItemNameByID(itemID) or ("item " .. itemID)
			local have = GetItemCount(itemID, true) or 0
			row.data = { itemID = itemID, n = n, unit = unit, source = source, age = age, secs = secs, origin = origin,
				have = have }
			row.Icon:SetTexture(GetItemIcon(itemID))
			row.Name:SetText(("%d %s"):format(n, name))
			local tags = {}
			if have > 0 then
				tags[#tags + 1] = (have >= n and "|cff20ff20have %d/%d|r" or "|cffffd200have %d/%d|r"):format(have, n)
				anyHave = true
			end
			local tag, old = AgeTag(source, age)
			if tag then tags[#tags + 1] = tag end
			anyOld = anyOld or old
			row.Tags:SetText(table.concat(tags, "  "))
			row.Cost:SetText(cost and Tip.MoneyIcons(cost) or "|cff999999no price|r")
			if have < n then
				if unit then toBuy = toBuy + (n - have) * unit else toBuyUnpriced = true end
			end
			matText[i] = n .. "x " .. name
		end
	end
	pane.MatsTotal:SetText(priced > 0 and (Tip.MoneyIcons(base) .. (priced < count and " |cffff8000+?|r" or "")) or "")
	local y = -20 - #lines * MAT_ROW - 4
	pane.ToBuyLabel:SetShown(anyHave)
	pane.ToBuy:SetShown(anyHave)
	if anyHave then
		pane.ToBuyLabel:SetPoint("TOPLEFT", 24, y)
		pane.ToBuy:SetPoint("TOPRIGHT", 0, y)
		pane.ToBuy:SetText((toBuy > 0 or toBuyUnpriced)
			and (Tip.MoneyIcons(toBuy) .. (toBuyUnpriced and " |cffff8000+?|r" or ""))
			or "|cff20ff20you have all the mats|r")
		y = y - 18
	end
	pane.OldNote:SetShown(anyOld)
	if anyOld then
		pane.OldNote:SetPoint("TOPLEFT", 0, y)
		pane.OldNote:SetPoint("TOPRIGHT", 0, y)
		y = y - 16
	end
	pane.Mats:SetHeight(-y)

	local ahOpen = Price.AHOpen()
	pane.SearchAH:SetShown(ahOpen)
	if ahOpen then pane.SearchAH:SetEnabled(#MissingMats() > 0) end

	-- Advert
	local enchantName = current.name or ("spell " .. current.spellID)
	local fields = {
		enchant = enchantName,
		link = RecipeLink() or enchantName,
		mats = table.concat(matText, ", "),
		pct = pct,
		tip = Tip.MoneyText(tip),
		base = Tip.MoneyText(base),
		age = Price.AgeShort(),
	}
	local msg, trimmed = Tip.Message(ns.db.template, fields)
	if trimmed and fields.link ~= enchantName then
		fields.link = enchantName -- a cut link would be broken text in chat
		msg, trimmed = Tip.Message(ns.db.template, fields)
	end
	current.message = msg
	pane.Message:SetText(msg .. (trimmed and " |cffff8000(trimmed to 255)|r" or ""))
	local boxHeight = pane.Message:GetStringHeight() + 14
	pane.MessageBox:SetHeight(boxHeight)
	pane.Ask:SetHeight(18 + boxHeight + LayoutAdvertise())
end

local function CreateMatRow(parent, i)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(MAT_ROW)
	local y = -20 - (i - 1) * MAT_ROW
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(18, 18)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Cost = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Cost:SetPoint("RIGHT")
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
	row.Name:SetWordWrap(false)
	row.Tags = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Tags:SetPoint("LEFT", row.Name, "RIGHT", 8, 0)
	row.Tags:SetPoint("RIGHT", row.Cost, "LEFT", -6, 0)
	row.Tags:SetJustifyH("LEFT")
	row.Tags:SetWordWrap(false)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.06)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(d.itemID)
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Price each", d.unit and Tip.MoneyIcons(d.unit) or "none", 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("From", SourceLong(d.source, d.age, d.secs, d.origin), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("You have", ("%d of %d"):format(d.have, d.n), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddLine("Right-click: set your own price", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnMouseUp", function(self, button)
		if button ~= "RightButton" or not self.data then return end
		local itemID = self.data.itemID
		StaticPopup_Show("GRATUITY_PRICE", GetItemNameByID(itemID) or ("item " .. itemID), nil, itemID)
	end)
	return row
end

local function Divider(block)
	local line = block:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.12)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", block, "TOPLEFT", 0, 6)
	line:SetPoint("BOTTOMRIGHT", block, "TOPRIGHT", 0, 6)
end

-- Builds the pane inside parent (the right inset of the Gratuity window).
function Detail.Create(parent)
	pane = CreateFrame("Frame", nil, parent)
	pane:SetAllPoints()

	-- Header: icon + name (Shift-click = enchant link in chat) and slot.
	local header = CreateFrame("Button", nil, pane)
	header:SetPoint("TOPLEFT", PAD, -PAD)
	header:SetPoint("TOPRIGHT", -PAD, -PAD)
	header:SetHeight(38)
	header.Icon = header:CreateTexture(nil, "ARTWORK")
	header.Icon:SetSize(36, 36)
	header.Icon:SetPoint("LEFT")
	header.Name = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header.Name:SetPoint("TOPLEFT", header.Icon, "TOPRIGHT", 8, -1)
	header.Name:SetPoint("TOPRIGHT", 0, -1)
	header.Name:SetJustifyH("LEFT")
	header.Name:SetWordWrap(false)
	header.Sub = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	header.Sub:SetTextColor(unpack(SOFT))
	header.Sub:SetPoint("BOTTOMLEFT", header.Icon, "BOTTOMRIGHT", 8, 1)
	header:SetScript("OnClick", function()
		if IsModifiedClick("CHATLINK") then
			local link = RecipeLink()
			if link and InsertLink then InsertLink(link) end
		end
	end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(current.spellID)
		GameTooltip:AddLine("Shift-click: link in chat.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	pane.Header = header

	-- Tip block: the answer, where it comes from, and the % to change it.
	local hero = CreateFrame("Frame", nil, pane)
	hero:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
	hero:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
	hero:SetHeight(112)
	local bg = hero:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)
	local label = hero:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOP", 0, -8)
	label:SetText("Suggested tip")
	pane.TipAmount = hero:CreateFontString(nil, "ARTWORK")
	pane.TipAmount:SetFontObject(TipFont)
	pane.TipAmount:SetPoint("TOP", label, "BOTTOM", 0, -4)
	pane.TipBasis = hero:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.TipBasis:SetTextColor(unpack(SOFT))
	pane.TipBasis:SetPoint("TOP", pane.TipAmount, "BOTTOM", 0, -4)
	pane.TipBasis:SetWidth(340)

	local tabs = CreateFrame("Frame", nil, hero)
	tabs:SetSize(#QUICK_PCTS * 48 + 14 + 52 + 40 + 14, 22) -- buttons, gap, "Custom", box, "%"
	tabs:SetPoint("BOTTOM", 0, 8)
	pane.PctButtons = {}
	for i, pct in ipairs(QUICK_PCTS) do
		local b = CreateFrame("Button", nil, tabs, "UIPanelButtonTemplate")
		b:SetSize(44, 22)
		b:SetPoint("LEFT", (i - 1) * 48, 0)
		b:SetText(pct .. "%")
		b.pct = pct
		b:SetScript("OnClick", function() SetPct(pct) end)
		pane.PctButtons[i] = b
	end
	-- Custom %: labelled, and lit gold (label + glow behind the box) whenever the tip uses a % you typed (1.2, user).
	local customLabel = tabs:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	customLabel:SetPoint("LEFT", #QUICK_PCTS * 48 + 14, 0)
	customLabel:SetText("Custom")
	local box = CreateFrame("EditBox", nil, tabs, "InputBoxTemplate")
	box:SetSize(34, 20)
	box:SetPoint("LEFT", customLabel, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	box:SetJustifyH("CENTER")
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then SetPct(tonumber(self:GetText()) or 0, true) end
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	-- Wrapped: the script passes extra arguments, which HighlightText would read as a (bad) start position.
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEnter", function(self)
		ButtonTooltip(self, "Custom tip %", "Click and type any %, e.g. 12. It is remembered like the buttons.")
	end)
	box:SetScript("OnLeave", GameTooltip_Hide)
	local glow = tabs:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", box, "TOPLEFT", -8, 4)
	glow:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 4, -4)
	glow:SetColorTexture(1, 0.82, 0, 0.25)
	glow:Hide()
	local pctSign = tabs:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	pctSign:SetPoint("LEFT", box, "RIGHT", 4, 0)
	pctSign:SetText("%")
	pane.PctBox, pane.CustomLabel, pane.CustomGlow = box, customLabel, glow

	-- Mats: one line each; total on the header line; Search AH while the AH is open.
	local mats = CreateFrame("Frame", nil, pane)
	mats:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -16)
	mats:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -16)
	mats:SetHeight(20)
	Divider(mats)
	local matsLabel = mats:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	matsLabel:SetPoint("TOPLEFT")
	matsLabel:SetText("Mats")
	pane.MatsTotal = mats:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	pane.MatsTotal:SetPoint("TOPRIGHT")
	local search = CreateFrame("Button", nil, mats, "UIPanelButtonTemplate")
	search:SetSize(90, 20)
	search:SetPoint("LEFT", matsLabel, "RIGHT", 10, 0)
	search:SetText("Search AH")
	search:SetMotionScriptsWhileDisabled(true)
	search:SetScript("OnClick", function()
		local missing = MissingMats()
		if #missing == 0 then return ns.Print("you have all the mats") end
		local ok, what = Price.SearchAH(missing)
		if not ok then ns.Print("search failed: " .. (what or "?")) elseif not Price.HasAuctionator() then ns.Print(what) end
	end)
	search:SetScript("OnEnter", function(self)
		local _, missingLines = MissingMats()
		if #missingLines == 0 then
			ButtonTooltip(self, "Search AH", "You have all the mats.")
		elseif Price.HasAuctionator() then
			ButtonTooltip(self, "Search AH", "Lists what you still need in Auctionator's Shopping tab:", unpack(missingLines))
		else
			ButtonTooltip(self, "Search AH", "Puts the first mat you still need in the AH search box (press Enter):",
				unpack(missingLines))
		end
	end)
	search:SetScript("OnLeave", GameTooltip_Hide)
	search:Hide()
	pane.SearchAH = search
	pane.MatRows = {}
	for i = 1, MAX_MATS do pane.MatRows[i] = CreateMatRow(mats, i) end
	pane.ToBuyLabel = mats:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.ToBuyLabel:SetTextColor(unpack(SOFT))
	pane.ToBuyLabel:SetText("Still to buy")
	pane.ToBuy = mats:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.OldNote = mats:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	pane.OldNote:SetJustifyH("LEFT")
	pane.OldNote:SetText(("|cffff2020Some AH prices are %d+ days old: open the AH to re-check, or right-click a mat.|r")
		:format(AGE_RED_DAYS))
	pane.Mats = mats

	-- Advert: the message in a box, the channel buttons right under it.
	local ask = CreateFrame("Frame", nil, pane)
	ask:SetPoint("TOPLEFT", mats, "BOTTOMLEFT", 0, -16)
	ask:SetPoint("TOPRIGHT", mats, "BOTTOMRIGHT", 0, -16)
	ask:SetHeight(80)
	Divider(ask)
	local askLabel = ask:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	askLabel:SetPoint("TOPLEFT")
	askLabel:SetText("Ask for an enchanter")
	local messageBox = CreateFrame("Frame", nil, ask, "BackdropTemplate")
	messageBox:SetPoint("TOPLEFT", 0, -18)
	messageBox:SetPoint("TOPRIGHT", 0, -18)
	messageBox:SetHeight(40)
	messageBox:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	messageBox:SetBackdropColor(0, 0, 0, 0.45)
	messageBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
	pane.Message = messageBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.Message:SetPoint("TOPLEFT", 8, -7)
	pane.Message:SetPoint("TOPRIGHT", -8, -7)
	pane.Message:SetJustifyH("LEFT")
	pane.MessageBox = messageBox
	pane.AdButtons = {}
	pane.AdNone = ask:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pane.AdNone:SetTextColor(unpack(SOFT))
	pane.AdNone:SetPoint("TOPLEFT", messageBox, "BOTTOMLEFT", 2, -8)
	pane.AdNone:SetText("Tick channels in /gratuity options to get Advertise buttons.")
	pane.Ask = ask

	pane:SetScript("OnShow", function()
		pane.ticker = C_Timer.NewTicker(30, Detail.Update) -- price age
		Detail.Update()
	end)
	pane:SetScript("OnHide", function()
		if pane.ticker then
			pane.ticker:Cancel()
			pane.ticker = nil
		end
	end)
	Price.OnUpdate(Detail.Update)
	pane:RegisterEvent("BAG_UPDATE_DELAYED") -- "have" and Search AH
	pane:RegisterEvent("AUCTION_HOUSE_SHOW")
	pane:RegisterEvent("AUCTION_HOUSE_CLOSED")
	pane:RegisterEvent("CHANNEL_UI_UPDATE") -- channel joined or left
	pane:RegisterEvent("GROUP_ROSTER_UPDATE")
	pane:RegisterEvent("PLAYER_GUILD_UPDATE")
	-- Next frame: at AUCTION_HOUSE_CLOSED the AH frame may still report shown.
	pane:SetScript("OnEvent", function() C_Timer.After(0, Detail.Update) end)
	return pane
end

-- Shows an enchant in the pane (the list calls this when a row is selected).
function Detail.Show(spellID)
	if not pane then return end
	local name, icon, slot = Recipes.Info(spellID)
	local mats = Recipes.Mats(spellID)
	if not mats then return ns.Print(("%s (%d): no reagents known"):format(name or "?", spellID)) end
	current.spellID, current.name, current.mats = spellID, name, mats
	pane.Header.Icon:SetTexture(icon)
	pane.Header.Name:SetText(name or ("spell " .. spellID))
	pane.Header.Sub:SetText(slot or "")
	Detail.Update()
	ns.AH.CheckMats(mats) -- 2.0: at the AH, re-check this enchant's mats (only those not priced in the last 10 minutes)
	-- Mat names can arrive after the first draw.
	for _, m in ipairs(mats) do
		local item = Item:CreateFromItemID(m[1])
		if not item:IsItemEmpty() then
			item:ContinueOnItemLoad(function()
				if current.spellID == spellID then Detail.Update() end
			end)
		end
	end
end

function Detail.Current()
	return current.spellID
end
