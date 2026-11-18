local addon, ns = ...
local action = 'CLICK MaliFishingButton:LeftButton'
BINDING_CATEGORY_MALIFISHING = 'MaliFishing'
BINDING_HEADER_MALIFISHING = 'MaliFishing'
_G['BINDING_NAME_' .. action] = 'Cast / Reel'

local function boundKey()
    return GetBindingKey(action)
end

local db, pending, cast, active, oldSoft
local areas = {}
local line, deferred, browse = false, false, false
-- Fishing input
local owner = CreateFrame('Frame', nil, UIParent)
local castButton = CreateFrame('Button', 'MaliFishingButton', UIParent, 'SecureActionButtonTemplate')
castButton:SetSize(1, 1)
castButton:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', -10, -10)
local function spell()
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7620)
        or (GetSpellInfo and GetSpellInfo(7620)) or 'Fishing'
end

local function fishing()
    local name, _, _, _, _, _, _, id = UnitChannelInfo('player')
    return name == spell() or id == 7620
end

local function keyDownMode()
    return GetCVarBool('ActionButtonUseKeyDown')
end

local function clickMode()
    castButton:RegisterForClicks(keyDownMode() and 'AnyDown' or 'AnyUp')
end

local function sync()
    if not db or InCombatLockdown() then
        return
    end
    for _, key in ipairs({ GetBindingKey(action) }) do
        local base = key and key:match('[^-]+$')
        local mouse = base and tonumber(base:match('^BUTTON(%d+)$'))
        local held
        if mouse then
            held = IsMouseButtonDown and IsMouseButtonDown(mouse)
        elseif base and IsKeyDown then
            held = IsKeyDown(base)
        end
        if held then
            if not deferred then
                deferred = true
                C_Timer.After(0.08, function()
                    deferred = false
                    sync()
                end)
            end
            return
        end
    end
    ClearOverrideBindings(owner)
    if line then
        for _, key in ipairs({ GetBindingKey(action) }) do
            SetOverrideBinding(owner, true, key, 'INTERACTTARGET')
        end
    end
end

local function soft(enabled)
    local value = GetCVar('SoftTargetInteract')
    if enabled and (boundKey() or db.doubleClick) then
        if not oldSoft and value and value ~= '3' then
            oldSoft = value
            SetCVar('SoftTargetInteract', '3')
        end
    elseif oldSoft then
        if value == '3' then
            SetCVar('SoftTargetInteract', oldSoft)
        end
        oldSoft = nil
    end
end

local audio = { saved = {}, writing = {} }
function audio.set(key, value)
    audio.writing[key] = true
    SetCVar(key, value)
    audio.writing[key] = nil
end
function audio.update(enabled)
    if enabled and db and db.splashBoost then
        if audio.active then return end
        audio.active = true
        for key, value in pairs({ Sound_SFXVolume = 1, Sound_AmbienceVolume = 0.10 }) do
            local old = GetCVar(key)
            local n = tonumber(old)
            if n and ((key == 'Sound_SFXVolume' and n < value) or
                     (key == 'Sound_AmbienceVolume' and n > value)) then
                audio.set(key, tostring(value))
                local applied = tonumber(GetCVar(key))
                if applied and applied ~= n then audio.saved[key] = { old = old, applied = applied } end
            end
        end
    else
        audio.active = false
        for key, entry in pairs(audio.saved) do
            audio.saved[key] = nil
            if tonumber(GetCVar(key)) == entry.applied then audio.set(key, entry.old) end
        end
    end
end

-- Weapon swapping
local equipItem = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local restoreGeneration = 0
local weapons, restoring
local function equipped(slot)
    return GetInventoryItemLink('player', slot)
end

local function rod(link)
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not info or not link then
        return false
    end
    local _, _, _, _, _, class, subclass = info(link)
    return class == 2 and subclass == 20
end

local function bestRod()
    local bags = C_Container
    if not bags then return end
    local best, score
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, bags.GetContainerNumSlots(bag) do
            local link = bags.GetContainerItemLink(bag, slot)
            if rod(link) then
                local tooltip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
                local bonus, usable = 0, true
                local info = C_Item and C_Item.GetItemInfo or GetItemInfo
                local requiredLevel
                if info then
                    local _, _, _, _, level = info(link)
                    requiredLevel = level
                end
                if requiredLevel and requiredLevel > UnitLevel('player') then usable = false end
                for _, row in ipairs(tooltip and tooltip.lines or {}) do
                    local text = row.leftText or ''
                    local color = row.leftColor
                    if color and color.r > 0.8 and color.g < 0.3 and color.b < 0.3 then
                        usable = false
                    end
                    local value = text:match('[Ff]ishing[^%d]*(%d+)') or text:match('%+(%d+)%s+[Ff]ishing')
                    if value and not text:find('[Rr]equires') then
                        bonus = math.max(bonus, tonumber(value))
                    end
                end
                if usable and (not score or bonus > score) then
                    best, score = link, bonus
                end
            end
        end
    end
    return best
end

local function restoreWeapons(combatOnly)
    local generation = restoreGeneration
    if not weapons or restoring or not equipItem then return end
    if not rod(equipped(16)) and not weapons.restoring then return end
    weapons.restoring, restoring = true, true
    local snapshot = weapons
    if snapshot.main and equipped(16) ~= snapshot.main then
        pcall(equipItem, snapshot.main, 16)
    end
    C_Timer.After(0.25, function()
        if weapons ~= snapshot or generation ~= restoreGeneration or (combatOnly and not UnitAffectingCombat('player')) then
            restoring = false
            return
        end
        if equipped(16) == snapshot.main and snapshot.off and equipped(17) ~= snapshot.off then
            pcall(equipItem, snapshot.off, 17)
        end
        C_Timer.After(0.25, function()
            restoring = false
            if weapons == snapshot and equipped(16) == snapshot.main and equipped(17) == snapshot.off then
                weapons = nil
            elseif weapons == snapshot and generation == restoreGeneration and not combatOnly and not InCombatLockdown() and not snapshot.retried then
                snapshot.retried = true
                restoreWeapons()
            elseif weapons == snapshot and generation == restoreGeneration and not combatOnly and not InCombatLockdown() then
                print('MaliFishing: Could not fully restore your weapons. Check your weapon slots.')
            end
        end)
    end)
end

local function scheduleRestore()
    restoreGeneration = restoreGeneration + 1
    local generation, snapshot = restoreGeneration, weapons
    if snapshot then
        C_Timer.After(30, function()
            if generation == restoreGeneration and weapons == snapshot and not line and not InCombatLockdown() then
                restoreWeapons()
            end
        end)
    end
end

