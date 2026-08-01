-- BagSort Addon - In-Place Sort
-- Displays item levels and sorts equipment by item level

local ADDON_NAME, NS = ...;

BagSortDB = BagSortDB or {
    useColoring = true,
    showBagButtons = true,
    columns = 10,
    layout = "topleft",
    position = nil,
};

local C_Item_GetItemInfoInstant = C_Item.GetItemInfoInstant;
local C_Item_GetCurrentItemLevel = C_Item.GetCurrentItemLevel;
local C_Container_GetContainerItemLink, C_Container_GetContainerItemInfo = C_Container.GetContainerItemLink, C_Container.GetContainerItemInfo;
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS;

local CACHE = {};

-- Tooltip for binding detection
local bindingTooltip;


local INVENTORY_TYPE_PRIORITY_DEFAULT = 99;

local ITEM_CLASSES = {
    [Enum.ItemClass.Weapon]     = true,
    [Enum.ItemClass.Armor]      = true,
    [Enum.ItemClass.Profession] = true,
};

-- Get binding type for an item: SB (Soulbound), BoE (Bind on Equip), BoP (Bind on Pickup), or nil
-- Uses tooltip scanning to detect binding type
local bindingTooltip;
local function GetItemBindingType(bag, slot)
    local itemLink = C_Container_GetContainerItemLink(bag, slot);
    if not itemLink then return nil; end
    
    -- Use tooltip to check for binding text
    if not bindingTooltip then
        bindingTooltip = CreateFrame("GameTooltip", "BagSortBindingTooltip", UIParent, "GameTooltipTemplate");
    end
    bindingTooltip:SetOwner(UIParent, "ANCHOR_NONE");
    bindingTooltip:ClearLines();
    bindingTooltip:SetBagItem(bag, slot);
    
    local bindingType = nil;
    for i = 1, bindingTooltip:NumLines() do
        local text = _G[bindingTooltip:GetName() .. "TextLeft" .. i];
        if text and text:GetText() then
            local line = text:GetText();
            if line:find("Binds when picked up") or line:find("Bind on Pickup") then
                bindingType = "BoP";
                break;
            elseif line:find("Binds when equipped") or line:find("Bind on Equip") then
                bindingType = "BoE";
                break;
            elseif line:find("Binds when used") or line:find("Bind on Use") then
                bindingType = "BoU";
                break;
            elseif line:find("Soulbound") or line:find("Already Known") then
                bindingType = "SB";
                break;
            elseif line:find("Warbound until equipped") or line:find("Warbound to Account") then
                bindingType = "WB";
                break;
            end
        end
    end
    
    bindingTooltip:Hide();
    return bindingType;
end

local function GetItemSortData(bag, slot)
    local itemLink = C_Container_GetContainerItemLink(bag, slot);
    if CACHE[itemLink] then
        local c = CACHE[itemLink];
        return c.itemLevel, c.quality;
    end

    local itemInfo = C_Container_GetContainerItemInfo(bag, slot);
    if not itemInfo then return; end

    local _, _, _, _, _, classID = C_Item_GetItemInfoInstant(itemLink);
    if not (classID and ITEM_CLASSES[classID]) then return; end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot);
    local itemLevel = itemLocation and C_Item_GetCurrentItemLevel(itemLocation);
    if not itemLevel then return; end

    local quality = itemInfo.quality;

    CACHE[itemLink] = {itemLevel = itemLevel, quality = quality};
    return itemLevel, quality;
end

-- Backwards-compatible wrapper for the button display code
local function GetContainerItemLevelAndQuality(bag, slot)
    local ilvl, quality = GetItemSortData(bag, slot);
    return ilvl, quality;
end

local hooks = {};

function NS.RegisterHook(func, hook, includeBlizzard)
    hooks[func] = hooks[func] or {};
    hooks[func][hook] = includeBlizzard and true or false;
end

