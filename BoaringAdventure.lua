-- Boaring Adventure
-- WoW 1.12.1 / OctoWoW
-- A boar-only frontend for pfQuest's NPC database and map renderer.

local ADDON = "BoaringAdventure"
local PREFIX = "|cffd28b42Boaring Adventure|r: "

BoaringAdventure = BoaringAdventure or {}
local BA = BoaringAdventure
BA.version = "0.1.0"
BA.boars = {}
BA.byid = {}
BA.ready = false
BA.originalAddNode = nil
BA.filterInstalled = false

local namedBoars = {
  ["longsnout"] = true,
  ["bellygrub"] = true,
  ["princess"] = true,
  ["grunter"] = true,
  ["raging agam'ar"] = true,
  ["rotting agam'ar"] = true,
  ["enraged agam'ar"] = true,
}

local function msg(text)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text) end
end

local function trim(text)
  if not text then return "" end
  return string.gsub(text, "^%s*(.-)%s*$", "%1")
end

local function lower(text)
  return string.lower(text or "")
end

local function isExcludedName(name)
  local n = lower(name)
  if string.find(n, "quilboar", 1, true) then return true end
  if n == "tamed boar" then return true end
  if n == "boar spirit" then return true end
  if string.find(n, "piglet", 1, true) then return true end
  return false
end

local function isBoarName(name)
  if not name or isExcludedName(name) then return false end
  local n = lower(name)
  if namedBoars[n] then return true end
  if string.find(n, "goretusk", 1, true) then return true end
  if string.find(n, "boar", 1, true) then return true end
  return false
end

local function hasCoords(data)
  if not data or not data.coords then return false end
  for _ in pairs(data.coords) do return true end
  return false
end

local function isFriendly(id)
  if pfDatabase and pfDatabase.IsFriendly then return pfDatabase:IsFriendly(id) end
  return false
end

local function countCoords(coords)
  local count = 0
  if coords then for _ in pairs(coords) do count = count + 1 end end
  return count
end

local function getLocalizedName(id, fallback)
  if pfDB and pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][id] then
    return pfDB["units"]["loc"][id]
  end
  return fallback
end

function BA:BuildIndex()
  self.boars = {}
  self.byid = {}
  if not pfDB or not pfDB["units"] then return 0 end

  local names = pfDB["units"]["enUS"] or pfDB["units"]["loc"] or {}
  local data = pfDB["units"]["data"] or {}

  for id, englishName in pairs(names) do
    local unit = data[id]
    if isBoarName(englishName) and hasCoords(unit) and not isFriendly(id) then
      local entry = {
        id = id,
        english = englishName,
        name = getLocalizedName(id, englishName),
        lvl = unit.lvl or "?",
        coords = unit.coords,
        spawns = countCoords(unit.coords),
      }
      table.insert(self.boars, entry)
      self.byid[id] = entry
    end
  end

  table.sort(self.boars, function(a, b)
    local an = lower(a.name)
    local bn = lower(b.name)
    if an == bn then return a.id < b.id end
    return an < bn
  end)

  return table.getn(self.boars)
end

function BA:IsOurMeta(meta)
  return meta and meta.addon == ADDON
end

function BA:InstallBoarOnlyFilter()
  if self.filterInstalled or not pfMap or not pfMap.AddNode then return end
  self.originalAddNode = pfMap.AddNode
  local original = self.originalAddNode

  pfMap.AddNode = function(frame, meta)
    if BoaringAdventureDB and BoaringAdventureDB.boarOnly and not BA:IsOurMeta(meta) then return end
    return original(frame, meta)
  end

  self.filterInstalled = true
end

function BA:RemoveBoarOnlyFilter()
  if not self.filterInstalled then return end
  if pfMap and self.originalAddNode then pfMap.AddNode = self.originalAddNode end
  self.filterInstalled = false
end

function BA:ClearOtherNodes()
  if not pfMap or not pfMap.nodes or not pfMap.DeleteNode then return end
  local remove = {}
  for addon in pairs(pfMap.nodes) do
    if addon ~= ADDON then table.insert(remove, addon) end
  end
  for _, addon in pairs(remove) do pfMap:DeleteNode(addon) end
end

function BA:ClearBoars()
  if pfMap and pfMap.DeleteNode then pfMap:DeleteNode(ADDON) end
  if pfMap and pfMap.UpdateNodes then pfMap:UpdateNodes() end
end

function BA:Matches(entry, query)
  if not query or query == "" then return true end
  local q = lower(query)
  if string.find(lower(entry.name), q, 1, true) then return true end
  if string.find(lower(entry.english), q, 1, true) then return true end
  if tostring(entry.id) == q then return true end
  return false
end