local function prepareRod()
    if not db.autoRod or rod(equipped(16)) or not equipItem then return false end
    if weapons then return true end
    local main, off = equipped(16), equipped(17)
    if not main then return false end
    local best = bestRod()
    if not best then return false end
    local snapshot = { main = main, off = off }
    weapons = snapshot
    pcall(equipItem, best, 16)
    C_Timer.After(1, function()
        if weapons == snapshot and not snapshot.restoring and not rod(equipped(16)) then
            weapons = nil
            print('MaliFishing: Could not equip a fishing rod.')
        end
    end)
    scheduleRestore()
    return true
end

local lureNames = {
    [6529] = 'Shiny Bauble', [6530] = 'Nightcrawlers', [6532] = 'Bright Baubles',
    [6533] = 'Aquadynamic Fish Attractor', [6811] = 'Aquadynamic Fish Lens',
    [7307] = 'Flesh Eating Worm',
}
local fresh = { slots = {}, queue = {} }
local lootOpen = false
local function bagItems()
    local items = {}
    local bags = C_Container
    if not bags then return items end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, bags.GetContainerNumSlots(bag) do
            local info = bags.GetContainerItemInfo(bag, slot)
            if info and (lureNames[info.itemID]) then
                local item = items[info.itemID] or { count = 0 }
                items[info.itemID] = item
                item.count = item.count + (info.stackCount or 1)
                if not item.bag and not info.isLocked then item.bag, item.slot = bag, slot end
            end
        end
    end
    return items
end
function fresh.snapshot()
    local result, bags = {}, C_Container
    if not bags then return result end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, bags.GetContainerNumSlots(bag) do
            local info = bags.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local guid
                if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
                    guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
                end
                result[bag .. ':' .. slot] = { bag = bag, slot = slot, id = info.itemID, guid = guid,
                    link = info.hyperlink, count = info.stackCount or 1, loot = info.hasLoot, locked = info.isLocked }
            end
        end
    end
    return result
end
function fresh.same(a, b)
    return a and b and a.id == b.id and a.guid == b.guid and a.link == b.link
end
function fresh.openable(entry)
    if not entry or not entry.loot or entry.locked then return false end
    local tooltip = C_TooltipInfo and C_TooltipInfo.GetBagItem
    local data = tooltip and tooltip(entry.bag, entry.slot)
    if not data or not data.lines or not data.lines[1] then return false end
    for _, row in ipairs(data.lines) do
        local text = (row.leftText or ''):lower()
        if text == (LOCKED or 'Locked'):lower() or text:find('lockpick', 1, true)
            or text:find('lockbox', 1, true) or text:find('junkbox', 1, true)
            or (LOCKPICKING and text:find(LOCKPICKING:lower(), 1, true)) then return false end
    end
    return true
end
function fresh.settle()
    local now = fresh.snapshot()
    for key, credit in pairs(fresh.slots) do
        local entry = now[key]
        if not fresh.same(credit.entry, entry) or entry.count < credit.expected then fresh.slots[key] = nil end
    end
    for _, batch in ipairs(fresh.queue) do
        if GetTime() <= batch.deadline then
            local oldGUIDs = {}
            for _, old in pairs(batch.before) do
                if old.guid then oldGUIDs[old.guid] = true end
            end
            for key, entry in pairs(now) do
                local old, remaining = batch.before[key], batch.items[entry.id] or 0
                local added = fresh.same(old, entry) and math.max(0, entry.count - old.count)
                    or (not old and not (entry.guid and oldGUIDs[entry.guid]) and entry.count or 0)
                if added > 0 and remaining > 0 and entry.loot then
                    local count = math.min(added, remaining)
                    local previous = fresh.slots[key]
                    batch.items[entry.id] = remaining - count
                    fresh.slots[key] = { entry = entry, expected = entry.count,
                        count = math.min(entry.count, count + (previous and previous.count or 0)) }
                end
            end
        end
    end
    fresh.queue = {}
    return now
end
local function prepareCatch(self)
    if not db.autoLure and not db.openCaught then return false end
    if (CursorHasItem and CursorHasItem()) or (SpellIsTargeting and SpellIsTargeting()) then return false end
    local items = bagItems()
    local lure = db.autoLure and items[db.lureID]
    if lure and lure.bag and rod(equipped(16)) and GetWeaponEnchantInfo and not GetWeaponEnchantInfo() then
        self:SetAttribute('item', ('%d %d'):format(lure.bag, lure.slot))
        self:SetAttribute('target-slot', 16)
        self:SetAttribute('type', 'item')
        return true
    end
    if db.openCaught then
        local now = fresh.settle()
        for key, credit in pairs(fresh.slots) do
            local entry = now[key]
            if fresh.openable(entry) then
                credit.count = credit.count - 1
                credit.expected = entry.count - 1
                if credit.count == 0 then fresh.slots[key] = nil end
                self:SetAttribute('item', ('%d %d'):format(entry.bag, entry.slot))
                self:SetAttribute('type', 'item')
                return true
            end
        end
    end
    return false
end

castButton:SetScript('PreClick', function(self)
    if not InCombatLockdown() then
        self:SetAttribute('type', nil)
        self:SetAttribute('target-slot', nil)
        if lootOpen or line or pending or fishing() or (LootFrame and LootFrame:IsShown()) then return end
        if (MerchantFrame and MerchantFrame:IsShown()) or (TradeFrame and TradeFrame:IsShown())
            or (MailFrame and MailFrame:IsShown()) or (BankFrame and BankFrame:IsShown())
            or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
        if prepareRod() then return end
        if not prepareCatch(self) then
            self:SetAttribute('spell', spell())
            self:SetAttribute('type', 'spell')
        end
    end
end)
castButton:SetScript('PostClick', function(self)
    if not InCombatLockdown() then
        self:SetAttribute('type', nil)
    end
end)

-- Double right-click
local mouseOwner = CreateFrame('Frame', nil, UIParent)
local mouseDown, lastTap, mouseOverride
local function clearMouse()
    if not InCombatLockdown() then
        ClearOverrideBindings(mouseOwner)
        mouseOverride = nil
    end
end

local function overWorld()
    if WorldFrame and WorldFrame.IsMouseMotionFocus and WorldFrame:IsMouseMotionFocus() then
        return true
    end
    if GetMouseFoci then
        local focus = GetMouseFoci()
        return type(focus) == 'table' and focus[1] == WorldFrame
    end
    return false
end

local function rightDown()
    if not db or not db.doubleClick or InCombatLockdown() or not overWorld() then
        lastTap, mouseDown = nil, nil
        return
    end
    local now = GetTime()
    mouseDown = now
    if lastTap and now - lastTap <= 0.35 then
        lastTap = nil
        mouseOverride = true
        if line then
            SetOverrideBinding(mouseOwner, true, 'BUTTON2', 'INTERACTTARGET')
        else
            SetOverrideBindingClick(mouseOwner, true, 'BUTTON2', 'MaliFishingButton', 'LeftButton')
        end
    end