function NS.CallHooks(func, itemButton)
    if not itemButton then return; end
    for hook, includeBlizzard in pairs(hooks[func] or {}) do
        if includeBlizzard then
            local bag, slot = itemButton:GetBagID(), itemButton:GetID();
            hook(itemButton, bag, slot);
        end
    end
end

local function UpdateButton(button, bag, slot)
    if not button:IsShown() then return; end

    if button.count then
        local font = button.count >= 1000 and NumberFont_OutlineThick_Mono_Small or NumberFontNormal;
        button.Count:SetFontObject(font);
        button.Count:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', 0, 2);
    end

    if not button.ItemLevel then
        button.ItemLevel = button:CreateFontString(nil, 'ARTWORK', 'NumberFontNormal');
        button.ItemLevel:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', 0, 2);
        button.ItemLevel:SetJustifyH('RIGHT');
    end
    
    if not button.BindingType then
        button.BindingType = button:CreateFontString(nil, 'ARTWORK', 'NumberFontNormal');
        button.BindingType:SetPoint('TOPLEFT', button, 'TOPLEFT', 2, -2);
        button.BindingType:SetJustifyH('LEFT');
        button.BindingType:SetFontObject(NumberFont_OutlineThick_Mono_Small);
    end

    button.ItemLevel:Hide();
    button.BindingType:Hide();

    if not button.count or button.count <= 0 then return; end

    local itemLevel, quality = GetContainerItemLevelAndQuality(bag, slot);

    if itemLevel and quality then
        button.ItemLevel:SetText(itemLevel);
        if BagSortDB.useColoring then
            button.ItemLevel:SetTextColor(ITEM_QUALITY_COLORS[quality].color:GetRGB());
        else
            button.ItemLevel:SetTextColor(1, 1, 1);
        end
        button.ItemLevel:Show();
    end
    
    -- Show binding type if applicable
    local bindingType = GetItemBindingType(bag, slot);
    if bindingType then
        button.BindingType:SetText(bindingType);
        button.BindingType:SetTextColor(1, 0.8, 0); -- Gold color
        button.BindingType:Show();
    end
end

NS.RegisterHook('BagSortItemButton_Update', UpdateButton, true);

local function UpdateAllBagItems()
    if ContainerFrameCombinedBags then
        for _, itemButton in ContainerFrameCombinedBags:EnumerateValidItems() do
            NS.CallHooks('BagSortItemButton_Update', itemButton);
        end
    end

    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame" .. i];
        if containerFrame then
            for _, itemButton in containerFrame:EnumerateValidItems() do
                NS.CallHooks('BagSortItemButton_Update', itemButton);
            end
        end
    end
end

local isSorting = false;