function BA:ShowBoars(query, jumpToBestMap)
  if not self.ready then return end
  self:ClearBoars()

  local maps = {}
  local matches = 0
  local spawnCount = 0

  for _, entry in pairs(self.boars) do
    if self:Matches(entry, query) then
      local meta = { addon = ADDON }
      maps = pfDatabase:SearchMobID(entry.id, meta, maps) or maps
      matches = matches + 1
      spawnCount = spawnCount + entry.spawns
    end
  end

  if pfMap and pfMap.UpdateNodes then pfMap:UpdateNodes() end

  if jumpToBestMap and matches > 0 and pfDatabase.GetBestMap and pfMap.ShowMapID then
    local best = pfDatabase:GetBestMap(maps)
    if best then pfMap:ShowMapID(best) end
  end

  if query and query ~= "" then
    msg(string.format("Showing %d boar type(s), %d recorded spawn point(s) matching |cffffffff%s|r.", matches, spawnCount, query))
  end
end

function BA:GetZones(entry)
  local zones = {}
  local seen = {}
  if not entry or not entry.coords then return zones end

  for _, coord in pairs(entry.coords) do
    local zone = coord[3]
    if zone and not seen[zone] then
      seen[zone] = true
      local name = pfMap and pfMap.GetMapNameByID and pfMap:GetMapNameByID(zone) or tostring(zone)
      table.insert(zones, name or tostring(zone))
    end
  end

  table.sort(zones)
  return zones
end

function BA:Info(query)
  query = trim(query)
  if query == "" then
    msg("Usage: |cffffffff/boar info <name or npc id>|r")
    return
  end

  local found = 0
  for _, entry in pairs(self.boars) do
    if self:Matches(entry, query) then
      local zones = self:GetZones(entry)
      local zoneText = table.concat(zones, ", ")
      msg(string.format("|cffffffff%s|r — level %s, NPC %d, %d spawn point(s)%s", entry.name, tostring(entry.lvl), entry.id, entry.spawns, zoneText ~= "" and ", " .. zoneText or ""))
      found = found + 1
    end
  end

  if found == 0 then msg("No indexed enemy boar matched |cffffffff" .. query .. "|r.") end
end

function BA:List(query)
  query = trim(query)
  local shown = 0
  for _, entry in pairs(self.boars) do
    if query == "" or self:Matches(entry, query) then
      msg(string.format("|cffffffff%s|r — lvl %s — NPC %d — %d spawn(s)", entry.name, tostring(entry.lvl), entry.id, entry.spawns))
      shown = shown + 1
    end
  end
  msg(string.format("%d boar type(s) listed.", shown))
end

function BA:SetFilter(enabled)
  BoaringAdventureDB.boarOnly = enabled and true or false
  if BoaringAdventureDB.boarOnly then
    self:InstallBoarOnlyFilter()
    self:ClearOtherNodes()
    self:ShowBoars(nil, false)
    msg("Strict boar-only map filtering |cff55ff55enabled|r.")
  else
    msg("Strict boar-only map filtering |cffffaa55disabled|r. Existing boar pins remain until cleared.")
  end
end

function BA:Status()
  msg(string.format("v%s — %d enemy boar type(s) indexed. Boar-only filter: %s.", self.version, table.getn(self.boars), BoaringAdventureDB.boarOnly and "ON" or "OFF"))
end

function BA:Help()
  msg("Commands:")
  msg("|cffffffff/boar all|r — show all boar spawns")
  msg("|cffffffff/boar <name>|r — show matching boar spawns")
  msg("|cffffffff/boar info <name/id>|r — boar details")
  msg("|cffffffff/boar list [text]|r — list indexed boars")
  msg("|cffffffff/boar clean|r — clear boar pins")
  msg("|cffffffff/boar filter on|off — strict boar-only pfQuest map mode")
  msg("|cffffffff/boar status|r — database status")
end

SLASH_BOARINGADVENTURE1 = "/boar"
SlashCmdList["BOARINGADVENTURE"] = function(input)
  input = trim(input)
  local _, _, command, rest = string.find(input, "^(%S+)%s*(.-)%s*$")
  command = lower(command or "")
  rest = rest or ""

  if command == "" or command == "help" then BA:Help()
  elseif command == "all" then BA:ShowBoars(nil, false)
  elseif command == "clean" then BA:ClearBoars(); msg("Boar pins cleared.")
  elseif command == "info" then BA:Info(rest)
  elseif command == "list" then BA:List(rest)
  elseif command == "status" then BA:Status()
  elseif command == "filter" then
    local state = lower(trim(rest))
    if state == "on" then BA:SetFilter(true)
    elseif state == "off" then BA:SetFilter(false)
    else msg("Usage: |cffffffff/boar filter on|off|r") end
  else BA:ShowBoars(input, true) end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
  if BA.ready then return end
  if not pfDB or not pfDatabase or not pfMap then
    msg("|cffff5555pfQuest was not ready. Boaring Adventure requires pfQuest.|r")
    return
  end

  BoaringAdventureDB = BoaringAdventureDB or {}
  if BoaringAdventureDB.boarOnly == nil then BoaringAdventureDB.boarOnly = true end

  local count = BA:BuildIndex()
  BA.ready = true

  if BoaringAdventureDB.boarOnly then
    BA:InstallBoarOnlyFilter()
    BA:ClearOtherNodes()
  end

  BA:ShowBoars(nil, false)
  msg(string.format("Loaded v%s with %d enemy boar type(s). /boar for commands.", BA.version, count))
  this:UnregisterAllEvents()
end)
