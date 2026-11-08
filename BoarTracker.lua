-- BoarTracker
-- Standalone boar spawn tracker for WoW 1.12.1 / OctoWoW.

local PREFIX = "|cffd28b42BoarTracker|r: "
local ICON = "Interface\\AddOns\\BoarTracker\\Textures\\BoarPortrait" -- Fallback portrait.
-- Map each known NPC entry to a 16x16 TGA cropped from its actual unit-frame portrait.
-- A spawn can exist on the map without a live unit token; SetPortraitTexture("target")
-- cannot reproduce NPC-specific portraits for offline map pins.
-- NPC IDs -> CreatureDisplayID mappings load from BoarPortraitDisplays.lua.
-- Only approved unit-frame portrait textures are used; missing variants retain
-- the existing fallback rather than an unrelated model preview.
local function portraitTextureForNPC(npcID)
  local displayID = BoarTrackerDisplayIDs and BoarTrackerDisplayIDs[npcID]
  local filename = displayID and BoarTrackerPortraitTextures and BoarTrackerPortraitTextures[displayID]
  return filename and ("Interface\\AddOns\\BoarTracker\\Textures\\" .. filename) or ICON
end

local PIN_SIZE = 13
local MINI_PIN_SIZE = 12

BoarTracker = BoarTracker or {}
local BT = BoarTracker
BT.version = "0.3.12"
BT.worldPins = {}
BT.miniPins = {}
BT.zoneByName = {}
BT.zoneSpawns = {}
BT.ready = false

local minimapZoom = {
  [0] = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
  [1] = { [0] = 466.6667, [1] = 400, [2] = 333.3333, [3] = 266.6667, [4] = 200, [5] = 133.3333 },
}

local function msg(text)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text) end
end