local function SortEquipmentByItemLevel()
    if InCombatLockdown() then return; end
    if isSorting then return; end

    isSorting = true;
    CACHE = {};

    local equipmentBags, unassignedBags = {}, {};

    for bag = NUM_BAG_SLOTS, 0, -1 do
        local isEquipment = C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags and Enum.BagSlotFlags.ClassEquipment or 1);
        local isUnassigned = not (isEquipment
            or C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags and Enum.BagSlotFlags.ClassConsumables    or 2)
            or C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags and Enum.BagSlotFlags.ClassProfessionGoods or 4)
            or C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags and Enum.BagSlotFlags.ClassJunk            or 8));
        if isEquipment then
            table.insert(equipmentBags, bag);
        elseif isUnassigned then
            table.insert(unassignedBags, bag);
        end
    end

    local targetBags = {};
    for _, bag in ipairs(equipmentBags)  do table.insert(targetBags, bag); end
    for _, bag in ipairs(unassignedBags) do table.insert(targetBags, bag); end

    if #targetBags == 0 then isSorting = false; return; end

    -- Ordered list of all physical slots we manage.
    -- The index i into this table IS the target position for the i-th best item.
    local allSlots = {};
    -- Lookup: slotLookup[bag][slot] = index into allSlots — avoids O(N) scans
    local slotLookup = {};
    for _, bag in ipairs(targetBags) do
        slotLookup[bag] = slotLookup[bag] or {};
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            table.insert(allSlots, {bag = bag, slot = slot});
            slotLookup[bag][slot] = #allSlots;
        end
    end

    -- Snapshot the current live state of all managed slots.
    -- Each entry mirrors allSlots[i] and carries sort keys.
    -- Non-equipment / empty slots get ilvl = -1 as a sentinel so they sort last.
    -- `origIdx` is the slot's index in allSlots — used as stable tiebreaker
    -- so identical items never swap unnecessarily (preserves their relative order).
    local function BuildSnapshot()
        local snap = {};
        for i, s in ipairs(allSlots) do
            local link = C_Container_GetContainerItemLink(s.bag, s.slot);
            local ilvl, quality, origIdx = -1, -1, i;
            if link then
                local _, _, _, _, _, classID = C_Item_GetItemInfoInstant(link);
                if classID and ITEM_CLASSES[classID] then
                    local il, q = GetContainerItemLevelAndQuality(s.bag, s.slot);
                    if il and q and q > 0 then  -- Exclude grey (quality 0) items
                        ilvl, quality = il, q or 0;
                    end
                end
            end
            snap[i] = {bag = s.bag, slot = s.slot, ilvl = ilvl, quality = quality, origIdx = origIdx};
        end
        return snap;
    end

    -- Returns `desired`: desired[targetPos] = current snapshot index of the item
    -- that should end up at targetPos after sorting.
    local function ComputeDesiredOrder(snap)
        local indices = {};
        for i = 1, #snap do indices[i] = i; end
        table.sort(indices, function(a, b)
            local sa, sb = snap[a], snap[b];
            if sa.ilvl    ~= sb.ilvl    then return sa.ilvl    > sb.ilvl;    end
            if sa.quality ~= sb.quality then return sa.quality > sb.quality; end
            return sa.origIdx < sb.origIdx; -- stable: prefer item already closer to front
        end);
        return indices;
    end

    -- Find the first (targetPos, sourcePos) pair where a swap is needed.
    -- targetPos: the slot that has the wrong item.
    -- sourcePos: where the item that belongs at targetPos currently lives.
    --
    -- `desired[pos]` = snapshot index of item that SHOULD be at pos.
    -- `currentAt[pos]` = snapshot index of item that IS at pos right now.
    -- These start the same (snap[i] lives at slot i), so currentAt[i] = i.
    -- We need to find the first pos where currentAt[pos] ~= desired[pos],
    -- then find which pos currently holds desired[pos] to know what to swap.
    local function FindFirstMismatch(desired)
        -- whereIs[snapIdx] = which pos that item currently occupies
        -- Initially item i is at pos i (snapshot reflects live state).
        local whereIs = {};
        for i = 1, #desired do whereIs[i] = i; end

        for pos = 1, #desired do
            local wantIdx = desired[pos];   -- snapshot index we want at this pos
            local havePos = whereIs[wantIdx]; -- where that item currently is

            if havePos ~= pos then
                -- The item we want is at havePos; the item at pos is wrong.
                -- Swap them in our whereIs map to simulate the move,
                -- but just return the two positions for the caller to act on.
                return pos, havePos;
            end
        end
        return nil;
    end

    -- C_Container.SortBags(); -- Commented out to disable Blizzard bag clean-up

    C_Timer.After(1, function()
        local function doNextSwap()
            if not isSorting then return; end

            local snap    = BuildSnapshot();
            local desired = ComputeDesiredOrder(snap);
            local posA, posB = FindFirstMismatch(desired);

            if not posA then
                isSorting = false;
                return;
            end

            -- posA = target slot (has wrong item), posB = where the right item is now
            local slotA = allSlots[posA];
            local slotB = allSlots[posB];

            -- slotA = destination (wrong item or empty), slotB = source (item we want)
            -- Only proceed if the source item still exists (sanity guard)
            if C_Container_GetContainerItemLink(slotB.bag, slotB.slot) then  -- source still exists
                C_Container.PickupContainerItem(slotB.bag, slotB.slot);
                C_Container.PickupContainerItem(slotA.bag, slotA.slot);
            end

            C_Timer.After(0.3, doNextSwap);
        end

        doNextSwap();
    end);
