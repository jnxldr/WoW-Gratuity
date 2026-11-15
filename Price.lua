-- Price provider. 2.0: Gratuity's own prices first (AH.lua: AH searches, Vendor.lua: merchants), Auctionator only as an
-- optional fallback. The only file that talks to Auctionator (stable API v1, plus one read-only saved value).
local _, ns = ...
local Price = {}
ns.Price = Price

-- Calls Auctionator.API.v1.<name>(callerID, ...); nil if Auctionator or the function is missing or it errors.
local function API(name, ...)
	local v1 = Auctionator and Auctionator.API and Auctionator.API.v1
	local fn = v1 and v1[name]
	if not fn then return nil end
	local ok, result = pcall(fn, ns.callerID, ...)
	if ok then return result end
end

local listeners = {}

-- fn() is called after prices change (e.g. to refresh a window).
function Price.OnUpdate(fn)
	listeners[#listeners + 1] = fn
end

-- Called by AH.lua and Vendor.lua when they record prices, and on Auctionator's updates.
function Price.Notify()
	for _, fn in ipairs(listeners) do pcall(fn) end
end

function Price.HasAuctionator()
	return (Auctionator and Auctionator.API and Auctionator.API.v1) ~= nil
end

function Price.Init()
	-- Fires after a scan and after ordinary AH searches (modern and legacy AH both have it). Nothing without Auctionator.
	API("RegisterForDBUpdate", function()
		ns.db.lastPriceUpdate = time()
		Price.Notify()
	end)
end

local function UseAuctionator()
	return ns.db.useAuctionator ~= false
end

-- Unit price in copper, source, AH age in whole days, seconds since our own check (nil for Auctionator's), origin.
-- source: "manual" | "vendor" | "ah" | "none" (searched, nothing listed) | nil (no price at all).
-- origin: "own" (Gratuity's AH search or merchant) | "auctionator".
-- Order as Auctionator's own "To craft" total: your price, vendor (merchant price, unlimited stock only), then AH. Between
-- Gratuity's AH price and Auctionator's, the newer wins (age in whole days, a tie goes to ours).
function Price.Unit(itemID)
	local manual = ns.db.manualPrices[itemID]
	if manual then return manual, "manual" end
	local vendor = ns.db.vendorPrices[itemID]
	if vendor then return vendor, "vendor", nil, nil, "own" end
	if UseAuctionator() then
		vendor = API("GetVendorPriceByItemID", itemID)
		if vendor then return math.ceil(vendor), "vendor", nil, nil, "auctionator" end
	end
	local own = ns.db.ahPrices[itemID]
	local ownSecs = own and math.max(time() - own.t, 0)
	local ownDays = ownSecs and floor(ownSecs / 86400)
	local theirs, theirDays
	if UseAuctionator() then
		theirs = API("GetAuctionPriceByItemID", itemID)
		if theirs then theirDays = API("GetAuctionAgeByItemID", itemID) end
	end
	-- Auctionator's age is nil when it is over 21 days, so it only wins on a known, strictly newer day.
	local preferTheirs = theirs and (not own or (theirDays ~= nil and theirDays < ownDays))
	if preferTheirs then return theirs, "ah", theirDays, nil, "auctionator" end
	if own then
		if own.p then return own.p, "ah", ownDays, ownSecs, "own" end
		return nil, "none", ownDays, ownSecs, "own"
	end
	return nil
end

-- True while the auction house is open (modern or legacy frame), as Auctionator's own search check.
function Price.AHOpen()
	return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown()) or false
end

-- terms = { { name, quantity }, ... }. With Auctionator: lists them in its Shopping tab (exact names). Without: puts the
-- first name in the AH window's own search box, for you to press Enter (we don't press Search for you: that is the AH
-- window's own code). Returns true + what happened, or false + why not.
function Price.SearchAH(terms)
	if not Price.AHOpen() then return false, "open the auction house first" end
	local v1 = Auctionator and Auctionator.API and Auctionator.API.v1
	if v1 and v1.MultiSearchAdvanced then
		local searchTerms = {}
		for i, t in ipairs(terms) do
			searchTerms[i] = { searchString = t[1], isExact = true, quantity = t[2] }
		end
		local ok, err = pcall(v1.MultiSearchAdvanced, ns.callerID, searchTerms)
		return ok, not ok and tostring(err) or "listed in Auctionator's Shopping tab"
	end
	local box = AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox
	if not box then return false, "the AH search box wasn't found" end
	box:SetText(terms[1][1])
	box:SetFocus()
	return true, ("'%s' is in the AH search box: press Enter"):format(terms[1][1])
end

-- Seconds since the last full scan or check started (Auctionator's scan or Gratuity's "Check mat prices"; nil if none)
-- and since the newest price came in (ours, or an Auctionator update; nil if never).
-- Forever uses the modern AH (checked 2026-11-13): Auctionator's auto/summary scan saves TimeOfLastBrowseScan, its
-- replicate scan TimeOfLastReplicateScan (legacy AH: TimeOfLastGetAllScan). All are set when a scan starts; newest wins.
local SCAN_KEYS = { "TimeOfLastBrowseScan", "TimeOfLastReplicateScan", "TimeOfLastGetAllScan" }

local function Newest(...)
	local best
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if type(t) == "number" and t > 0 and (not best or t > best) then best = t end
	end
	return best
end

function Price.Ages()
	local now = time()
	local saved = UseAuctionator() and type(AUCTIONATOR_SAVEDVARS) == "table" and AUCTIONATOR_SAVEDVARS or {}
	local newestScan = Newest(ns.db.lastFullCheck, saved[SCAN_KEYS[1]], saved[SCAN_KEYS[2]], saved[SCAN_KEYS[3]])
	local newestUpdate = Newest(ns.db.lastOwnPrice, UseAuctionator() and ns.db.lastPriceUpdate or nil)
	return newestScan and now - newestScan or nil, newestUpdate and now - newestUpdate or nil
end

function Price.FormatDuration(seconds)
	if seconds < 60 then return "under 1 min" end
	local d, h, m = floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60)
	if d > 0 then return ("%d d %d h"):format(d, h) end
	if h > 0 then return ("%d h %d min"):format(h, m) end
	return ("%d min"):format(m)
end

-- "AH prices: full check 2 h 40 min ago · newest 25 min ago", coloured by the newest of the two.
-- Second return: the newest age in seconds (nil = never).
function Price.AgeLine()
	local fullScan, update = Price.Ages()
	local parts = {}
	if fullScan then parts[#parts + 1] = "full check " .. Price.FormatDuration(fullScan) .. " ago" end
	if update then parts[#parts + 1] = "newest " .. Price.FormatDuration(update) .. " ago" end
	local newest = fullScan and update and math.min(fullScan, update) or fullScan or update
	local text = #parts > 0 and table.concat(parts, " · ") or "none yet: Check mat prices at the AH"
	return Price.AgeColor(newest):WrapTextInColorCode("AH prices: " .. text), newest
end

-- Colour for a price age in seconds: white while fresh, orange from ageWarnHours, red from ageBadHours or unknown.
function Price.AgeColor(seconds)
	if seconds and seconds < ns.db.ageWarnHours * 3600 then return WHITE_FONT_COLOR end
	if seconds and seconds < ns.db.ageBadHours * 3600 then return ORANGE_FONT_COLOR or YELLOW_FONT_COLOR end
	return RED_FONT_COLOR
end

-- "prices 6 min old", coloured by age (the tip block in the window).
function Price.AgeShortColored()
	local _, newest = Price.AgeLine()
	return Price.AgeColor(newest):WrapTextInColorCode(Price.AgeShort())
end

-- Short form for the chat message token {age}: "prices 3 h old".
function Price.AgeShort()
	local _, newest = Price.AgeLine()
	if not newest then return "prices unknown age" end
	return "prices " .. Price.FormatDuration(newest) .. " old"
end
