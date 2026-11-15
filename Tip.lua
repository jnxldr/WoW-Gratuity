-- Tip maths and the advert message. No UI here.
local _, ns = ...
local Tip = {}
ns.Tip = Tip

Tip.ROUNDING = { none = 1, ["1s"] = 100, ["10s"] = 1000, ["1g"] = 10000 } -- round the tip up to this many copper

-- Mats cost over all reagents (owned or not): total copper, priced count, reagent count, oldest AH age in days.
-- Each line: { itemID, count, unit, source, ageDays, cost, ageSeconds (own checks), origin } (see Price.Unit).
function Tip.Base(mats)
	local total, priced, oldest, lines = 0, 0, nil, {}
	for i, m in ipairs(mats) do
		local unit, source, age, secs, origin = ns.Price.Unit(m[1])
		local cost = unit and unit * m[2]
		if cost then
			total, priced = total + cost, priced + 1
			if age and (not oldest or age > oldest) then oldest = age end
		end
		lines[i] = { m[1], m[2], unit, source, age, cost, secs, origin }
	end
	return total, priced, #mats, oldest, lines
end

-- "smart" (default from 1.1, user 2026-11-14): round up to a coin a person would hand over, with the step growing with
-- the tip so it never swallows the % (1.1.1: below 10s the step was 1s, so 10 % and 15 % of a 9c enchant were both 1s).
local function SmartStep(raw)
	if raw >= 100000 then return 10000 end -- 10g and up: whole gold
	if raw >= 10000 then return 1000 end -- 1g to 10g: 10s
	if raw >= 1000 then return 100 end -- 10s to 1g: whole silver
	if raw >= 100 then return 10 end -- 1s to 10s: 10c
	return 1 -- under 1s: whole copper
end

function Tip.Compute(base, pct, rounding, minTip)
	local raw = base * pct / 100
	local step = rounding == "smart" and SmartStep(raw) or Tip.ROUNDING[rounding] or 1
	local tip = raw > 0 and math.ceil(raw / step - 1e-9) * step or 0
	if minTip and tip < minTip then tip = minTip end
	return tip
end

-- Money with coin icons for the UI and printed lines. The global GetCoinTextureString is nil on Forever (2026-11-13);
-- GetMoneyString is what Auctionator uses there, C_CurrencyInfo.GetCoinTextureString the fallback.
function Tip.MoneyIcons(copper)
	copper = floor(copper + 0.5)
	if GetMoneyString then return GetMoneyString(copper, true) end
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
	return Tip.MoneyText(copper)
end

-- Plain money text for chat ("1g 20s 5c").
function Tip.MoneyText(copper)
	copper = floor(copper + 0.5)
	local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

-- Fills {enchant} {mats} {pct} {tip} {base} {age}; unknown tokens stay as typed. Trimmed to 255 characters.
function Tip.Message(template, fields)
	local msg = template:gsub("{(%w+)}", function(key)
		local v = fields[key]
		return v ~= nil and tostring(v) or nil
	end)
	if #msg > 255 then return msg:sub(1, 255), true end
	return msg, false
end