end

-- Sort Button
local sortButton;

local function UpdateSortButtonVisibility()
    if not sortButton then return; end
    local open = false;
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        open = true;
    else
        for i = 1, NUM_CONTAINER_FRAMES do
            local cf = _G["ContainerFrame" .. i];
            if cf and cf:IsShown() then open = true; break; end
        end
    end
    if open then sortButton:Show(); else sortButton:Hide(); end
end

local function CreateSortButton()
    if sortButton then return; end

    local parent = ContainerFrameCombinedBags or _G["ContainerFrame1"];
    if not parent then return; end

    sortButton = CreateFrame("Button", "BagSortEquipmentButton", UIParent, "UIPanelButtonTemplate");
    sortButton:SetSize(32, 32);
    sortButton:SetFrameStrata("HIGH");
    sortButton:SetFrameLevel(parent:GetFrameLevel() + 5);
    sortButton:SetText("Sort");

    if BagItemSearchBox then
        sortButton:SetPoint("RIGHT", BagItemSearchBox, "LEFT", -5, 0);
    elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags.SearchBox then
        sortButton:SetPoint("RIGHT", ContainerFrameCombinedBags.SearchBox, "LEFT", -5, 0);
    else
        sortButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -8);
    end

    sortButton:SetScript("OnClick", SortEquipmentByItemLevel);
    sortButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Sort by Item Level", 1, 1, 1);
        GameTooltip:AddLine("Sorts equipment by ilvl (highest first)", nil, nil, nil, true);
        GameTooltip:Show();
    end);
    sortButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    sortButton:Show();
end

-- Slash Command
SLASH_BAGSORT1 = '/bagsort';
SlashCmdList['BAGSORT'] = function(input)
    input = strtrim(input or "");
    if input == "sort" then
        SortEquipmentByItemLevel();
    elseif input == "button" then
        if sortButton then UpdateSortButtonVisibility(); else CreateSortButton(); end
    end
end

-- Events
local frame = CreateFrame("Frame");
frame:RegisterEvent("PLAYER_LOGIN");
frame:RegisterEvent("BAG_UPDATE_DELAYED");
frame:RegisterEvent("PLAYER_REGEN_DISABLED");

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if ContainerFrameCombinedBags then
            hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", function()
                for _, btn in ContainerFrameCombinedBags:EnumerateValidItems() do
                    NS.CallHooks('BagSortItemButton_Update', btn);
                end
            end);
            ContainerFrameCombinedBags:HookScript("OnShow", UpdateSortButtonVisibility);
            ContainerFrameCombinedBags:HookScript("OnHide", UpdateSortButtonVisibility);
        end

        for i = 1, NUM_CONTAINER_FRAMES do
            local cf = _G["ContainerFrame" .. i];
            if cf then
                hooksecurefunc(cf, "UpdateItems", function()
                    for _, btn in cf:EnumerateValidItems() do
                        NS.CallHooks('BagSortItemButton_Update', btn);
                    end
                end);
                cf:HookScript("OnShow", UpdateSortButtonVisibility);
                cf:HookScript("OnHide", UpdateSortButtonVisibility);
            end
        end

        UpdateAllBagItems();
        C_Timer.After(2, CreateSortButton);
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateAllBagItems();
    elseif event == "PLAYER_REGEN_DISABLED" then
        if isSorting then
            isSorting = false;
            ClearCursor();
            print("|cffff4444BagSort:|r Sorting interrupted by combat. Run again after combat ends.");
        end
    end
end);