end

local function rightUp()
    if mouseOverride then
        C_Timer.After(0, clearMouse)
    elseif mouseDown and GetTime() - mouseDown <= 0.22 and overWorld() then
        lastTap = GetTime()
    else
        lastTap = nil
    end
    mouseDown = nil
end

-- Catch records and clock
local function current()
    local zone = GetZoneText() or 'Unknown area'
    local subzone = GetSubZoneText()
    local label = subzone and subzone ~= '' and subzone ~= zone and zone .. ' / ' .. subzone or zone
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
    local key = (map or zone) .. ':' .. label
    if not areas[key] then
        areas[key] = { key = key, zone = zone, label = label, items = {}, seconds = 0 }
    end
    return areas[key]
end

local function elapsed(spot, now)
    if active and active.spot == spot then
        return spot.seconds + math.max(0, math.min(now, active.deadline or now) - active.started)
    end
    return spot.seconds
end

local function pause(now)
    if active then
        active.spot.seconds = elapsed(active.spot, now)
        active = nil
    end
end

-- HUD controls
local function backdrop(frame, alpha)
    frame:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
    frame:SetBackdropColor(0.04, 0.07, 0.10, alpha)
    frame:SetBackdropBorderColor(0.24, 0.42, 0.49, 1)
end

local function label(parent, font)
    local text = parent:CreateFontString(nil, 'OVERLAY', font or 'GameFontHighlightSmall')
    text:SetJustifyH('LEFT')
    text:SetWordWrap(false)
    return text
end

local function place(frame, parent, x, y)
    frame:ClearAllPoints()
    frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
end

local function control(parent, text, width, fn)
    local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    button:SetSize(width, 18)
    button:SetText(text)
    button:SetScript('OnClick', fn)
    return button
end

local hud = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
hud:SetSize(320, 110)
hud:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 26, -180)
backdrop(hud, 0.93)
hud:SetMovable(true)
hud:SetClampedToScreen(true)
hud:EnableMouse(true)
hud:RegisterForDrag('LeftButton')
hud:SetScript('OnDragStart', hud.StartMoving)
local function applyHUDPosition()
    local x, y = db.x, db.y
    if db.minimalHUD then x, y = db.minimalX, db.minimalY end
    local ratio = UIParent:GetEffectiveScale() / hud:GetEffectiveScale()
    hud:ClearAllPoints()
    hud:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', (x or 26) * ratio, (y or -180) * ratio)
end

local function savePosition()
    local ratio = hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, top = hud:GetLeft(), hud:GetTop()
    if not left or not top then return end
    local x, y = left * ratio, top * ratio - UIParent:GetHeight()
    if db.minimalHUD then
        db.minimalX, db.minimalY = x, y
    else
        db.x, db.y = x, y
    end
end
hud:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    savePosition()
end)
hud:Hide()

local title = label(hud, 'GameFontNormal')
local skill, stats, prices = label(hud), label(hud), label(hud)
local ahLine, cphLine = label(hud), label(hud)
local page, pageCount, pageSize = 1, 1, 8
local redraw, visibility, refreshOptions
local function clearTrackedCatch()
    db.targetItem = nil
    redraw()
end

local function clickHint(frame, text)
    GameTooltip:SetOwner(frame, 'ANCHOR_RIGHT')
    GameTooltip:AddLine(text, 1, 1, 1)
    GameTooltip:Show()
end

local function hideHint(frame)
    if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local targetClick = CreateFrame('Button', nil, hud)
targetClick:RegisterForClicks('RightButtonUp')
local targetIcon = targetClick:CreateTexture(nil, 'ARTWORK')
targetIcon:SetPoint('LEFT')
local targetLine = label(targetClick)
targetLine:SetPoint('LEFT', targetIcon, 'RIGHT', 4, 0)

local function targetSize()
    return db.minimalHUD and db.minimalTargetIconSize or db.targetIconSize
end
targetClick:Hide()
targetClick:SetScript('OnClick', function(self)
    hideHint(self)
    clearTrackedCatch()
end)
targetClick:SetScript('OnEnter', function(self) clickHint(self, 'Right-click to clear target') end)
targetClick:SetScript('OnLeave', hideHint)
targetClick:SetScript('OnHide', hideHint)

local function auctionVisible()
    if db.minimalHUD and db.minimalAH ~= nil then return db.minimalAH end
    return db.showAH == true
end
local expand = control(hud, 'Catches', 68, function()
    db.expanded = not db.expanded
    redraw()
end)
local mode = control(hud, 'Session', 62, function()
    db.lifetime, page = not db.lifetime, 1
    redraw()
end)
local scope = control(hud, 'Area', 48, function()
    db.zoneScope, page = not db.zoneScope, 1
    redraw()
end)
local back = control(hud, '<', 22, function()
    page = math.max(1, page - 1)
    redraw()
end)
local nextPage = control(hud, '>', 22, function()
    page = math.min(pageCount, page + 1)
    redraw()
end)
local grip = CreateFrame('Button', nil, hud)
grip:SetSize(15, 15)
grip:SetPoint('BOTTOMRIGHT', -1, 1)
grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
local rows = {}
for i = 1, pageSize do
    local frame = CreateFrame('Button', nil, hud)
    frame:RegisterForClicks('RightButtonUp')
    local icon = frame:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('LEFT')
    local name, detail = label(frame), label(frame)
    name:SetPoint('LEFT', icon, 'RIGHT', 5, 0)
    detail:SetPoint('RIGHT')
    local row = { frame = frame, icon = icon, name = name, detail = detail }
    rows[i] = row
    local iconClick = CreateFrame('Button', nil, frame)
    iconClick:SetAllPoints(icon)
    iconClick:RegisterForClicks('RightButtonUp')
    local function hint(self)
        if row.id then
            clickHint(self, db.targetItem == row.id and 'Right-click to clear target' or 'Right-click to target')
        end
    end
    local function toggleTarget()
        if not row.id then return end
        db.targetItem = db.targetItem ~= row.id and row.id or nil
        redraw()
        if GameTooltip:IsOwned(iconClick) then hint(iconClick) end
    end
    frame:SetScript('OnClick', toggleTarget)
    iconClick:SetScript('OnClick', toggleTarget)
    iconClick:SetScript('OnEnter', hint)
    iconClick:SetScript('OnLeave', hideHint)
    iconClick:SetScript('OnHide', hideHint)
end

