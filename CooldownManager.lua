-- CooldownManager.lua
-- Rotapop Cooldown Manager (CDM) for WoW 12.x
-- Replaces legacy C_Spell.GetSpellCooldown with C_CooldownViewer-based cooldown resolution.
-- All cooldown state retrieval is centralized here; no other file should call C_Spell.GetSpellCooldown directly.

local addon, ns = ...

local CDM = {}
ns.CooldownManager = CDM

-- Internal cache for spell-to-category mappings discovered from CDM queries.
CDM.categoryCache = {}

--- Retrieve cooldown info from the CDM, returning unpacked values.
--- @param spellID number
--- @return number startTime
--- @return number duration
--- @return boolean isEnabled
--- @return number modRate
function CDM.GetCooldownInfo( spellID )
    if not spellID or spellID <= 0 then
        return 0, 0, true, 1
    end

    -- Primary path: C_CooldownViewer (12.x CDM).
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo( spellID )
        if cdInfo then
            if cdInfo.activeCategory and cdInfo.activeCategory > 0 then
                CDM.categoryCache[ spellID ] = cdInfo.activeCategory
            end
            return cdInfo.startTime or 0,
                   cdInfo.duration or 0,
                   cdInfo.isEnabled ~= false,
                   cdInfo.modRate or 1
        end
    end

    -- Secondary path: C_Spell.GetSpellCooldown (pre-12.x structured object).
    if C_Spell and C_Spell.GetSpellCooldown then
        local spellCooldownInfo = C_Spell.GetSpellCooldown( spellID )
        if spellCooldownInfo then
            if spellCooldownInfo.activeCategory and spellCooldownInfo.activeCategory > 0 then
                CDM.categoryCache[ spellID ] = spellCooldownInfo.activeCategory
            end
            return spellCooldownInfo.startTime or 0,
                   spellCooldownInfo.duration or 0,
                   spellCooldownInfo.isEnabled ~= false,
                   spellCooldownInfo.modRate or 1
        end
    end

    return 0, 0, true, 1
end

--- Retrieve the raw cooldown info object from the CDM.
--- Used by spec modules that need direct field access (e.g. activeCategory, isOnGCD).
--- @param spellID number
--- @return table cooldownInfo  SpellCooldownInfo-compatible table
function CDM.GetSpellCooldownInfo( spellID )
    local empty = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
    if not spellID or spellID <= 0 then
        return empty
    end

    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo( spellID )
        if cdInfo then
            if cdInfo.activeCategory and cdInfo.activeCategory > 0 then
                CDM.categoryCache[ spellID ] = cdInfo.activeCategory
            end
            return cdInfo
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown( spellID )
        if info then
            if info.activeCategory and info.activeCategory > 0 then
                CDM.categoryCache[ spellID ] = info.activeCategory
            end
            return info
        end
    end

    return empty
end

--- Retrieve charge information through the CDM.
--- @param spellID number
--- @return number|nil currentCharges
--- @return number|nil maxCharges
--- @return number|nil cooldownStartTime
--- @return number|nil cooldownDuration
--- @return number|nil chargeModRate
function CDM.GetChargeInfo( spellID )
    if not spellID or spellID <= 0 then
        return nil
    end

    -- Primary: C_CooldownViewer charge query (12.x).
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerChargeInfo then
        local chargeInfo = C_CooldownViewer.GetCooldownViewerChargeInfo( spellID )
        if chargeInfo then
            return chargeInfo.currentCharges,
                   chargeInfo.maxCharges,
                   chargeInfo.cooldownStartTime,
                   chargeInfo.cooldownDuration,
                   chargeInfo.chargeModRate
        end
    end

    -- Secondary: C_Spell.GetSpellCharges (pre-12.x).
    if C_Spell and C_Spell.GetSpellCharges then
        local spellChargeInfo = C_Spell.GetSpellCharges( spellID )
        if spellChargeInfo then
            return spellChargeInfo.currentCharges,
                   spellChargeInfo.maxCharges,
                   spellChargeInfo.cooldownStartTime,
                   spellChargeInfo.cooldownDuration,
                   spellChargeInfo.chargeModRate
        end
    end

    return nil
end

--- Retrieve the GCD state from the CDM.
--- Uses spell 61304 (the global cooldown trigger).
--- @return number startTime
--- @return number duration
--- @return boolean isEnabled
--- @return number modRate
function CDM.GetGCDInfo()
    return CDM.GetCooldownInfo( 61304 )
end

--- Determine whether two spells share a cooldown category.
--- @param spellA number
--- @param spellB number
--- @return boolean
function CDM.SharesCooldownCategory( spellA, spellB )
    -- Refresh category cache for both spells if needed.
    if not CDM.categoryCache[ spellA ] then
        CDM.GetSpellCooldownInfo( spellA )
    end
    if not CDM.categoryCache[ spellB ] then
        CDM.GetSpellCooldownInfo( spellB )
    end

    local catA = CDM.categoryCache[ spellA ]
    local catB = CDM.categoryCache[ spellB ]
    if catA and catB and catA == catB then
        return true
    end

    -- Check linked spells through CDM (12.x).
    if C_CooldownViewer and C_CooldownViewer.GetLinkedSpellIDs then
        local linked = C_CooldownViewer.GetLinkedSpellIDs( spellA )
        if linked then
            for _, id in ipairs( linked ) do
                if id == spellB then return true end
            end
        end
    end

    return false
end

--- Retrieve the active cooldown category for a spell.
--- @param spellID number
--- @return number|nil category
function CDM.GetCooldownCategory( spellID )
    if CDM.categoryCache[ spellID ] then
        return CDM.categoryCache[ spellID ]
    end

    local info = CDM.GetSpellCooldownInfo( spellID )
    if info and info.activeCategory then
        CDM.categoryCache[ spellID ] = info.activeCategory
        return info.activeCategory
    end

    return nil
end

--- Resolve override spell IDs through the CDM (12.x).
--- @param spellID number
--- @return number resolvedID
function CDM.GetOverrideSpell( spellID )
    if C_CooldownViewer and C_CooldownViewer.GetOverrideSpellID then
        local overrideID = C_CooldownViewer.GetOverrideSpellID( spellID )
        if overrideID and overrideID > 0 then
            return overrideID
        end
    end
    return spellID
end

--- Determine whether a spell's reported cooldown is purely the GCD.
--- Uses the CDM isOnGCD field when available, falling back to duration comparison.
--- @param spellID number
--- @param startTime number  The spell's cooldown start time.
--- @param duration number   The spell's cooldown duration.
--- @return boolean isGCDOnly
function CDM.IsGCDOnly( spellID, startTime, duration )
    -- Use CDM isOnGCD flag when available.
    local info = CDM.GetSpellCooldownInfo( spellID )
    if info.isOnGCD ~= nil then
        if info.isOnGCD and duration <= ( info.duration or 0 ) then
            return true
        end
    end

    -- Structural comparison: If the spell's CD exactly matches the current GCD window, it is GCD-only.
    local gcdStart, gcdDuration = CDM.GetGCDInfo()
    if gcdStart == startTime and gcdDuration == duration and duration > 0 then
        return true
    end

    return false
end

--- Clear all cached data (e.g. on specialization change).
function CDM.ClearCache()
    wipe( CDM.categoryCache )
end
