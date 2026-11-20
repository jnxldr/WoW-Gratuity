-- Minimap button (LibDBIcon-1.0, embedded in Libs\) and Blizzard's add-on compartment entry (.toc AddonCompartmentFunc*).
-- Both: left-click = enchant list, right-click = settings; tooltip = price age.
local addonName, ns = ...
local Launcher = {}
ns.Launcher = Launcher

-- Gratuity's own icon (gold coin with the enchanting star); same file as ## IconTexture.
local ICON = "Interface\\AddOns\\Gratuity\\Media\\Icon"
ns.ICON = ICON -- also on the AH window's "Check mat prices" button (AH.lua)

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function OnClick(button)
	if button == "RightButton" then
		ns.Settings.Open()
	else
		ns.List.Toggle()
	end
end

local function FillTooltip(tooltip)
	tooltip:AddDoubleLine("Gratuity", ns.version, 1, 0.82, 0, 0.6, 0.6, 0.6)
	tooltip:AddLine((ns.Price.AgeLine()))
	tooltip:AddLine(" ")
	tooltip:AddLine("Left-click: enchant list", 0.6, 0.6, 0.6)
	tooltip:AddLine("Right-click: settings", 0.6, 0.6, 0.6)
end

-- Called from Core at ADDON_LOADED (the saved position is in ns.db.minimap).
function Launcher.Init()
	if not (LDB and DBIcon) then return end
	local object = LDB:NewDataObject(addonName, {
		type = "launcher",
		label = addonName,
		icon = ICON,
		OnClick = function(_, button) OnClick(button) end,
		OnTooltipShow = FillTooltip,
	})
	-- Not DBIcon:AddButtonToCompartment: the .toc entry below is Blizzard's own and stays when the minimap button is hidden.
	DBIcon:Register(addonName, object, ns.db.minimap)
end

function Launcher.IsShown()
	return not ns.db.minimap.hide
end

function Launcher.SetShown(show)
	ns.db.minimap.hide = not show
	if not DBIcon then return end
	if show then DBIcon:Show(addonName) else DBIcon:Hide(addonName) end
end

-- 1.2: a plain left-click on an enchant link in chat (an enchanter's "[Enchanting: ...]" trade link, or a spell link to an
-- enchant) also opens Gratuity on it. A post-hook, so the game's own tooltip still shows; modified clicks (Shift to re-link,
-- Ctrl, Alt) are left alone. Off with /gratuity options.
hooksecurefunc("SetItemRef", function(link, _, button)
	if not (ns.db and ns.db.openFromLinks) then return end
	if (button and button ~= "LeftButton") or IsModifiedClick() then return end
	local kind, id = (link or ""):match("^(%a+):(%d+)")
	if kind ~= "enchant" and kind ~= "spell" then return end
	id = tonumber(id)
	if id and ns.Enchants[id] then ns.List.Open(id) end
end)

-- Add-on compartment (.toc). Blizzard calls these with (addonName, mouseButton) and (addonName, menuButtonFrame).
function Gratuity_OnAddonCompartmentClick(_, button)
	OnClick(button)
end

function Gratuity_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton or AddonCompartmentFrame or UIParent, "ANCHOR_LEFT")
	FillTooltip(GameTooltip)
	GameTooltip:Show()
end

function Gratuity_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