local spot, totals
local itemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local function rate(value, known, seconds)
    if not known or seconds < 1 then
        return '—'
    end
    if db.minimalHUD then
        local copper = math.floor(value * 3600 / seconds + 0.5)
        return ('%d|TInterface\\MoneyFrame\\UI-GoldIcon:10|t %02d|TInterface\\MoneyFrame\\UI-SilverIcon:10|t'):format(
            math.floor(copper / 10000), math.floor(copper / 100) % 100)
    end
    local silver = math.floor(value * 36 / seconds + 0.5)
    return ('%dg %02ds/hr'):format(math.floor(silver / 100), silver % 100)
end

local function updateRates()
    if not spot or not totals or not hud:IsShown() then
        return
    end
    local seconds = elapsed(spot, GetTime())
    local caught = seconds >= 1 and math.floor(totals.units * 3600 / seconds + 0.5) or 0
    stats:SetText(('%d catches | %d cph | %d:%02d'):format(
        totals.units, caught, math.floor(seconds / 60), math.floor(seconds) % 60))
    prices:SetText((db.minimalHUD and 'V: ' or 'Vendor ') .. rate(totals.vendor, totals.vendorKnown, seconds))
    if auctionVisible() then
        local partial = totals.ahKnown and seconds >= 1 and totals.ahUnits < totals.units
        ahLine:SetText((db.minimalHUD and 'AH: ' or 'AH est. ') .. rate(totals.ah, totals.ahKnown, seconds)
            .. (partial and (db.minimalHUD and '*' or ' (partial)') or ''))
    end
    if db.minimalHUD and db.minimalCatches then
        cphLine:SetText(seconds >= 1 and ('%d cph'):format(math.floor(totals.units * 3600 / seconds + 0.5)) or '— cph')
    end
    if db.targetItem then
        local count = spot.items[db.targetItem] or 0
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(db.targetItem)) or 134400
        local hourly = seconds >= 1 and ('%d/h'):format(math.floor(count * 3600 / seconds + 0.5)) or '—'
        local name = not db.minimalHUD and itemInfo and itemInfo(db.targetItem)
        local size = targetSize()
        targetIcon:SetTexture(icon)
        targetIcon:SetSize(size, size)
        targetLine:SetText(hourly .. (name and ('  ' .. name) or ''))
        local textWidth = math.ceil(targetLine:GetStringWidth())
        targetClick:SetSize(size + 4 + textWidth, size + 3)
    end
    if db.minimalHUD then
        local width, y = 0, -5
        for _, text in ipairs({ prices, ahLine, cphLine }) do
            if text:IsShown() then
                text:SetWidth(0)
                place(text, hud, 6, y)
                width = math.max(width, text:GetStringWidth())
                y = y - 13
            end
        end
        if targetClick:IsShown() then
            place(targetClick, hud, 6, y)
            width = math.max(width, targetClick:GetWidth())
            y = y - targetClick:GetHeight()
        end
        hud:SetSize(math.ceil(width) + 12, 5 - y)
    end
end

local function breakdown()
    local source = db.lifetime and db.history or areas
    if not db.zoneScope then
        return source[spot.key] and source[spot.key].items or {}
    end
    local counts = {}
    for _, entry in pairs(source) do
        if entry.zone == spot.zone then
            for id, count in pairs(entry.items) do
                counts[id] = (counts[id] or 0) + count
            end
        end
    end
    return counts
end

local badgeBorder = { 0.85, 0.65, 0.20 }
local badgeBackdrop, backdropThickness
local function layout()
    local compact = db.minimalHUD == true
    local thickness = compact and db.minimalBorderThickness or db.borderThickness
    if badgeBackdrop ~= compact or backdropThickness ~= thickness then
        badgeBackdrop, backdropThickness = compact, thickness
        hud:SetBackdrop({
            bgFile = 'Interface\\Buttons\\WHITE8X8',
            edgeFile = compact and 'Interface\\Tooltips\\UI-Tooltip-Border' or 'Interface\\Buttons\\WHITE8X8',
            edgeSize = thickness,
            insets = compact and { left = 2, right = 2, top = 2, bottom = 2 } or nil,
        })
    end
    local bg = db.background
    local border = compact and (db.minimalBorderColor or badgeBorder) or db.borderColor
    hud:SetBackdropColor(bg[1], bg[2], bg[3], db.opacity / 100)
    local showBorder = (compact and db.minimalBorder ~= false) or (not compact and db.border)
    hud:SetBackdropBorderColor(border[1], border[2], border[3], showBorder and 1 or 0)
    title:SetShown(not compact)
    stats:SetShown(not compact)
    expand:SetShown(not compact)
    grip:SetShown(not compact)
    prices:SetShown(not compact or db.minimalVendor ~= false)
    ahLine:SetShown(auctionVisible())
    cphLine:SetShown(compact and db.minimalCatches == true)
    local showTarget = db.targetItem ~= nil and (not compact or db.minimalTarget ~= false)
    targetClick:SetShown(showTarget)
    if compact then
        updateRates()
        return
    end
    local width = math.max(db.expanded and 265 or 220, db.width)
    local offset = skill:IsShown() and 0 or 17
    local height = math.max(db.iconSize + 4, 19)
    hud:SetWidth(width)
    place(title, hud, 10, -9)
    place(skill, hud, 10, -26)
    place(stats, hud, 10, -43 + offset)
    place(prices, hud, 10, -59 + offset)
    for _, text in ipairs({ title, skill, stats, prices }) do
        text:SetWidth(width - 20)
    end
    ahLine:SetWidth(width - 20)
    if db.showAH then
        place(ahLine, hud, 10, -73 + offset)
        offset = offset - 14
    end
    if db.targetItem then
        place(targetClick, hud, 10, -73 + offset)
        offset = offset - math.max(16, db.targetIconSize + 4)
    end
    place(expand, hud, 8, -77 + offset)
    place(mode, hud, 79, -77 + offset)
    place(scope, hud, 144, -77 + offset)
    place(back, hud, width - 58, -77 + offset)
    place(nextPage, hud, width - 33, -77 + offset)
    local shown = 0
    for i, row in ipairs(rows) do
        row.frame:SetSize(width - 24, height)
        row.icon:SetSize(db.iconSize, db.iconSize)
        row.name:SetWidth(width - db.iconSize - 122)
        place(row.frame, hud, 10, -99 + offset - (i - 1) * height)
        if row.frame:IsShown() then
            shown = shown + 1
        end
    end
    hud:SetHeight(105 - offset + shown * height)
    updateRates()
end

