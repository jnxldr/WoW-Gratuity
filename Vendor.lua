-- Vendor prices (2.0): when a merchant window opens, mats sold for plain money in unlimited stock are recorded
-- (ns.db.vendorPrices[itemID] = copper each). Price.Unit uses them before any AH price, as Auctionator's craft total does.
local _, ns = ...

-- Blizzard's Forever merchant frame (Vanilla variant) uses the global; newer clients only have C_MerchantFrame.GetItemInfo.
local function ItemInfo(index)
	if GetMerchantItemInfo then
		local _, _, price, stack, available, _, _, extendedCost = GetMerchantItemInfo(index)
		return price, stack, available, extendedCost
	end
	local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo(index)
	if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
end

local function Scan()
	if not (ns.db and ns.Enchants) then return end
	local mats = {}
	for _, entry in pairs(ns.Enchants) do
		for _, m in ipairs(entry[2]) do mats[m[1]] = true end
	end
	local found = 0
	for i = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(i)
		if itemID and mats[itemID] then
			local price, stack, available, extendedCost = ItemInfo(i)
			if price and price > 0 and available == -1 and not extendedCost then
				local each = math.ceil(price / math.max(stack or 1, 1))
				if ns.db.vendorPrices[itemID] ~= each then
					ns.db.vendorPrices[itemID] = each
					found = found + 1
				end
			end
		end
	end
	if found > 0 then ns.Price.Notify() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:SetScript("OnEvent", function() C_Timer.After(0, Scan) end)
