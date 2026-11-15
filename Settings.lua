-- Settings panel in Options > AddOns (Blizzard Settings, canvas layout, as EllesmereUI and Wowhead use on Forever).
local addonName, ns = ...
local Settings_ = {}
ns.Settings = Settings_

local DEFAULT_TEMPLATE = "LF {link}, my mats, tipping {tip} ({pct}% of AH cost)" -- same as Core.lua's default
local ROUNDING = { { "smart", "Sensible (step grows with the tip)" }, { "none", "No rounding" }, { "1s", "Round up to 1s" },
	{ "10s", "Round up to 10s" }, { "1g", "Round up to 1g" } }

local panel = CreateFrame("Frame")
panel.name = addonName
-- 2.0: everything sits in a scroll frame (the channel list grows with your joined channels, user 2026-11-15: cut off)
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", -28, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(600, 700)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
local lower = CreateFrame("Frame", nil, content) -- the sections under the channel list, moved down as it grows
lower:SetHeight(176)
local category
local refreshers = {} -- functions that load the saved values into the controls (on show)

local function Changed()
	if ns.List then ns.List.Refresh(true) end
	if ns.Detail then ns.Detail.Update() end
end

-- Secondary text: the stock disabled grey is hard to read on the panel (user), so a light grey like the main window's.
local function Hint(parent, x, y, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetTextColor(0.82, 0.82, 0.82)
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function Heading(text, y, parent)
	local fs = (parent or content):CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
	return fs
end

local function Note(text, anchor, x, y)
	local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetTextColor(0.82, 0.82, 0.82)
	fs:SetPoint("LEFT", anchor, "RIGHT", x or 8, y or 0)
	fs:SetText(text)
	return fs
end

-- Numeric box bound to ns.db[key]; toDb/fromDb convert between shown and saved values.
local function NumberBox(label, y, key, width, fromDb, toDb, min, max)
	local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", 24, y)
	fs:SetWidth(220)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)
	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	box:SetSize(width or 50, 20)
	box:SetPoint("LEFT", fs, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(5)
	box:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then return end
		local v = tonumber(self:GetText())
		if v and v >= (min or 0) and v <= (max or 99999) then
			ns.db[key] = toDb and toDb(v) or v
			Changed()
		end
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEditFocusLost", function(self) -- show the saved value again if the text was invalid
		local v = ns.db[key]
		self:SetText(tostring(fromDb and fromDb(v) or v))
	end)
	refreshers[#refreshers + 1] = function()
		local v = ns.db[key]
		box:SetText(tostring(fromDb and fromDb(v) or v))
	end
	return box
end

local function CheckBox(label, parent, point, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint(unpack(point))
	local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetText(label)
	cb.Label = fs
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)
	return cb
end

local function Build()
	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Gratuity")
	local version = Hint(content, 0, 0, ns.version)
	version:ClearAllPoints()
	version:SetPoint("LEFT", title, "RIGHT", 8, 0)

	Heading("Tip", -50)
	local pct = NumberBox("Tip %", -74, "tipPct", 50, nil, nil, 0, 1000)
	Note("the % buttons in the window change it too", pct)
	local minTip = NumberBox("Minimum tip (silver)", -100, "minTip", 50,
		function(c) return floor(c / 100) end, function(s) return s * 100 end, 0, 99999)
	Note("0 = none", minTip)
	local roundLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	roundLabel:SetPoint("TOPLEFT", 24, -128)
	roundLabel:SetText("Rounding")
	local rounding = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	rounding:SetWidth(170)
	rounding:SetPoint("TOPLEFT", 254, -122)
	rounding:SetupMenu(function(_, root)
		for _, r in ipairs(ROUNDING) do
			root:CreateRadio(r[2], function() return ns.db.rounding == r[1] end, function()
				ns.db.rounding = r[1]
				Changed()
			end)
		end
	end)
	refreshers[#refreshers + 1] = function() rounding:GenerateMenu() end

	Heading("Price age (colour of the age line)", -164)
	local warn = NumberBox("Orange after (hours)", -188, "ageWarnHours", 40, nil, nil, 1, 999)
	Note("white before", warn)
	local bad = NumberBox("Red after (hours)", -214, "ageBadHours", 40, nil, nil, 1, 999)
	Note("since the last price check", bad)

	Heading("Message", -252)
	local template = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	template:SetSize(520, 20)
	template:SetPoint("TOPLEFT", 30, -274)
	template:SetAutoFocus(false)
	template:SetMaxLetters(255)
	template:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			ns.db.template = self:GetText()
			Changed()
		end
	end)
	template:SetScript("OnEnterPressed", template.ClearFocus)
	template:SetScript("OnEscapePressed", template.ClearFocus)
	refreshers[#refreshers + 1] = function() template:SetText(ns.db.template) end
	local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	reset:SetSize(80, 22)
	reset:SetPoint("LEFT", template, "RIGHT", 8, 0)
	reset:SetText("Default")
	reset:SetScript("OnClick", function()
		ns.db.template = DEFAULT_TEMPLATE
		template:SetText(DEFAULT_TEMPLATE)
		Changed()
	end)
	Hint(content, 24, -298, "{link} = clickable enchant link, {enchant} = its name; also {mats} {pct} {tip} {base} {age}.")

	Heading("Advertise in (one button each in the Gratuity window)", -326)
	local channelBoxes = {}
	refreshers[#refreshers + 1] = function()
		for _, cb in ipairs(channelBoxes) do cb:Hide() end
		for i, ch in ipairs(ns.Advertise.Choices()) do
			local cb = channelBoxes[i]
			if not cb then
				local col, row = (i - 1) % 3, floor((i - 1) / 3)
				cb = CheckBox("", content, { "TOPLEFT", 20 + col * 190, -348 - row * 26 }, function() end)
				channelBoxes[i] = cb
			end
			cb.Label:SetText(ch.label)
			cb:SetChecked(ns.db.channels[ch.key] == true)
			cb:SetScript("OnClick", function(self) ns.db.channels[ch.key] = self:GetChecked() or nil end)
			cb:Show()
		end
		local rows = ceil(#ns.Advertise.Choices() / 3)
		local top = -348 - rows * 26 - 14
		lower:SetPoint("TOPLEFT", 0, top)
		lower:SetPoint("TOPRIGHT", 0, top)
		content:SetHeight(348 + rows * 26 + 14 + lower:GetHeight())
	end

	Heading("Buttons", 0, lower)
	local minimap = CheckBox("Show minimap button", lower, { "TOPLEFT", 20, -22 }, function(checked)
		ns.Launcher.SetShown(checked)
	end)
	refreshers[#refreshers + 1] = function() minimap:SetChecked(ns.Launcher.IsShown()) end
	local links = CheckBox("Open Gratuity when I click an enchant link in chat", lower, { "TOPLEFT", 260, -22 },
		function(checked) ns.db.openFromLinks = checked and true or false end)
	refreshers[#refreshers + 1] = function() links:SetChecked(ns.db.openFromLinks) end
	Hint(lower, 24, -50, "Gratuity is also in the add-on button next to the minimap (left-click list, right-click settings).")

	Heading("AH prices", -80, lower)
	local auto = CheckBox("At the AH, check the selected enchant's mats automatically", lower, { "TOPLEFT", 20, -102 },
		function(checked) ns.db.autoCheck = checked and true or false end)
	refreshers[#refreshers + 1] = function() auto:SetChecked(ns.db.autoCheck) end
	local useAuc = CheckBox("Use Auctionator's prices when they are newer", lower, { "TOPLEFT", 20, -128 },
		function(checked)
			ns.db.useAuctionator = checked and true or false
			Changed()
		end)
	refreshers[#refreshers + 1] = function()
		useAuc:SetChecked(ns.db.useAuctionator)
		useAuc:SetEnabled(ns.Price.HasAuctionator())
		useAuc.Label:SetText("Use Auctionator's prices when they are newer"
			.. (ns.Price.HasAuctionator() and "" or " (Auctionator isn't loaded)"))
	end
	Hint(lower, 24, -156, "All mats: the \"Check mat prices\" button under the AH window, or /gratuity prices.")

end

panel:SetScript("OnShow", function()
	if not panel.built then
		Build()
		panel.built = true
	end
	for _, fn in ipairs(refreshers) do fn() end
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
	Settings.RegisterAddOnCategory(category)
end

function Settings_.Open()
	if not category then return ns.Print("no settings panel on this client") end
	if InCombatLockdown() then return ns.Print("settings can't be opened in combat") end
	Settings.OpenToCategory(category:GetID())
end
