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

-- Named boars whose creature names do not contain "boar" or "goretusk".
-- These are deliberately explicit so similarly named non-boar NPCs are not caught.
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
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
  end
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

  -- Quilboar are humanoids, not boar beasts.
  if string.find(n, "quilboar", 1, true) then return true end

  -- Utility/pet/spirit entries should not be treated as grindable enemy boars.
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
  if pfDatabase and pfDatabase.IsFriendly then
    return pfDatabase:IsFriendly(id)
  end
  return false
end

local function countCoords(coords)
  local count = 0
  if coords then
    for _ in pairs(coords) do count = count + 1 end
  end
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

  -- Classify against English names so detection remains stable even if the client locale changes.
  -- pfQuest-turtle patches its custom English unit names into this same table when installed.
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
    if BoaringAdventureDB and BoaringAdventureDB.boarOnly and not BA:IsOurMeta(meta) then
      return
    end
    return original(frame, meta)
  end

  self.filterInstalled = true
end

function BA:RemoveBoarOnlyFilter()
  if not self.filterInstalled then return end
  if pfMap and self.originalAddNode then
    pfMap.AddNode = self.originalAddNode
  end
  self.filterInstalled = false
end

function BA:ClearOtherNodes()
  if not pfMap or not pfMap.nodes or not pfMap.DeleteNode then return end

  local remove = {}
  for addon in pairs(pfMap.nodes) do
    if addon ~= ADDON then
      table.insert(remove, addon)
    end
  end

  for _, addon in pairs(remove) do
    pfMap:DeleteNode(addon)
  end
end

function BA:ClearBoars()
  if pfMap and pfMap.DeleteNode then
    pfMap:DeleteNode(ADDON)
  end
  if pfMap and pfMap.UpdateNodes then
    pfMap:UpdateNodes()
  end
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

  if pfMap and pfMap.UpdateNodes then
    pfMap:UpdateNodes()
  end

  if jumpToBestMap and matches > 0 and pfDatabase.GetBestMap and pfMap.ShowMapID then
    local best = pfDatabase:GetBestMap(maps)
    if best then pfMap:ShowMapID(best) end
  end

  if query and query ~= "" then
    if matches == 0 then
      msg("No boars matched |cffffffff" .. query .. "|r.")
    else
      msg("Showing |cffffffff" .. matches .. "|r boar type(s), |cffffffff" .. spawnCount .. "|r recorded spawn point(s).")
    end
  end
end

function BA:PrintInfo(query)
  query = trim(query)
  if query == "" then
    msg("Usage: |cffffffff/boar info <name or NPC id>|r")
    return
  end

  local found = 0
  for _, entry in pairs(self.boars) do
    if self:Matches(entry, query) then
      found = found + 1
      msg("|cffffffff" .. entry.name .. "|r  |cffaaaaaa[NPC " .. entry.id .. "]|r  Level |cffffcc00" .. tostring(entry.lvl) .. "|r  Spawns |cffffffff" .. entry.spawns .. "|r")

      local zones = {}
      for _, coord in pairs(entry.coords) do
        local zid = coord[3]
        if zid then zones[zid] = (zones[zid] or 0) + 1 end
      end

      local zoneText = ""
      for zid, count in pairs(zones) do
        local zname = (pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zid]) or ("Zone " .. zid)
        zoneText = zoneText .. (zoneText ~= "" and ", " or "") .. zname .. " (" .. count .. ")"
      end
      if zoneText ~= "" then
        msg("  |cffaaaaaa" .. zoneText .. "|r")
      end

      if found >= 10 then
        msg("More matches exist; use a more specific name.")
        break
      end
    end
  end

  if found == 0 then
    msg("No boars matched |cffffffff" .. query .. "|r.")
  end
end

function BA:PrintList(query)
  query = trim(query)
  local total = 0
  local shown = 0

  for _, entry in pairs(self.boars) do
    if self:Matches(entry, query) then
      total = total + 1
      if shown < 30 then
        shown = shown + 1
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffd28b42%3d|r  |cffffffff%s|r  |cffaaaaaaLv %s, %d spawns|r", entry.id, entry.name, tostring(entry.lvl), entry.spawns))
      end
    end
  end

  msg("|cffffffff" .. total .. "|r matching boar type(s)." .. (total > shown and " Showing the first 30." or ""))
