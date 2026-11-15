-- Gratuity: namespace, saved settings, login checks.
local addonName, ns = ...

ns.callerID = addonName -- Auctionator API caller ID
local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.version = GetMetadata and GetMetadata(addonName, "Version") or "?"

local PREFIX = "|cff66ccffGratuity|r: "
function ns.Print(...)
	print(PREFIX .. strjoin(" ", tostringall(...)))
end

local DEFAULTS = {
	tipPct = 10, -- the window remembers the last % picked (user 2026-11-14: default 10)
	rounding = "smart", -- smart | none | 1s | 10s | 1g (Tip.Compute)
	minTip = 0, -- copper
	template = "LF {link}, my mats, tipping {pct}% of AH cost ({tip})", -- 2.1: {link} = the clickable enchanting link
	channels = { TradeLocal = true }, -- where to advertise, by channel name (or SAY / PARTY / GUILD); user, 2026-11-13
	ageWarnHours = 6, -- price age colours: white below, amber up to ageBadHours, red above
	ageBadHours = 24,
	manualPrices = {}, -- [itemID] = copper: your own price for a mat (right-click it in the detail window)
	lastPriceUpdate = nil, -- time() of the last Auctionator price update we saw
	minimap = { hide = false }, -- LibDBIcon's own table (position, hidden)
	listSort = "slot", -- list window order: slot | name | cheap | dear
	openFromLinks = true, -- 1.2: clicking an enchant link in chat opens Gratuity on it
	-- 2.0: own prices (AH.lua, Vendor.lua)
	ahPrices = {}, -- [itemID] = { p = copper or false (searched, none listed), t = time() }
	vendorPrices = {}, -- [itemID] = copper each, recorded at merchants
	lastFullCheck = nil, -- time() the last "Check mat prices" started
	lastOwnPrice = nil, -- time() of the newest own AH price
	autoCheck = true, -- at the AH, re-check the selected enchant's mats
	useAuctionator = true, -- use Auctionator's prices when they are newer (if it is installed)
}

local function ApplyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = type(v) == "table" and CopyTable(v) or v
		end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		GratuityDB = GratuityDB or {}
		ns.db = GratuityDB
		ApplyDefaults(ns.db, DEFAULTS)
		-- 1.0.2: channels ticked while testing (0.x) are reset once to the release default, whatever they were
		-- (1.0.0 only reset a Say-only choice, user 2026-11-14). What you tick after this is kept.
		if not ns.db.migrated102 then
			ns.db.channels = CopyTable(DEFAULTS.channels)
			ns.db.migrated102 = true
		end
		-- 1.1.0: default tip 10 % with sensible rounding (user 2026-11-14); set once, later changes are kept.
		if not ns.db.migrated110 then
			ns.db.tipPct, ns.db.rounding = DEFAULTS.tipPct, DEFAULTS.rounding
			ns.db.migrated110 = true
		end
		-- 2.1.0: the default message posts the enchant as a link (user, 2026-11-15). A template still equal to the old
		-- default switches once; one you wrote yourself is kept.
		if not ns.db.migrated210 then
			if ns.db.template == "LF {enchant}, my mats, tipping {pct}% of AH cost ({tip})" then
				ns.db.template = DEFAULTS.template
			end
			ns.db.migrated210 = true
		end
		ns.db.migrated100, ns.db.icon = nil, nil -- retired settings
		ns.Launcher.Init()
	elseif event == "PLAYER_LOGIN" then
		ns.Price.Init()
		local version, build = GetBuildInfo()
		local client = version .. "." .. build
		if client ~= ns.DataBuild then
			ns.Print(("enchant list is from build %s, the client is %s. /gratuity check shows changed mats; "
				.. "rerun tools/gen_enchant_data.py to update."):format(ns.DataBuild, client))
		end
	end
end)