redraw = function()
    if not db or not hud:IsShown() then
        return
    end
    local area = current()
    if spot ~= area then
        page = 1
    end
    spot = area
    title:SetText(spot.label)
    local requirements = ns.requirements or {}
    local levels = requirements[spot.label] or requirements[spot.zone]
    skill:SetShown(not db.minimalHUD and levels ~= nil)
    if levels then
        skill:SetText(('Skill Level: |cffffa040%d|r / |cff72df79%d|r'):format(levels[1], levels[2]))
    end
    totals = { units = 0, vendor = 0, ah = 0, ahUnits = 0 }
    local api = auctionVisible() and Auctionator and Auctionator.API and Auctionator.API.v1
    for id, count in pairs(spot.items) do
        totals.units = totals.units + count
        if itemInfo then
            local _, _, _, _, _, _, _, _, _, _, sell = itemInfo(id)
            if type(sell) == 'number' then
                totals.vendor, totals.vendorKnown = totals.vendor + sell * count, true
            end
        end
        if api and api.GetAuctionPriceByItemID then
            local ok, price = pcall(api.GetAuctionPriceByItemID, addon, id)
            if ok and type(price) == 'number' and price > 0 then
                totals.ah, totals.ahKnown = totals.ah + price * count, true
                totals.ahUnits = totals.ahUnits + count
            end
        end
    end
    local expanded = not db.minimalHUD and db.expanded == true
    expand:SetText(expanded and 'v Catches' or '> Catches')
    mode:SetShown(expanded)
    scope:SetShown(expanded)
    mode:SetText(db.lifetime and 'All-time' or 'Session')
    scope:SetText(db.zoneScope and 'Zone' or 'Area')
    local list, sample = {}, 0
    if expanded then
        for id, count in pairs(breakdown()) do
            local name, icon
            if itemInfo then
                local nameValue, _, _, _, _, _, _, _, _, iconValue = itemInfo(id)
                name, icon = nameValue, iconValue
            end
            sample = sample + count
            list[#list + 1] = { id = id, count = count, name = name or ('Item ' .. id), icon = icon or 134400 }
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.name < b.name
        end)
    end
    pageCount = math.max(1, math.ceil(#list / pageSize))
    page = math.min(page, pageCount)
    back:SetShown(expanded and pageCount > 1)
    nextPage:SetShown(expanded and pageCount > 1)
    for i, row in ipairs(rows) do
        local item = list[(page - 1) * pageSize + i]
        local empty = expanded and i == 1 and #list == 0
        row.id = item and item.id
        row.frame:SetShown(item ~= nil or empty)
        if item then
            row.icon:Show()
            row.icon:SetTexture(item.icon)
            row.name:SetText((db.targetItem == item.id and '* ' or '') .. item.name)
            row.detail:SetText(('%d  %.1f%%'):format(item.count, item.count * 100 / sample))
        elseif empty then
            row.icon:Hide()
            row.name:SetText('No catches recorded here yet.')
            row.detail:SetText('')
        end
    end
    layout()
end

visibility = function()
    local shown = not db.alwaysHide and (browse or (not db.hidden and (not db.onlyFishing or active ~= nil)))
    local changed = shown ~= hud:IsShown()
    hud:SetShown(shown)
    if changed and shown then
        redraw()
    end
    return changed
end

local function applyHUDMode()
    if not visibility() then redraw() end
    applyHUDPosition()
end

local function updateAppearance()
    hud:SetScale(db.scale / 100)
    layout()
end

-- Options and key capture
local panel = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
panel:SetSize(365, 584)
panel:SetPoint('CENTER')
panel:SetFrameStrata('MEDIUM')
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag('LeftButton')
panel:SetScript('OnDragStart', panel.StartMoving)
panel:SetScript('OnDragStop', panel.StopMovingOrSizing)
backdrop(panel, 0.98)
panel:Hide()
local heading = label(panel, 'GameFontNormalLarge')
heading:SetText('MaliFishing Options')
place(heading, panel, 16, -14)
local close = CreateFrame('Button', nil, panel, 'UIPanelCloseButton')
close:SetFrameStrata(panel:GetFrameStrata())
close:SetFrameLevel(panel:GetFrameLevel() + 1)
close:SetPoint('TOPRIGHT', -2, -2)
close:SetScript('OnClick', function() panel:Hide() end)
local keyText, hint = label(panel), label(panel)
place(keyText, panel, 16, -48)
place(hint, panel, 16, -70)
local function keyLabel(key)
    return key and ((GetBindingText and GetBindingText(key, 'KEY_')) or key) or 'Not set'
end

local openBindings = control(panel, 'Open Keybindings', 126, function()
    panel:Hide()
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
    else
        if SettingsPanel then
            ShowUIPanel(SettingsPanel)
        elseif KeyBindingFrame then
            ShowUIPanel(KeyBindingFrame)
        end
        print('MaliFishing: Options > Keybindings > MaliFishing > Cast / Reel')
    end
end)
place(openBindings, panel, 218, -43)
local function optionCheck(text, y, field, changed)
    local check = CreateFrame('CheckButton', nil, panel, 'UICheckButtonTemplate')
    place(check, panel, 12, y)
    local title = label(panel)
    title:SetPoint('LEFT', check, 'RIGHT', 2, 0)
    title:SetText(text)
    check:SetScript('OnClick', function(self)
        db[field] = not not self:GetChecked()
        if changed then changed() end
    end)
    return check
end

local doubleCheck = optionCheck('Double right-click to cast / reel', -76, 'doubleClick', function()
    lastTap, mouseDown = nil, nil
    clearMouse()
    soft(line)
end)
local gearCheck = optionCheck('Auto-swap fishing rod', -106, 'autoRod', function()
    if not db.autoRod then restoreWeapons() end
end)

local lureCheck = optionCheck('Auto apply lure', -136, 'autoLure')
local lurePicker = CreateFrame('Frame', 'MaliFishingLureDropdown', panel, 'UIDropDownMenuTemplate')
place(lurePicker, panel, 145, -133)
UIDropDownMenu_SetWidth(lurePicker, 164)
local function lureName(id)
    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
    return (info and info(id)) or lureNames[id]
end
UIDropDownMenu_Initialize(lurePicker, function(_, level)
    if not db or level ~= 1 then return end
    local items, ids = bagItems(), {}
    for id in pairs(lureNames) do
        if items[id] then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return lureName(a) < lureName(b) end)
    if #ids == 0 then
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.disabled, info.notCheckable = 'No supported lures in bags', true, true
        UIDropDownMenu_AddButton(info, level)
    end
    for _, id in ipairs(ids) do
        local choice = id
        local info = UIDropDownMenu_CreateInfo()
        info.text = ('%s (%d)'):format(lureName(id), items[id].count)
        info.checked = db.lureID == id
        info.func = function()
            db.lureID = choice
            refreshOptions()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)
local caughtCheck = optionCheck('Open caught containers', -166, 'openCaught', function()
    fresh.slots, fresh.queue = {}, {}
    if pending then pending.before, pending.received = nil, nil end
end)
local ahCheck = optionCheck('Show Auctionator price estimate', -226, 'showAH', function()
    redraw()
end)

local minimalCheck = optionCheck('Minimal HUD', -519, 'minimalHUD', function()
    applyHUDMode()
    refreshOptions()
end)
local compactOptions = CreateFrame('Frame', nil, panel, 'BackdropTemplate')
compactOptions:SetSize(224, 320)
compactOptions:SetPoint('LEFT', panel, 'RIGHT', 6, 0)
compactOptions:SetClampedToScreen(true)
compactOptions:EnableMouse(true)
compactOptions:SetFrameLevel(panel:GetFrameLevel() + 4)
backdrop(compactOptions, 0.98)
compactOptions:Hide()
panel:HookScript('OnHide', function() compactOptions:Hide() end)
local compactTitle = label(compactOptions, 'GameFontNormal')
compactTitle:SetText('Minimal HUD Settings')
place(compactTitle, compactOptions, 14, -14)
local compactClose = CreateFrame('Button', nil, compactOptions, 'UIPanelCloseButton')
compactClose:SetPoint('TOPRIGHT', -1, -1)
compactClose:SetScript('OnClick', function() compactOptions:Hide() end)
local compactChecks = {}
for i, choice in ipairs({
    { 'Vendor value (V:)', 'minimalVendor' },
    { 'Auctionator estimate (AH:)', 'minimalAH' },
    { 'Catches per hour', 'minimalCatches' },
    { 'Target Catch', 'minimalTarget' },
    { 'Show border', 'minimalBorder' },
}) do
    local text, field = choice[1], choice[2]
    local check = CreateFrame('CheckButton', nil, compactOptions, 'UICheckButtonTemplate')
    place(check, compactOptions, 10, -32 - (i - 1) * 29)
    local caption = label(compactOptions)
    caption:SetPoint('LEFT', check, 'RIGHT', 2, 0)
    caption:SetText(text)
    check:SetScript('OnClick', function(self)
        db[field] = not not self:GetChecked()
        redraw()
    end)
    compactChecks[field] = check
end
local configure = control(panel, 'Configure...', 96, function()
    compactOptions:SetShown(not compactOptions:IsShown())
    refreshOptions()
end)
place(configure, panel, 145, -525)
local clearTarget = control(panel, 'Clear target', 90, clearTrackedCatch)
place(clearTarget, panel, 16, -548)
local resetHUD = control(panel, 'Reset HUD positions', 132, function()
    db.x, db.y = nil, nil
    db.minimalX, db.minimalY = nil, nil
    applyHUDPosition()
end)
place(resetHUD, panel, 118, -548)

local splashCheck = optionCheck('Boost bobber splash while fishing', -196, 'splashBoost', function()
    audio.update(line)
end)

local sliders = {}
local updating = false
local function slider(field, name, low, high, step, y, suffix, parent)
    parent = parent or panel
    local text = label(parent)
    place(text, parent, 16, y)
    local bar = CreateFrame('Slider', nil, parent, 'OptionsSliderTemplate')
    bar:SetSize(parent == panel and 307 or 176, 15)
    place(bar, parent, 24, y - 16)
    bar:SetMinMaxValues(low, high)
    bar:SetValueStep(step)
    bar:SetObeyStepOnDrag(true)
    for _, fieldName in ipairs({ 'Low', 'High', 'Text' }) do
        if bar[fieldName] then
            bar[fieldName]:SetText('')
        end
    end
    local function display(value)
        text:SetText(('%s: %d%s'):format(name, value, suffix))
    end
    bar:SetScript('OnValueChanged', function(_, value)
        if not updating then
            db[field] = math.floor(value + 0.5)
            display(db[field])
            updateAppearance()
        end
    end)
    sliders[#sliders + 1] = function()
        bar:SetValue(db[field])
        display(db[field])
    end
end
slider('scale', 'HUD scale', 75, 150, 5, -259, '%')
slider('iconSize', 'Catch icon size', 12, 28, 1, -300, ' px')
slider('targetIconSize', 'Target icon size', 12, 36, 1, -341, ' px')
slider('opacity', 'Background opacity', 0, 100, 1, -382, '%')
slider('borderThickness', 'Border thickness', 1, 8, 1, -487, ' px')
slider('minimalTargetIconSize', 'Target icon size', 12, 36, 1, -194, ' px', compactOptions)
slider('minimalBorderThickness', 'Border thickness', 1, 12, 1, -234, ' px', compactOptions)
local only = CreateFrame('CheckButton', nil, panel, 'UICheckButtonTemplate')
place(only, panel, 12, -422)
local onlyText = label(panel)
onlyText:SetPoint('LEFT', only, 'RIGHT', 2, 0)
onlyText:SetText('Only show while fishing')
only:SetScript('OnClick', function(self)
    db.onlyFishing, browse = self:GetChecked() == true, false
    visibility()
end)
local hideCheck = optionCheck('Always hide HUD', -422, 'alwaysHide', function()
    browse = false
    visibility()
    refreshOptions()
end)
place(hideCheck, panel, 190, -422)
local borderToggle = CreateFrame('CheckButton', nil, panel, 'UICheckButtonTemplate')
place(borderToggle, panel, 12, -452)
local borderLabel = label(panel)
borderLabel:SetPoint('LEFT', borderToggle, 'RIGHT', 2, 0)
borderLabel:SetText('Enable Border')
borderToggle:SetScript('OnClick', function(self)
    db.border = not not self:GetChecked()
    updateAppearance()
end)

local function pickColor(field)
    local picker = ColorPickerFrame
    if not picker or not picker.SetupColorPickerAndShow then
        return hint:SetText('Color picker is unavailable on this client.')
    end
    local old = db[field] or badgeBorder
    picker:SetupColorPickerAndShow({
        r = old[1], g = old[2], b = old[3], hasOpacity = false,
        swatchFunc = function()
            db[field] = { picker:GetColorRGB() }
            updateAppearance()
            refreshOptions()
        end,
        cancelFunc = function()
            db[field] = old
            updateAppearance()
            refreshOptions()
        end,
    })
end

local function swatch(field, x, y, parent)
    parent = parent or panel
    local button = CreateFrame('Button', nil, parent)
    button:SetSize(18, 18)
    place(button, parent, x, y)
    local edge = button:CreateTexture(nil, 'BACKGROUND')
    edge:SetAllPoints()
    edge:SetColorTexture(0.7, 0.7, 0.7, 1)
    local color = button:CreateTexture(nil, 'ARTWORK')
    color:SetPoint('TOPLEFT', 2, -2)
    color:SetPoint('BOTTOMRIGHT', -2, 2)
    button:SetScript('OnClick', function() pickColor(field) end)
    return color
end
local borderSwatch = swatch('borderColor', 133, -459)
local badgeSwatch = swatch('minimalBorderColor', 16, -276, compactOptions)
local badgeLabel = label(compactOptions)
badgeLabel:SetText('Border color')
place(badgeLabel, compactOptions, 40, -280)
local backgroundSwatch = swatch('background', 318, -459)
local backgroundLabel = label(panel)
backgroundLabel:SetText('Background color')
place(backgroundLabel, panel, 207, -462)

refreshOptions = function()
    keyText:SetText('Fishing key: ' .. keyLabel(boundKey()))
    doubleCheck:SetChecked(db.doubleClick)
    gearCheck:SetChecked(db.autoRod)
    lureCheck:SetChecked(db.autoLure)
    caughtCheck:SetChecked(db.openCaught)
    ahCheck:SetChecked(db.showAH)
    splashCheck:SetChecked(db.splashBoost)
    minimalCheck:SetChecked(db.minimalHUD)
    compactChecks.minimalVendor:SetChecked(db.minimalVendor ~= false)
    local minimalAH = db.minimalAH
    if minimalAH == nil then minimalAH = db.showAH end
    compactChecks.minimalAH:SetChecked(minimalAH)
    compactChecks.minimalCatches:SetChecked(db.minimalCatches)
    compactChecks.minimalTarget:SetChecked(db.minimalTarget ~= false)
    compactChecks.minimalBorder:SetChecked(db.minimalBorder ~= false)
    local tint = db.minimalBorderColor or badgeBorder
    badgeSwatch:SetColorTexture(tint[1], tint[2], tint[3], 1)
    hideCheck:SetChecked(db.alwaysHide)
    only:SetEnabled(not db.alwaysHide)
    onlyText:SetAlpha(db.alwaysHide and 0.5 or 1)
    local selected = db.lureID and lureName(db.lureID)
    UIDropDownMenu_SetText(lurePicker, selected or 'Select lure')
    only:SetChecked(db.onlyFishing)
    borderToggle:SetChecked(db.border)
    borderSwatch:SetColorTexture(db.borderColor[1], db.borderColor[2], db.borderColor[3], 1)
    backgroundSwatch:SetColorTexture(db.background[1], db.background[2], db.background[3], 1)
    updating = true
    for _, refresh in ipairs(sliders) do
        refresh()
    end
    updating = false
end

grip:SetScript('OnMouseDown', function(self, key)
    if key ~= 'LeftButton' then return end
    local start = GetCursorPosition()
    local minWidth = db.expanded and 265 or 220
    local width = math.max(minWidth, db.width)
    self:SetScript('OnUpdate', function()
        local x = GetCursorPosition()
        db.width = math.max(minWidth, math.min(520, math.floor(width + (x - start) / hud:GetEffectiveScale() + 0.5)))
        layout()
        if panel:IsShown() then
            refreshOptions()
        end
        if not IsMouseButtonDown(1) then
            self:SetScript('OnUpdate', nil)
        end
    end)
end)
grip:SetScript('OnMouseUp', function(self) self:SetScript('OnUpdate', nil) end)
grip:SetScript('OnHide', function(self) self:SetScript('OnUpdate', nil) end)

-- Minimap and commands
local mini = CreateFrame('Button', 'MaliFishingMinimapButton', Minimap)
mini:SetSize(31, 31)
mini:SetFrameLevel(Minimap:GetFrameLevel() + 8)
mini:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
mini:RegisterForDrag('LeftButton')
local fishIcon = mini:CreateTexture(nil, 'ARTWORK')
fishIcon:SetTexture(133888)
fishIcon:SetSize(20, 20)
fishIcon:SetPoint('CENTER')
local ring = mini:CreateTexture(nil, 'OVERLAY')
ring:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
ring:SetSize(53, 53)
ring:SetPoint('TOPLEFT')
local function placeMini()
    local angle = db.angle or 0.8
    mini:ClearAllPoints()
    mini:SetPoint('CENTER', Minimap, 'CENTER', math.cos(angle) * (Minimap:GetWidth() / 2 + 5),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 5))
end
mini:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', function()
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = Minimap:GetCenter()
        db.angle = math.atan2(y / scale - cy, x / scale - cx)
        placeMini()
    end)
