-- LockCheck
-- Copyright (c) 2025 Derfla 
-- All rights reserved.
--
-- This addon may be used free of charge.
-- Redistribution, rehosting, bundling, or modification for redistribution
-- is not permitted without explicit permission from the author.
-- LockCheck.lua
-- Purpose:
--   - Out of combat, while grouped: show a small frame indicating
--       * whether a Warlock is in your party/raid
--       * whether you have an incoming summon (and who it's from, when available)
--     plus a manual button to either request a summon or say thanks.
--   - In combat: behave exactly like "not in group" => fully hidden.
--
-- Notes / best practices:
--   - No automatic whispers: only on button click.
--   - No protected actions: no casting, targeting, or auto-accepting summons.
--   - Defensive API checks for different WoW clients/versions.

local ADDON_NAME = ...

-- ------------------------------------------------------------
-- Utilities
-- ------------------------------------------------------------
local function IsPlayerInCombat()
  -- UnitAffectingCombat covers player combat state; InCombatLockdown covers restricted state.
  return UnitAffectingCombat("player") or InCombatLockdown()
end

local function HasIncomingSummon()
  return C_IncomingSummon
     and C_IncomingSummon.HasIncomingSummon
     and C_IncomingSummon.HasIncomingSummon("player")
     or false
end

local function GetSummonSummoner()
  -- Returns name-realm when available on modern clients; may be nil/empty.
  if C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner then
    local summoner = C_SummonInfo.GetSummonConfirmSummoner()
    if summoner and summoner ~= "" then
      return summoner
    end
  end
  return nil
end

local function UnitNameWithRealm(unit)
  local name, realm = UnitName(unit)
  if not name then return nil end
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

-- Finds the first Warlock (returns name[-realm]) or nil.
local function FindFirstWarlockName()
  if not IsInGroup() then return nil end

  local function isWarlock(unit)
    if not UnitExists(unit) then return false end
    local classFile = select(2, UnitClass(unit))
    return classFile == "WARLOCK"
  end

  if IsInRaid() then
    local n = GetNumGroupMembers()
    for i = 1, n do
      local unit = "raid" .. i
      if isWarlock(unit) then
        return UnitNameWithRealm(unit)
      end
    end
    return nil
  end

  -- Party (includes player + party1-4)
  if isWarlock("player") then
    return UnitNameWithRealm("player")
  end
  for i = 1, 4 do
    local unit = "party" .. i
    if isWarlock(unit) then
      return UnitNameWithRealm(unit)
    end
  end
  return nil
end

local function GroupHasWarlock()
  return FindFirstWarlockName() ~= nil
end

-- ------------------------------------------------------------
-- UI
-- ------------------------------------------------------------
local frame = CreateFrame("Frame", "LockCheckIndicator", UIParent, "BackdropTemplate")
frame:SetSize(230, 54)
frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

frame:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
frame:SetBackdropColor(0, 0, 0, 0.70)

local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOP", frame, "TOP", 0, -8)

local summonText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summonText:SetPoint("TOP", statusText, "BOTTOM", 0, -2)

local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn:SetSize(200, 18)
btn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 6)
btn:SetText("Request summon")

-- ------------------------------------------------------------
-- Button (manual only)
-- ------------------------------------------------------------
btn:SetScript("OnClick", function()
  if not IsInGroup() then
    print("|cffff8800LockCheck:|r You are not in a party/raid.")
    return
  end

  local incoming = HasIncomingSummon()
  
  if incoming then
    local summoner = GetSummonSummoner()
    if summoner then
      C_ChatInfo.SendChatMessage("ty!", "WHISPER", nil, summoner)
      print("|cff00ff00LockCheck:|r Thanked " .. summoner .. " for the summon.")
    else
      -- Incoming summon exists but summoner is unknown on this client/version.
      print("|cffff8800LockCheck:|r Summon pending, but couldn't determine who started it.")
    end
    return
  end

  local lock = FindFirstWarlockName()
  if lock then
    C_ChatInfo.SendChatMessage("summon me when you can pls", "WHISPER", nil, lock)
    print("|cff00ff00LockCheck:|r Requested summon from " .. lock .. ".")
  else
    print("|cffff0000LockCheck:|r No Warlock found in group.")
  end
end)

-- ------------------------------------------------------------
-- State + Updates
-- ------------------------------------------------------------
local lastHasLock, lastIncoming, lastSummoner = nil, nil, nil

local function ApplyVisibility()
  -- Requirement: In-combat behavior matches not-in-group behavior => fully hidden.
  if IsPlayerInCombat() or not IsInGroup() then
    frame:Hide()
    return false
  end

  frame:Show()
  frame:SetAlpha(1.0)
  btn:Show()
  return true
end

local function UpdateTexts(force)
  -- If we are hidden due to visibility rules, avoid churn; we'll refresh on next show.
  if not frame:IsShown() and not force then return end

  local hasLock = GroupHasWarlock()
  local incoming = HasIncomingSummon()
  local summoner = incoming and GetSummonSummoner() or nil

  if force or hasLock ~= lastHasLock then
    lastHasLock = hasLock
    if hasLock then
      statusText:SetText("LOCK: YES")
      frame:SetBackdropBorderColor(0.2, 1.0, 0.2, 1)
    else
      statusText:SetText("LOCK: NO")
      frame:SetBackdropBorderColor(1.0, 0.2, 0.2, 1)
    end
  end

  if force or incoming ~= lastIncoming or summoner ~= lastSummoner then
    lastIncoming = incoming
    lastSummoner = summoner

    if incoming then
      if summoner then
        summonText:SetText("SUMMON: INCOMING (" .. summoner .. ")")
      else
        summonText:SetText("SUMMON: INCOMING")
      end
      btn:SetText("Say thanks")
      btn:Show()
    else
      summonText:SetText("SUMMON: NONE")

      -- Only show the button if it can actually do something: a Warlock exists.
      if hasLock then
        btn:SetText("Request summon")
        btn:Show()
      else
        btn:Hide()
      end
    end
  end
end

local function FullUpdate(forceTexts)
  local visible = ApplyVisibility()
  if visible then
    UpdateTexts(forceTexts)
  end
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("GROUP_ROSTER_UPDATE")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Summon prompt state changes (modern clients). Safe to register even if never fires.
evt:RegisterEvent("CONFIRM_SUMMON")
evt:RegisterEvent("CANCEL_SUMMON")

-- Combat transitions
evt:RegisterEvent("PLAYER_REGEN_DISABLED")
evt:RegisterEvent("PLAYER_REGEN_ENABLED")

evt:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    FullUpdate(true)
    return
  end

  -- Any of these can affect visibility or display state.
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    FullUpdate(true)
    return
  end

  if event == "CONFIRM_SUMMON" or event == "CANCEL_SUMMON" then
    FullUpdate(true)
    return
  end

  -- GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD
  FullUpdate(false)
end)

-- ------------------------------------------------------------
-- Slash commands
-- ------------------------------------------------------------
SLASH_LOCKCHECK1 = "/lockcheck"
SlashCmdList.LOCKCHECK = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "reset" then
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    print("|cff00ff00LockCheck:|r position reset.")
    FullUpdate(true)
    return
  end

  print("|cff00ff00LockCheck:|r Commands:")
  print("  /lockcheck reset")
end