local function secondsText(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "Unknown" end
  if SecondsToTime then return SecondsToTime(seconds) end
  if seconds >= 3600 then return string.format("%dh %dm", math.floor(seconds / 3600), math.floor(math.mod(seconds, 3600) / 60)) end
  if seconds >= 60 then return string.format("%dm %ds", math.floor(seconds / 60), math.mod(seconds, 60)) end
  return tostring(seconds) .. "s"
end

local function getMapZoneName()
  -- World-map pins are zone-map only. On the Azeroth/continent views
  -- GetCurrentMapZone() is 0; never fall back to the player's real zone
  -- or those pins would be projected onto the higher-level map.
  local continent = GetCurrentMapContinent and GetCurrentMapContinent() or 0
  local zone = GetCurrentMapZone and GetCurrentMapZone() or 0
  if not continent or continent <= 0 or not zone or zone <= 0 or not GetMapZones then
    return nil
  end

  local zones = { GetMapZones(continent) }
  return zones[zone]
end

local function getRealZoneName()
  return GetRealZoneText and GetRealZoneText() or getMapZoneName()
end

local zoomState
local probingZoom = false

local function minimapIndoor(zoom)
  local inside = tonumber(GetCVar("minimapInsideZoom")) or 0
  local outside = tonumber(GetCVar("minimapZoom")) or 0
  if zoomState and zoomState.zoom == zoom and zoomState.inside == inside and zoomState.outside == outside then
    return zoomState.mode
  end

  local mode
  if inside == outside then
    -- Vanilla exposes no indoor query. A temporary zoom change updates
    -- the active CVar. Only probe when the zone or zoom settings change.
    probingZoom = true
    Minimap:SetZoom(zoom >= 3 and zoom - 1 or zoom + 1)
    mode = tonumber(GetCVar("minimapInsideZoom")) ~= inside and 0 or 1
    Minimap:SetZoom(zoom)
    probingZoom = false
  else
    mode = inside == zoom and 0 or 1
  end

  zoomState = { zoom = zoom, inside = inside, outside = outside, mode = mode }
  return mode
end

-- Classic mob "con" colours, calculated from the current player level.
-- Spawn data provides level ranges, so use the highest possible level.
local function mobDifficultyColor(levelText)
  local playerLevel = UnitLevel("player")
  if not playerLevel or playerLevel <= 0 then return 1, .82, .25 end

  local text = tostring(levelText or "")
  local _, _, low, high = string.find(text, "(%d+)%s*%-%s*(%d+)")
  local mobLevel = tonumber(high) or tonumber(text)
  if not mobLevel then
    if text == "??" then return .65, .1, .1 end
    return 1, .82, .25
  end

  local difference = mobLevel - playerLevel
  if difference >= 10 then return .65, .1, .1 end -- Skull: dark red
  if difference >= 5 then return 1, .15, .15 end -- Red
  if difference >= 3 then return 1, .5, 0 end -- Orange
  if difference >= -2 then return 1, .92, 0 end -- Yellow

  -- Grey (no-XP) threshold scales with level in Vanilla WoW.
  local greyLevel
  if playerLevel <= 5 then
    greyLevel = 0
  elseif playerLevel <= 39 then
    greyLevel = playerLevel - math.floor(playerLevel / 10) - 5
  elseif playerLevel <= 59 then
    greyLevel = playerLevel - math.floor(playerLevel / 5) - 1
  else
    greyLevel = playerLevel - 9
  end

  if mobLevel <= greyLevel then return .55, .55, .55 end -- Grey
  return .2, .9, .2 -- Green
end

local function pinTooltip(pin, world)
  local data = pin.spawn
  if not data then return end
  local tip = world and WorldMapTooltip or GameTooltip
  if not tip then return end
  tip:SetOwner(pin, "ANCHOR_LEFT")
  local r, g, b = mobDifficultyColor(data.level)
  tip:SetText(data.name, r, g, b)
  tip:AddDoubleLine("Level:", data.level or "?", .75, .75, .75, 1, 1, 1)
  tip:AddDoubleLine("NPC ID:", tostring(data.id or "?"), .75, .75, .75, 1, 1, 1)
  tip:AddDoubleLine("Respawn:", secondsText(data.respawn), .75, .75, .75, 1, 1, 1)
  tip:AddDoubleLine("Location:", string.format("%.1f, %.1f", data.x, data.y), .75, .75, .75, 1, 1, 1)
  if data.zoneName then tip:AddLine(data.zoneName, .65, .8, 1) end
  tip:Show()
end

local function hideTooltip(world)
  local tip = world and WorldMapTooltip or GameTooltip
  if tip then tip:Hide() end
end

local function makePin(parent, world)
  local pin = CreateFrame("Button", nil, parent)
  pin:SetWidth(world and PIN_SIZE or MINI_PIN_SIZE)
  pin:SetHeight(world and PIN_SIZE or MINI_PIN_SIZE)
  pin:EnableMouse(true)
  -- Both maps keep their spawn markers below the native player marker.
  local parentLevel = (parent.GetFrameLevel and parent:GetFrameLevel() or 1)
  pin:SetFrameLevel(parentLevel + 1)

  local tex = pin:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(pin)
  tex:SetTexture(ICON)
  pin.texture = tex

  pin:SetScript("OnEnter", function() pinTooltip(this, world) end)
  pin:SetScript("OnLeave", function() hideTooltip(world) end)
  return pin
end

-- Pin frames are pooled and reused for different spawns, so the portrait must be
-- updated whenever the NPC ID changes on either the world map or minimap.
local function setPinSpawn(pin, spawn)
  pin.spawn = spawn
  if pin.portraitID ~= spawn.id then
    pin.texture:SetTexture(portraitTextureForNPC(spawn.id))
    pin.portraitID = spawn.id
  end
end

-- In WoW 1.12, the actual world-map direction arrow is an unnamed 3D Model
-- directly under WorldMapFrame. WorldMapPlayer is only its mouseover target.
-- Raising the Model (as Vanilla pfQuest does) fixes visual stacking without
-- deleting, hiding or repositioning any spawn pin.
local function keepWorldMapPlayerOnTop()
  if not WorldMapFrame then return end
  for _, child in pairs({ WorldMapFrame:GetChildren() }) do
    if child:IsObjectType("Model") and not child:GetName() then
      local model = child:GetModel()
      if model and string.find(string.lower(model), "interface\\minimap\\minimaparrow", 1, true) then
        if child:GetFrameLevel() < 255 then child:SetFrameLevel(255) end
        return
      end
    end
  end
end

function BT:BuildIndex()
  self.zoneByName = {}
  self.zoneSpawns = {}
  self.boarNames = {}
  if not BoarTrackerData or not BoarTrackerData.zones or not BoarTrackerData.boars then return end

  for zoneID, zone in pairs(BoarTrackerData.zones) do
    self.zoneByName[zone.name] = zoneID
    self.zoneSpawns[zoneID] = self.zoneSpawns[zoneID] or {}
  end

  for id, boar in pairs(BoarTrackerData.boars) do
    self.boarNames[string.lower(boar.name)] = boar.name
    for zoneID, encoded in pairs(boar.points or {}) do
      if self.zoneSpawns[zoneID] then
        for point in string.gfind(encoded, "[^;]+") do
          local _, _, sx, sy, sr = string.find(point, "([^,]+),([^,]+),([^,]+)")
          if sx and sy then
            table.insert(self.zoneSpawns[zoneID], {
              id = id,
              name = boar.name,
              level = boar.level,
              rank = boar.rank,
              x = tonumber(sx),
              y = tonumber(sy),
              zone = zoneID,
              zoneName = BoarTrackerData.zones[zoneID] and BoarTrackerData.zones[zoneID].name or tostring(zoneID),
              respawn = tonumber(sr) or 0,
            })
          end
        end
      end
    end
  end
end

function BT:GetZoneID(name)
  return name and self.zoneByName[name] or nil
end

function BT:HideWorldPins(from)
  if not from then self.worldLayout = nil end
  local start = from or 1
  for i = start, table.getn(self.worldPins) do
    if self.worldPins[i] then self.worldPins[i]:Hide() end
  end
end

function BT:HideMiniPins(from)
  if not from then self.miniLayout = nil end
  local start = from or 1
  for i = start, self.visibleMiniPins or 0 do
    self.miniPins[i]:Hide()
  end
  self.visibleMiniPins = start - 1
end

function BT:UpdateWorldMap()
  if not self.ready or not WorldMapFrame or not WorldMapButton then return end
  if not BoarTrackerDB.showWorld then self:HideWorldPins(); return end
  -- Run before the layout cache can short-circuit: the client may redraw its arrow.
  keepWorldMapPlayerOnTop()

  local zoneName = getMapZoneName()
  local zoneID = self:GetZoneID(zoneName)
  local spawns = zoneID and self.zoneSpawns[zoneID]
  if not spawns then self:HideWorldPins(); return end

  local width = WorldMapButton:GetWidth()
  local height = WorldMapButton:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then return end

  local layout = self.worldLayout
  if layout and layout.zone == zoneID and layout.width == width and layout.height == height then return end
  self.worldLayout = { zone = zoneID, width = width, height = height }

  local i = 1
  for _, spawn in pairs(spawns) do
    local pin = self.worldPins[i]
    if not pin then
      pin = makePin(WorldMapButton, true)
      self.worldPins[i] = pin
    end
    setPinSpawn(pin, spawn)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", spawn.x / 100 * width, -spawn.y / 100 * height)
    pin:Show()
    i = i + 1
  end
  self:HideWorldPins(i)
end

function BT:UpdateMinimap()
  if not self.ready or not Minimap or probingZoom then return end
  if not BoarTrackerDB.showMini then self:HideMiniPins(); return end

  local zoneName = getRealZoneName()
  local zoneID = self:GetZoneID(zoneName)
  local zone = zoneID and BoarTrackerData.zones[zoneID]
  local spawns = zoneID and self.zoneSpawns[zoneID]
  if not zone or not spawns or not zone.width or zone.width <= 0 then self:HideMiniPins(); return end

  local xPlayer, yPlayer = GetPlayerMapPosition("player")
  if not xPlayer or not yPlayer or (xPlayer == 0 and yPlayer == 0) then self:HideMiniPins(); return end
  xPlayer, yPlayer = xPlayer * 100, yPlayer * 100

  local zoom = Minimap:GetZoom()
  local indoor = minimapIndoor(zoom)
  local yards = minimapZoom[indoor][zoom]
  if not yards then self:HideMiniPins(); return end

  local width, height = Minimap:GetWidth(), Minimap:GetHeight()
  local layout = self.miniLayout
  if layout and layout.zone == zoneID and layout.x == xPlayer and layout.y == yPlayer
    and layout.yards == yards and layout.width == width and layout.height == height then return end

  if not layout then
    layout = {}
    self.miniLayout = layout
  end
  layout.zone, layout.x, layout.y = zoneID, xPlayer, yPlayer
  layout.yards, layout.width, layout.height = yards, width, height

  local xDraw = width * zone.width / yards / 100
  local yDraw = height * zone.height / yards / 100
  local radius = math.min(width, height) / 2 - 7
  local radiusSquared = radius * radius
  local i = 1

  for _, spawn in pairs(spawns) do
    local xPos = (spawn.x - xPlayer) * xDraw
    local yPos = (spawn.y - yPlayer) * yDraw
    -- Only cull pins outside the minimap. NEVER hide a nearby boar spawn.
    if radius > 0 and xPos * xPos + yPos * yPos < radiusSquared then
      local pin = self.miniPins[i]
      if not pin then
        pin = makePin(Minimap, false)
        self.miniPins[i] = pin
      end
      setPinSpawn(pin, spawn)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", Minimap, "CENTER", xPos, -yPos)
      pin:Show()
      i = i + 1
    end
  end
  self:HideMiniPins(i)
end

function BT:Status()
  local types, spawns = 0, 0
  for _, boar in pairs(BoarTrackerData.boars or {}) do
    types = types + 1
    for _, encoded in pairs(boar.points or {}) do
      for _ in string.gfind(encoded, "[^;]+") do spawns = spawns + 1 end
    end
  end
  msg(string.format("v%s — %d boar types, %d recorded spawn points. Map %s, minimap %s.", self.version, types, spawns, BoarTrackerDB.showWorld and "ON" or "OFF", BoarTrackerDB.showMini and "ON" or "OFF"))
end

local function combatPattern(format)
  local pattern = string.gsub(format, "(%W)", "%%%1")
  pattern = string.gsub(pattern, "%%%%s", "(.+)")
  return string.gsub(pattern, "%%%%d", "(%%d+)")
end

local slainPattern = "^" .. combatPattern(SELFKILLOTHER or "You have slain %s!") .. "$"
-- The base message is also the prefix of the rested, group and raid variants.
local xpPattern = "^" .. combatPattern(COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience.")
local xpWindow = 20
local rateStart
local rateXP = 0
local lastCombatTime
local rateIdleTimeout = 300

local function resetIdleRate(now)
  if rateStart and lastCombatTime and now - lastCombatTime >= rateIdleTimeout then
    rateStart = nil
    rateXP = 0
    lastCombatTime = nil
    return true
  end
end

function BT:RecordBoarXP(message)
  local _, _, name, amount = string.find(message or "", xpPattern)
  local xp = tonumber(amount)
  if not xp or xp <= 0 or not self.boarNames[string.lower(name)] then return end

  local now = GetTime()
  resetIdleRate(now)
  lastCombatTime = now
  local samples = BoarTrackerKills.xpSamples
  if table.getn(samples) == xpWindow then table.remove(samples, 1) end
  table.insert(samples, xp)
  -- Measure from the first kill, so time spent before grinding is excluded.
  if rateStart then
    rateXP = rateXP + xp
  else
    rateStart = now
  end
end

local function boarsToLevel()
  local required = UnitXPMax("player")
  if required <= 0 then return end

  local remaining = math.max(0, required - UnitXP("player"))
  local samples = BoarTrackerKills.xpSamples
  local count = table.getn(samples)
  if count == 0 then return remaining end

  local total = 0
  for i = 1, count do total = total + samples[i] end
  return remaining, total / count, count, math.ceil(remaining * count / total)
end

function BT:ShowXP()
  local remaining, average, count, estimate = boarsToLevel()
  if not remaining then
    msg("No XP is needed for another level.")
  elseif not estimate then
    msg(string.format("%d XP to next level. Kill a boar that grants XP to start the estimate.", remaining))
  else
    msg(string.format("%d XP to next level. Average %.1f XP per boar (%d sampled). About %d more boars.",
      remaining, average, count, estimate))
  end
end

local xpTracker
local nextTrackerUpdate = 0

local function stopTrackerDrag()
  if not this.dragging then return end
  this:StopMovingOrSizing()
  this.dragging = nil

  local x, y = this:GetCenter()
  local parentX, parentY = UIParent:GetCenter()
  BoarTrackerDB.trackerX, BoarTrackerDB.trackerY = x - parentX, y - parentY
  this:ClearAllPoints()
  this:SetPoint("CENTER", UIParent, "CENTER", BoarTrackerDB.trackerX, BoarTrackerDB.trackerY)
end

local function updateXPTracker()
  if not BoarTrackerDB.showXPTracker then
    if xpTracker then xpTracker:Hide() end
    return
  end

  if not xpTracker then
    xpTracker = CreateFrame("Frame", nil, UIParent)
    xpTracker:SetWidth(330)
    xpTracker:SetHeight(24)
    xpTracker:SetPoint("CENTER", UIParent, "CENTER", BoarTrackerDB.trackerX or 0, BoarTrackerDB.trackerY or -120)
    xpTracker:SetMovable(true)
    xpTracker:SetClampedToScreen(true)
    xpTracker:EnableMouse(true)
    xpTracker:RegisterForDrag("LeftButton")
    xpTracker:SetScript("OnDragStart", function()
      if IsShiftKeyDown() then
        this.dragging = true
        this:StartMoving()
      end
    end)
    xpTracker:SetScript("OnDragStop", stopTrackerDrag)
    xpTracker:SetScript("OnHide", stopTrackerDrag)

    local label = xpTracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", xpTracker, "CENTER")
    xpTracker.label = label
  end

  local remaining, _, _, estimate = boarsToLevel()
  if not remaining then
    xpTracker.label:SetText("No XP needed")
  elseif not estimate then
    xpTracker.label:SetText("Kill a boar to estimate")
  else
    local label = string.format("~%d %s to level up", estimate, estimate == 1 and "boar" or "boars")
    local elapsed = rateStart and GetTime() - rateStart or 0
    if rateXP > 0 and elapsed > 0 then
      local perHour = rateXP * 3600 / elapsed
      local minutes = math.ceil(remaining * elapsed / rateXP / 60)
      local eta = minutes >= 60
        and string.format("%dh %02dm", math.floor(minutes / 60), math.mod(minutes, 60))
        or string.format("%dm", minutes)
      label = string.format("%s  |  %.0f XP/h  |  ~%s", label, perHour, eta)
    else
      label = label .. "  |  Calculating XP/h and ETA"
    end
    xpTracker.label:SetText(label)
  end
  xpTracker:Show()
end

function BT:RecordKill(message)
  local _, _, name = string.find(message or "", slainPattern)
  if not name then return end
  local key = string.lower(name)
  local boar = self.boarNames[key]
  if not boar then return end

  local db = BoarTrackerKills
  local count = (db.byName[key] or 0) + 1
  db.byName[key] = count
  db.total = db.total + 1
  if math.mod(db.total, 50) == 0 then
    msg(string.format("%d boars killed total (%d × %s).", db.total, count, boar))
  end
end

function BT:ShowKills(name)
  if name == "" then
    if not UnitIsPlayer("target") then name = UnitName("target") end
    if not name or name == "" then
      msg(string.format("%d boars killed total. Target a boar or use /bt killed <name>.", BoarTrackerKills.total))
      return
    end
  end

  local key = string.lower(name)
  local boar = self.boarNames[key]
  if boar then
    msg(string.format("%s killed: %d (%d boars total).", boar, BoarTrackerKills.byName[key] or 0, BoarTrackerKills.total))
  else
    msg("Unknown boar. Target a boar or use /bt killed <name>.")
  end
end

SLASH_BOARTRACKER1 = "/boartracker"
SLASH_BOARTRACKER2 = "/bt"
SlashCmdList["BOARTRACKER"] = function(input)
  input = string.lower(input or "")
  input = string.gsub(input, "^%s*(.-)%s*$", "%1")
  local _, _, name = string.find(input, "^killed%s+(.+)$")
  if input == "killed" or name then
    BT:ShowKills(name or "")
  elseif input == "xp" then
    BT:ShowXP()
  elseif input == "tracker on" or input == "tracker off" then
    BoarTrackerDB.showXPTracker = input == "tracker on"
    updateXPTracker()
    msg(BoarTrackerDB.showXPTracker and "XP tracker enabled. Shift-drag to move." or "XP tracker disabled.")
  elseif input == "map" then
    BoarTrackerDB.showWorld = not BoarTrackerDB.showWorld
    BT:UpdateWorldMap()
    msg("World-map pins " .. (BoarTrackerDB.showWorld and "enabled." or "disabled."))
  elseif input == "mini" or input == "minimap" then
    BoarTrackerDB.showMini = not BoarTrackerDB.showMini
    BT:UpdateMinimap()
    msg("Minimap pins " .. (BoarTrackerDB.showMini and "enabled." or "disabled."))
  elseif input == "on" then
    BoarTrackerDB.showWorld = true
    BoarTrackerDB.showMini = true
    BT:UpdateWorldMap(); BT:UpdateMinimap(); msg("Enabled.")
  elseif input == "off" then
    BoarTrackerDB.showWorld = false
    BoarTrackerDB.showMini = false
    BT:HideWorldPins(); BT:HideMiniPins(); msg("Disabled.")
  else
    BT:Status()
    msg("Commands: /bt map, /bt mini, /bt on, /bt off, /bt killed [name], /bt xp, /bt tracker on/off")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("MINIMAP_ZONE_CHANGED")
frame:RegisterEvent("WORLD_MAP_UPDATE")
frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function()
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    local now = GetTime()
    -- Check the old gap before new combat can overwrite its timestamp.
    local reset = resetIdleRate(now)
    lastCombatTime = now
    if reset and BT.ready then updateXPTracker() end
    return
  end
  if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    if BT.ready then BT:RecordKill(arg1) end
    return
  end
  if event == "CHAT_MSG_COMBAT_XP_GAIN" then
    if BT.ready then
      BT:RecordBoarXP(arg1)
      updateXPTracker()
    end
    return
  end
  if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
    if BT.ready then updateXPTracker() end
    return
  end
  if probingZoom then return end
  if event == "PLAYER_ENTERING_WORLD" and not BT.ready then
    BoarTrackerDB = BoarTrackerDB or {}
    if BoarTrackerDB.showWorld == nil then BoarTrackerDB.showWorld = true end
    if BoarTrackerDB.showMini == nil then BoarTrackerDB.showMini = true end
    BoarTrackerKills = BoarTrackerKills or { total = 0, byName = {} }
    BoarTrackerKills.xpSamples = BoarTrackerKills.xpSamples or {}
    BT:BuildIndex()
    BT.ready = true
    updateXPTracker()
    msg("Loaded standalone v" .. BT.version .. ". No pfQuest required. /bt for status.")
  end
  if BT.ready then
    BT:UpdateWorldMap()
    if event ~= "WORLD_MAP_UPDATE" then
      zoomState = nil
      BT:UpdateMinimap()
    end
  end
end)

frame:SetScript("OnUpdate", function()
  if not BT.ready then return end
  local now = GetTime()
  if UnitAffectingCombat("player") then
    lastCombatTime = now
  elseif resetIdleRate(now) then
    updateXPTracker()
  end
  if not BoarTrackerDB.showMini and not BoarTrackerDB.showXPTracker then return end
  if BoarTrackerDB.showXPTracker and rateXP > 0 and now >= nextTrackerUpdate then
    nextTrackerUpdate = now + 5
    updateXPTracker()
  end
  if not BoarTrackerDB.showMini then return end
  if (this.nextMiniUpdate or 0) > now then return end
  this.nextMiniUpdate = now + 0.25
  BT:UpdateMinimap()
end)