end)
mini:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
mini:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:AddLine('MaliFishing')
    GameTooltip:AddLine('Left: toggle HUD | Right: open Options | Drag: move')
    GameTooltip:AddLine('Shift + Left: switch HUD mode')
    GameTooltip:AddLine('Fishing key: ' .. keyLabel(boundKey()))
    GameTooltip:Show()
end)
mini:SetScript('OnLeave', function() GameTooltip:Hide() end)
local function options()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        refreshOptions()
    end
end
local function toggleHUD()
    if db.alwaysHide then return end
    if hud:IsShown() then
        browse, db.hidden = false, true
    else
        db.hidden = false
        browse = db.onlyFishing and not active or false
    end
    visibility()
end
mini:SetScript('OnClick', function(_, button)
    if button == 'RightButton' then
        options()
    elseif button == 'LeftButton' and IsShiftKeyDown() then
        db.minimalHUD = not db.minimalHUD
        applyHUDMode()
        if panel:IsShown() then refreshOptions() end
    elseif button == 'LeftButton' then
        toggleHUD()
    end
end)
SLASH_MALIFISH1 = '/malifish'
SlashCmdList.MALIFISH = function(input)
    local cmd = input:match('^%s*(%S*)%s*(.-)%s*$')
    if cmd == 'bind' or cmd == 'unbind' then
        print('MaliFishing: Options > Keybindings > MaliFishing > Cast / Reel')
    elseif cmd == 'reset' then
        pause(GetTime())
        areas, pending, cast = {}, nil, nil
        if line then
            cast = current()
            active = { spot = cast, started = GetTime() }
        end
        visibility()
        redraw()
        print('MaliFishing: Session reset. All-time catches kept.')
    elseif cmd == 'options' then
        options()
    elseif cmd == '' then
        toggleHUD()
    else
        print('MaliFishing: /malifish options | /malifish reset | /malifish')
    end
