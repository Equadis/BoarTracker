-- BoarTracker
-- Standalone boar spawn tracker for WoW 1.12.1 / OctoWoW.

local PREFIX = "|cffd28b42BoarTracker|r: "
local ICON = "Interface\\Icons\\Ability_Hunter_Pet_Boar"
local PIN_SIZE = 13
local MINI_PIN_SIZE = 12

BoarTracker = BoarTracker or {}
local BT = BoarTracker
BT.version = "0.2.0"
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
  local continent = GetCurrentMapContinent and GetCurrentMapContinent() or 0
  local zone = GetCurrentMapZone and GetCurrentMapZone() or 0
  if continent and continent > 0 and zone and zone > 0 and GetMapZones then
    local zones = { GetMapZones(continent) }
    if zones[zone] then return zones[zone] end
  end
  if GetRealZoneText then return GetRealZoneText() end
  return nil
end

local function getRealZoneName()
  return GetRealZoneText and GetRealZoneText() or getMapZoneName()
end

local function minimapIndoor()
  local tempzoom = 0
  local state = 1
  local inside = tonumber(GetCVar("minimapInsideZoom")) or 0
  local outside = tonumber(GetCVar("minimapZoom")) or 0

  if outside == inside then
    if inside >= 3 then
      Minimap:SetZoom(Minimap:GetZoom() - 1)
      tempzoom = 1
    else
      Minimap:SetZoom(Minimap:GetZoom() + 1)
      tempzoom = -1
    end
  end

  if inside == Minimap:GetZoom() then state = 0 end
  Minimap:SetZoom(Minimap:GetZoom() + tempzoom)
  return state
end

local function pinTooltip(pin, world)
  local data = pin.spawn
  if not data then return end
  local tip = world and WorldMapTooltip or GameTooltip
  if not tip then return end
  tip:SetOwner(pin, "ANCHOR_LEFT")
  tip:SetText(data.name, 1, .82, .25)
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
  pin:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 8)

  local tex = pin:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(pin)
  tex:SetTexture(ICON)
  pin.texture = tex

  pin:SetScript("OnEnter", function() pinTooltip(this, world) end)
  pin:SetScript("OnLeave", function() hideTooltip(world) end)
  return pin
end

function BT:BuildIndex()
  self.zoneByName = {}
  self.zoneSpawns = {}
  if not BoarTrackerData or not BoarTrackerData.zones or not BoarTrackerData.boars then return end

  for zoneID, zone in pairs(BoarTrackerData.zones) do
    self.zoneByName[zone.name] = zoneID
    self.zoneSpawns[zoneID] = self.zoneSpawns[zoneID] or {}
  end

  for id, boar in pairs(BoarTrackerData.boars) do
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
  local start = from or 1
  for i = start, table.getn(self.worldPins) do
    if self.worldPins[i] then self.worldPins[i]:Hide() end
  end
end

function BT:HideMiniPins(from)
  local start = from or 1
  for i = start, table.getn(self.miniPins) do
    if self.miniPins[i] then self.miniPins[i]:Hide() end
  end
end

function BT:UpdateWorldMap()
  if not self.ready or not WorldMapFrame or not WorldMapButton then return end
  if not BoarTrackerDB.showWorld then self:HideWorldPins(1); return end

  local zoneName = getMapZoneName()
  local zoneID = self:GetZoneID(zoneName)
  local spawns = zoneID and self.zoneSpawns[zoneID]
  if not spawns then self:HideWorldPins(1); return end

  local width = WorldMapButton:GetWidth()
  local height = WorldMapButton:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then return end

  local i = 1
  for _, spawn in pairs(spawns) do
    local pin = self.worldPins[i]
    if not pin then
      pin = makePin(WorldMapButton, true)
      self.worldPins[i] = pin
    end
    pin.spawn = spawn
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", spawn.x / 100 * width, -spawn.y / 100 * height)
    pin:Show()
    i = i + 1
  end
  self:HideWorldPins(i)
end

function BT:UpdateMinimap()
  if not self.ready or not Minimap then return end
  if not BoarTrackerDB.showMini then self:HideMiniPins(1); return end

  local zoneName = getRealZoneName()
  local zoneID = self:GetZoneID(zoneName)
  local zone = zoneID and BoarTrackerData.zones[zoneID]
  local spawns = zoneID and self.zoneSpawns[zoneID]
  if not zone or not spawns or not zone.width or zone.width <= 0 then self:HideMiniPins(1); return end

  local xPlayer, yPlayer = GetPlayerMapPosition("player")
  if not xPlayer or not yPlayer or (xPlayer == 0 and yPlayer == 0) then self:HideMiniPins(1); return end
  xPlayer, yPlayer = xPlayer * 100, yPlayer * 100

  local zoom = Minimap:GetZoom()
  local indoor = minimapIndoor()
  local yards = minimapZoom[indoor] and minimapZoom[indoor][zoom]
  if not yards then self:HideMiniPins(1); return end

  local xScale = yards / zone.width
  local yScale = yards / zone.height
  local xDraw = Minimap:GetWidth() / xScale / 100
  local yDraw = Minimap:GetHeight() / yScale / 100
  local halfW = Minimap:GetWidth() / 2
  local halfH = Minimap:GetHeight() / 2
  local i = 1

  for _, spawn in pairs(spawns) do
    local xPos = (spawn.x - xPlayer) * xDraw
    local yPos = (spawn.y - yPlayer) * yDraw
    local distance = math.sqrt(xPos * xPos + yPos * yPos)
    local radius = math.min(halfW, halfH) - 7
    if distance < radius then
      local pin = self.miniPins[i]
      if not pin then
        pin = makePin(Minimap, false)
        self.miniPins[i] = pin
      end
      pin.spawn = spawn
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

SLASH_BOARTRACKER1 = "/boartracker"
SLASH_BOARTRACKER2 = "/bt"
SlashCmdList["BOARTRACKER"] = function(input)
  input = string.lower(input or "")
  input = string.gsub(input, "^%s*(.-)%s*$", "%1")
  if input == "map" then
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
    BT:HideWorldPins(1); BT:HideMiniPins(1); msg("Disabled.")
  else
    BT:Status()
    msg("Commands: /bt map, /bt mini, /bt on, /bt off")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("MINIMAP_ZONE_CHANGED")
frame:RegisterEvent("WORLD_MAP_UPDATE")
frame:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    BoarTrackerDB = BoarTrackerDB or {}
    if BoarTrackerDB.showWorld == nil then BoarTrackerDB.showWorld = true end
    if BoarTrackerDB.showMini == nil then BoarTrackerDB.showMini = true end
    BT:BuildIndex()
    BT.ready = true
    msg("Loaded standalone v" .. BT.version .. ". No pfQuest required. /bt for status.")
  end
  if BT.ready then
    BT:UpdateWorldMap()
    BT:UpdateMinimap()
  end
end)

frame:SetScript("OnUpdate", function()
  if not BT.ready then return end
  if (this.nextMiniUpdate or 0) > GetTime() then return end
  this.nextMiniUpdate = GetTime() + 0.25
  BT:UpdateMinimap()
end)
