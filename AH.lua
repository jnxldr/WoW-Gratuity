-- Own AH prices (2.0, no Auctionator needed). On Forever, browse searches sent from add-on code are answered in ~0.1 s,
-- with or without a click; the AH has one request queue shared with the AH window and Auctionator, so we send one
-- search at a time and only when it is free.
-- Three ways prices come in:
--   1. our own searches: Blizzard's own browse query for one mat's exact name, minPrice of that item = cheapest unit
--   2. any browse results someone else asked for (Auctionator's scans, your own searches in the AH window)
--   3. the commodity list the AH window shows when you click a mat to buy it (unit price of the cheapest auction)
local _, ns = ...
local AH = {}
ns.AH = AH

local CAH = C_AuctionHouse
local GetItemNameByID = C_Item and C_Item.GetItemNameByID or function(id) return (GetItemInfo(id)) end
local RequestItem = C_Item and C_Item.RequestLoadItemDataByID or function() end

local ANSWER_TIMEOUT = 10 -- seconds to wait for an answer before moving on
local FRESH_SECONDS = 10 * 60 -- the automatic re-check skips mats priced this recently
local NAME_TRIES = 20 -- passes (0.25 s each) to wait for an uncached item name before skipping the mat

-- Blizzard's own query for the AH search box (the argument its search box passes to SendBrowseQuery):
-- sorts Price then Name, levels 0, its default filters. Built fresh for each search.
local function Query(name)
	return {
		searchString = name,
		sorts = { { sortOrder = 0, reverseSort = false }, { sortOrder = 1, reverseSort = false } },
		minLevel = 0,
		maxLevel = 0,
		filters = { 6, 7, 8, 9, 10, 11, 12 },
	}
end

local isMat -- [itemID] = true for every reagent in the enchant list
local function Mats()
	if not isMat then
		isMat = {}
		for _, entry in pairs(ns.Enchants) do
			for _, m in ipairs(entry[2]) do isMat[m[1]] = true end
		end
	end
	return isMat
end

local queue, queued = {}, {} -- itemIDs waiting for a search; [itemID] = { tries = n }
local inflight -- { itemID, sentAt } while our search is out
local run -- the full check: { startedAt, total, done, priced, unlisted, failed, unknown = { names } }
local ticker
local listeners = {}
local changed = false

-- fn(state) is called when the full check starts, moves on or ends (state = AH.Progress()).
function AH.OnProgress(fn)
	listeners[#listeners + 1] = fn
end

local function Progress()
	for _, fn in ipairs(listeners) do pcall(fn, AH.Progress()) end
end

local function FlushChanged()
	if changed then
		changed = false
		ns.Price.Notify()
	end
end

-- price = copper, or false = searched and none listed.
local function Record(itemID, price)
	if not Mats()[itemID] then return end
	local now = time()
	ns.db.ahPrices[itemID] = { p = price, t = now }
	if price then ns.db.lastOwnPrice = now end
	changed = true
end

-- Cheapest minPrice per mat in a list of browse results (one item can come back under several item keys).
local function RecordBrowse(results)
	local best = {}
	for _, r in ipairs(results or {}) do
		local id = r.itemKey and r.itemKey.itemID
		local p = tonumber(r.minPrice)
		if id and p and p > 0 and Mats()[id] and (not best[id] or p < best[id]) then best[id] = p end
	end
	for id, p in pairs(best) do Record(id, p) end
	return best
end

function AH.IsOpen()
	return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

-- True while you are on an item's buy view in the AH window: the automatic re-check waits so it can't change what you see.
local function Busy()
	local f = AuctionHouseFrame
	return f and ((f.CommoditiesBuyFrame and f.CommoditiesBuyFrame:IsShown())
		or (f.ItemBuyFrame and f.ItemBuyFrame:IsShown())) or false
end

local function Finish()
	if not run then return end
	local r = run
	run = nil
	ns.db.lastFullCheck = r.startedAt
	local line = ("checked %d mats in %d s: %d priced"):format(r.total, time() - r.startedAt, r.priced)
	local function Add(list, what)
		if #list == 0 then return end
		table.sort(list)
		local shown = { unpack(list, 1, math.min(#list, 8)) }
		line = line .. (", %d %s: %s%s"):format(#list, what, table.concat(shown, ", "), #list > #shown and ", ..." or "")
	end
	Add(r.unlisted, "not on the AH")
	Add(r.failed, "not checked (no answer from the AH)")
	Add(r.unknown, "not checked (the client has no such item)")
	ns.Print(line)
	Progress()
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local Pump

-- price: copper, false (searched, none listed) or nil (not checked; noName = the client never gave the item's name)
local function Done(itemID, price, noName)
	if run and queued[itemID] and queued[itemID].full then
		run.done = run.done + 1
		if price then run.priced = run.priced + 1
		else
			local list = noName and run.unknown or price == false and run.unlisted or run.failed
			list[#list + 1] = GetItemNameByID(itemID) or ("item " .. itemID)
		end
	end
	queued[itemID] = nil
	if run and #queue == 0 and not inflight then Finish() else Progress() end
end

-- Sends the next search if the AH is open and its queue is free. Called on a short ticker while work is waiting.
Pump = function()
	if inflight and GetTime() - inflight.sentAt > ANSWER_TIMEOUT then
		local id = inflight.itemID
		inflight = nil
		Done(id, nil) -- no answer: neither priced nor "not listed"
	end
	if inflight then return end
	if #queue == 0 then
		StopTicker()
		if run then Finish() end
		return
	end
	if not AH.IsOpen() or not CAH.IsThrottledMessageSystemReady() then return end
	for i, itemID in ipairs(queue) do
		local q = queued[itemID]
		local price = ns.db.ahPrices[itemID]
		if run and q.full and price and price.t >= run.startedAt then
			-- already came back with an earlier search of this check (e.g. "Essence" results list several)
			table.remove(queue, i)
			Done(itemID, price.p)
			return Pump()
		end
		if q.full or not Busy() then
			local name = GetItemNameByID(itemID)
			if name then
				table.remove(queue, i)
				inflight = { itemID = itemID, sentAt = GetTime() }
				CAH.SendBrowseQuery(Query(name))
				return
			end
			q.tries = (q.tries or 0) + 1
			RequestItem(itemID)
			if q.tries >= NAME_TRIES then
				table.remove(queue, i)
				Done(itemID, nil, true)
				return
			end
		end
	end
end

local function StartTicker()
	if not ticker then ticker = C_Timer.NewTicker(0.25, Pump) end
end

local function Enqueue(itemID, full)
	local q = queued[itemID]
	if q then
		q.full = q.full or full
		return
	end
	queued[itemID] = { full = full }
	queue[#queue + 1] = itemID
end

-- Automatic re-check of one enchant's mats while the AH is open (skips mats priced in the last 10 minutes).
function AH.CheckMats(mats)
	if not (ns.db.autoCheck and AH.IsOpen() and mats) then return end
	local now = time()
	for _, m in ipairs(mats) do
		local id = m[1]
		local rec = ns.db.ahPrices[id]
		local vendor = ns.db.vendorPrices[id]
		if Mats()[id] and not vendor and not ns.db.manualPrices[id] and not (rec and now - rec.t < FRESH_SECONDS) then
			Enqueue(id, false)
		end
	end
	if #queue > 0 then
		StartTicker()
		Pump()
	end
end

-- The full check (button on the AH window): every mat of every enchant, vendor-bought ones excepted.
function AH.StartFullCheck()
	if run then return end
	if not AH.IsOpen() then return ns.Print("open the auction house first") end
	local ids = {}
	for id in pairs(Mats()) do
		if not ns.db.vendorPrices[id] then ids[#ids + 1] = id end
	end
	table.sort(ids, function(a, b) return (GetItemNameByID(a) or "") < (GetItemNameByID(b) or "") end)
	run = { startedAt = time(), total = #ids, done = 0, priced = 0, unlisted = {}, failed = {}, unknown = {} }
	for _, id in ipairs(ids) do Enqueue(id, true) end
	Progress()
	StartTicker()
	Pump()
end

function AH.StopFullCheck()
	if not run then return end
	for i = #queue, 1, -1 do
		local id = queue[i]
		if queued[id].full then
			table.remove(queue, i)
			queued[id] = nil
		end
	end
	ns.Print(("price check stopped after %d of %d mats"):format(run.done, run.total))
	run = nil
	Progress()
end

-- nil when no full check runs, else { done, total }.
function AH.Progress()
	return run and { done = run.done, total = run.total } or nil
end

function AH.MatCount()
	local n = 0
	for id in pairs(Mats()) do
		if not ns.db.vendorPrices[id] then n = n + 1 end
	end
	return n
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
events:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
events:SetScript("OnEvent", function(_, event, arg1)
	if not ns.db then return end
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		local found = RecordBrowse(CAH.GetBrowseResults())
		if inflight then -- the answer to our search (one request at a time, and we only send when the queue is free)
			local id = inflight.itemID
			inflight = nil
			if not found[id] then Record(id, false) end
			local rec = ns.db.ahPrices[id]
			Done(id, rec and rec.p)
		end
		FlushChanged()
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		RecordBrowse(arg1) -- the next page of a big search (Auctionator's full scan)
		FlushChanged()
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		local ok, info = pcall(CAH.GetCommoditySearchResultInfo, arg1, 1)
		local p = ok and info and tonumber(info.unitPrice)
		if p and p > 0 then
			Record(arg1, p)
			FlushChanged()
		end
	elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		if #queue > 0 then Pump() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		C_Timer.After(0, function()
			AH.CreateButton()
			if ns.Detail and ns.Detail.Current() then AH.CheckMats(ns.Recipes.Mats(ns.Detail.Current())) end
		end)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if run then AH.StopFullCheck() end
		wipe(queue)
		wipe(queued)
		inflight = nil
		StopTicker()
	end
end)

-- "Check mat prices" button under the AH window, to the right of its tabs.
local button
function AH.CreateButton()
	if button or not AuctionHouseFrame then return end
	button = CreateFrame("Button", "GratuityAHButton", AuctionHouseFrame, "UIPanelButtonTemplate")
	button:SetSize(200, 24)
	button:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
	local function Label()
		local p = AH.Progress()
		if p then
			button:SetText(("Checking %d / %d (stop)"):format(p.done, p.total))
		else
			button:SetText("|T" .. ns.ICON .. ":16:16|t Check mat prices")
		end
	end
	button:SetScript("OnClick", function()
		if AH.Progress() then AH.StopFullCheck() else AH.StartFullCheck() end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Gratuity: check mat prices", 1, 1, 1)
		GameTooltip:AddLine(("Looks up the AH price of all %d enchanting mats, one search at a time (about a minute). "
			.. "Click again to stop."):format(AH.MatCount()), nil, nil, nil, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine((ns.Price.AgeLine()))
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	AH.OnProgress(Label)
	Label()
end