end

-- Loot and events
local function captureLoot()
    if pending or not IsFishingLoot or not IsFishingLoot() then
        return
    end
    local slots = {}
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local id = link and tonumber(link:match('item:(%d+)'))
        if id then
            local _, _, count = GetLootSlotInfo(i)
            slots[i] = { id = id, count = count or 1 }
        end
    end
    if next(slots) then
        if db.openCaught then fresh.settle() end
        pending = { spot = cast or current(), slots = slots }
        if db.openCaught then pending.before, pending.received = fresh.snapshot(), {} end
    end
end

local events = CreateFrame('Frame')
for _, event in ipairs({
    'GLOBAL_MOUSE_DOWN', 'GLOBAL_MOUSE_UP', 'PLAYER_REGEN_DISABLED',
    'PLAYER_LOGIN', 'UPDATE_BINDINGS', 'PLAYER_LOGOUT', 'PLAYER_REGEN_ENABLED', 'CVAR_UPDATE',
    'PLAYER_EQUIPMENT_CHANGED', 'ZONE_CHANGED', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED_INDOORS',
    'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP', 'GET_ITEM_INFO_RECEIVED',
    'LOOT_READY', 'LOOT_OPENED', 'LOOT_SLOT_CLEARED', 'LOOT_CLOSED', 'BAG_UPDATE_DELAYED',
}) do
    events:RegisterEvent(event)