end

function BA:SetFilter(state)
  if state then
    BoaringAdventureDB.boarOnly = true
    self:InstallBoarOnlyFilter()
    self:ClearOtherNodes()
    self:ShowBoars(nil, false)
    msg("Boar-only map filtering |cff33ff33enabled|r.")
  else
    BoaringAdventureDB.boarOnly = false
    self:RemoveBoarOnlyFilter()
    msg("Boar-only map filtering |cffffcc00disabled|r. pfQuest may show its normal nodes again.")
    if pfQuest and pfQuest.UpdateQuestlog then
      pfQuest:UpdateQuestlog()
    end
  end
end

function BA:PrintHelp()
  msg("Commands:")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar all|r - show every enemy boar spawn")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar <name>|r - show only matching boars and open their best map")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar info <name>|r - print level, NPC id, zones and spawn count")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar list [text]|r - list known boar types")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar clean|r - remove Boaring Adventure pins")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar filter on|off|r - enable/disable strict boar-only pfQuest map filtering")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/boar status|r - show database/filter status")
end

function BA:HandleSlash(input)
  input = trim(input)
  if input == "" or input == "help" then
    self:PrintHelp()
    return
  end

  local command, rest
  local _, _, c, r = string.find(input, "^(%S+)%s*(.-)$")
  command = lower(c or input)
  rest = trim(r or "")

  if command == "all" then
    self:ShowBoars(nil, false)
    msg("Showing all |cffffffff" .. table.getn(self.boars) .. "|r known enemy boar types.")
  elseif command == "clean" or command == "clear" then
    self:ClearBoars()
    msg("Boar pins cleared.")
  elseif command == "list" then
    self:PrintList(rest)
  elseif command == "info" then
    self:PrintInfo(rest)
  elseif command == "filter" then
    if lower(rest) == "on" then
      self:SetFilter(true)
    elseif lower(rest) == "off" then
      self:SetFilter(false)
    else
      msg("Boar-only filter is " .. (BoaringAdventureDB.boarOnly and "|cff33ff33ON|r" or "|cffffcc00OFF|r") .. ". Use |cffffffff/boar filter on|off|r.")
    end
  elseif command == "status" then
    msg("Version |cffffffff" .. self.version .. "|r - " .. table.getn(self.boars) .. " enemy boar types indexed. Filter: " .. (BoaringAdventureDB.boarOnly and "|cff33ff33ON|r" or "|cffffcc00OFF|r"))
    if IsAddOnLoaded and IsAddOnLoaded("pfQuest-turtle") then
      msg("pfQuest-turtle detected: custom Octo/Turtle boars are included.")
    else
      msg("pfQuest-turtle not detected: using pfQuest's base boar data only.")
    end
  else
    -- Any other text is treated as a boar-name search.
    self:ShowBoars(input, true)
  end
end

function BA:Initialize()
  if self.ready then return end

  if not pfDB or not pfDatabase or not pfMap then
    msg("Could not initialise because pfQuest is not available.")
    return
  end

  BoaringAdventureDB = BoaringAdventureDB or {}
  if BoaringAdventureDB.boarOnly == nil then BoaringAdventureDB.boarOnly = true end
  if BoaringAdventureDB.autoShow == nil then BoaringAdventureDB.autoShow = true end

  local count = self:BuildIndex()
  self.ready = true

  if BoaringAdventureDB.boarOnly then
    self:InstallBoarOnlyFilter()
    self:ClearOtherNodes()
  end

  if BoaringAdventureDB.autoShow then
    self:ShowBoars(nil, false)
  end

  msg("Loaded |cffffffff" .. count .. "|r enemy boar types. Type |cffffffff/boar|r for commands.")
end

SLASH_BOARINGADVENTURE1 = "/boar"
SLASH_BOARINGADVENTURE2 = "/boaring"
SlashCmdList["BOARINGADVENTURE"] = function(input)
  BA:HandleSlash(input)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
  this:UnregisterAllEvents()
  BA:Initialize()
end)