end

events:SetScript('OnEvent', function(_, event, arg, success)
    if event == 'PLAYER_LOGIN' then
        MaliFishingDB = MaliFishingDB or {}
        db = MaliFishingDB
        db.history = db.history or {}
        if db.showAH == nil then db.showAH = true end
        db.targetIconSize = math.max(12, math.min(36, math.floor((tonumber(db.targetIconSize) or 18) + 0.5)))
        db.minimalTargetIconSize = math.max(12, math.min(36,
            math.floor((tonumber(db.minimalTargetIconSize) or db.targetIconSize) + 0.5)))
        db.borderThickness = math.max(1, math.min(8, math.floor((tonumber(db.borderThickness) or 1) + 0.5)))
        db.minimalBorderThickness = math.max(1, math.min(12,
            math.floor((tonumber(db.minimalBorderThickness) or 8) + 0.5)))
        db.width, db.scale = db.width or 320, db.scale or 100
        db.iconSize, db.opacity = db.iconSize or 18, db.opacity or 93
        db.background = db.background or { 0, 0, 0 }
        db.borderColor = db.borderColor or { 0.35, 0.35, 0.35 }
        if not db.nativeKeyMigrated and not InCombatLockdown() then
            db.nativeKeyMigrated = true
            local legacy = db.key
            if legacy and not boundKey() then
                local existing = GetBindingAction(legacy)
                if not existing or existing == '' then
                    if SetBinding(legacy, action) then
                        SaveBindings(GetCurrentBindingSet())
                    end
                else
                    print('MaliFishing: Previous key is already assigned. Set Cast / Reel in WoW Keybindings.')
                end
            end
        end
        updateAppearance()
        applyHUDPosition()
        placeMini()
        clickMode()
        sync()
        visibility()
        C_Timer.NewTicker(1, function()
            if active then updateRates() end
        end)
    elseif event == 'UPDATE_BINDINGS' and db then
        soft(line)
        sync()
        if panel:IsShown() then refreshOptions() end
    elseif event == 'PLAYER_LOGOUT' then
        audio.update(false)
        soft(false)
    elseif event == 'GLOBAL_MOUSE_DOWN' and arg == 'RightButton' then
        rightDown()
    elseif event == 'GLOBAL_MOUSE_UP' and arg == 'RightButton' then
        rightUp()
    elseif event == 'PLAYER_REGEN_DISABLED' then
        lastTap, mouseDown = nil, nil
        restoreGeneration = restoreGeneration + 1
        if weapons then restoreWeapons(true) end
    elseif event == 'PLAYER_REGEN_ENABLED' then
        clearMouse()
        line = fishing()
        audio.update(line)
        soft(line)
        clickMode()
        sync()
    elseif event == 'CVAR_UPDATE' then
        for key, entry in pairs(audio.saved) do
            if tostring(arg):lower() == key:lower() and not audio.writing[key]
                and tonumber(GetCVar(key)) ~= entry.applied then audio.saved[key] = nil end
        end
        if tostring(arg):lower() == 'actionbuttonusekeydown' then
            if not InCombatLockdown() then clickMode() end
        end
    elseif event == 'PLAYER_EQUIPMENT_CHANGED' and arg == 16 and not rod(equipped(16)) then
        if weapons and not restoring and not weapons.restoring then weapons = nil end
        pause(GetTime())
        visibility()
        updateRates()
    elseif event == 'ZONE_CHANGED' or event == 'ZONE_CHANGED_NEW_AREA' or event == 'ZONE_CHANGED_INDOORS' then
        if active and active.spot ~= current() then
            pause(GetTime())
        end
        visibility()
        redraw()
    elseif event == 'UNIT_SPELLCAST_CHANNEL_START' and arg == 'player' and fishing() then
        line, browse = true, false
        audio.update(true)
        restoreGeneration = restoreGeneration + 1
        local now = GetTime()
        cast = current()
        if not active or active.spot ~= cast or (active.deadline and now >= active.deadline) then
            pause(now)
            active = { spot = cast, started = now }
        end
        active.deadline = nil
        if not InCombatLockdown() then
            soft(true)
            sync()
        end
        visibility()
        updateRates()
    elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' and arg == 'player' and line then
        line = false
        audio.update(false)
        if not InCombatLockdown() then scheduleRestore() end
        if active then
            local period, deadline = active, GetTime() + 5
            period.deadline = deadline
            C_Timer.After(5, function()
                if active == period and period.deadline == deadline then
                    pause(deadline)
                    updateRates()
                    visibility()
                end
            end)
        end
        soft(false)
        sync()
    elseif event == 'LOOT_READY' or event == 'LOOT_OPENED' then
        if event == 'LOOT_OPENED' then lootOpen = true end
        captureLoot()
    elseif event == 'BAG_UPDATE_DELAYED' then
        if db.openCaught and not pending and not lootOpen then fresh.settle() end
        if panel:IsShown() then refreshOptions() end
    elseif event == 'LOOT_SLOT_CLEARED' and pending then
        local item = pending.slots[arg]
        if item then
            local area = pending.spot
            local history = db.history[area.key]
            if not history then
                history = { zone = area.zone, items = {} }
                db.history[area.key] = history
            end
            area.items[item.id] = (area.items[item.id] or 0) + item.count
            history.items[item.id] = (history.items[item.id] or 0) + item.count
            if pending.received then
                pending.received[item.id] = (pending.received[item.id] or 0) + item.count
            end
            pending.slots[arg] = nil
            redraw()
        end
    elseif event == 'LOOT_CLOSED' then
        if pending and pending.before and next(pending.received) then
            fresh.queue[#fresh.queue + 1] = { before = pending.before, items = pending.received, deadline = GetTime() + 2 }
        end
        pending, lootOpen = nil, false
    elseif event == 'GET_ITEM_INFO_RECEIVED' and success and spot and hud:IsShown() then
        if spot.items[arg] or (db.expanded and breakdown()[arg]) then redraw() end
    end
end)
