
AddCSLuaFile( "autorun/client/cl_constraint_tension_effects.lua" )

TENSION_TBL = TENSION_TBL or {}

local enabledVar = CreateConVar( "tension_sv_enabled", 1, FCVAR_ARCHIVE, "Enable/disable tension." )
local enabled = enabledVar:GetBool()
cvars.AddChangeCallback( "tension_sv_enabled", function( _, _, new )
    enabled = tobool( new )

end )

local adminOnlyVar = CreateConVar( "tension_sv_adminsonly", 0, FCVAR_ARCHIVE, "Make tension only work on admin owned props, REQUIRES CPPI" )
local adminOnly = adminOnlyVar:GetBool()
cvars.AddChangeCallback( "tension_sv_adminsonly", function( _, _, new )
    adminOnly = tobool( new )

end )

local autoFreezeVar = CreateConVar( "tension_sv_autofreeze", 1, FCVAR_ARCHIVE, "Automatically freeze props that came from snapped constraints, when the server's laggin." )
local autoFreeze = autoFreezeVar:GetBool()
cvars.AddChangeCallback( "tension_sv_autofreeze", function( _, _, new )
    autoFreeze = tobool( new )

end )

local shakeEnabledVar = CreateConVar( "tension_sv_screenshake_enabled", 1, FCVAR_ARCHIVE, "Enable/disable tension screenshake." )
local shakeEnabled = shakeEnabledVar:GetBool()
cvars.AddChangeCallback( "tension_screenshake_enabled", function( _, _, new )
    shakeEnabled = tobool( new )

end )

TENSION_TBL.significantConstraints = TENSION_TBL.significantConstraints or {}
TENSION_TBL.nextGlobalEcho = 0
TENSION_TBL.nextFallWoosh = 0
TENSION_TBL.nextBigFallAmbiance = 0
TENSION_TBL.doBigFallAmbiance = 0

local IsValid = IsValid
local string_lower = string.lower
local string_find = string.find
local math_random = math.random
local math_Rand = math.Rand

local wasSomethingWorthFreezing

local overridingMats = {
    ["flesh"] = true

}
local noGenericMats = {
    ["flesh"] = true

}
local materialAliases = {
    ["antlion"] = "flesh",

}

local potentialMaterials = {
    "wood",
    "flesh",
    "antlion",
    --"concrete", -- not enough super heavy concrete sounds
}

local function getMaterialForEnt( ent )
    if not IsValid( ent ) then return end

    local cached = ent.tension_CachedSoundMaterial
    if cached then return cached end

    local theMat
    local stringToCheck = ent:GetMaterial()

    if stringToCheck ~= "" then
        local loweredStr = string_lower( stringToCheck )

        for _, currMat in ipairs( potentialMaterials ) do
            if string_find( loweredStr, currMat ) then
                --print( loweredStr, currMat, ent:GetModel() )
                theMat = currMat
                break

            end
        end
    end

    if not theMat then
        local entsObj = ent:GetPhysicsObject()
        if IsValid( entsObj ) then
            stringToCheck = entsObj:GetMaterial()

        end
        local loweredStr = string_lower( stringToCheck )

        for _, currMat in ipairs( potentialMaterials ) do
            if string_find( loweredStr, currMat ) then
                --print( loweredStr, currMat, ent:GetModel() )
                theMat = currMat
                break

            end
        end
    end

    if not theMat then
        theMat = "generic"

    end

    local alias = materialAliases[theMat]
    if alias then
        theMat = alias

    end

    ent.tension_CachedSoundMaterial = theMat

    timer.Simple( 5, function() -- props WILL get their material changed
        if not IsValid( ent ) then return end
        ent.tension_CachedSoundMaterial = nil

    end )
    return theMat

end

TENSION_TBL.getMaterialForEnt = getMaterialForEnt

local function getConstraintSignificance( const )
    local keys = const:GetKeyValues()
    local strength = math.max( keys.forcelimit, keys.torquelimit )
    local wasBreakable = true
    if strength == 0 then
        wasBreakable = false
        strength = math.huge

    end

    local ent1, ent2 = const:GetConstrainedEntities()
    local ent1sMass = 0
    local ent2sMass = 0
    local massInvolved = 0
    local oneIsHeld
    if IsValid( ent1 ) and IsValid( ent1:GetPhysicsObject() ) then
        if ent1:IsPlayerHolding() then -- physgun sets ent's mass to 50k...
            oneIsHeld = true

        else
            ent1sMass = ent1:GetPhysicsObject():GetMass()
            massInvolved = massInvolved + ent1sMass

        end
    end

    if IsValid( ent2 ) and IsValid( ent2:GetPhysicsObject() ) then
        if ent2:IsPlayerHolding() then
            oneIsHeld = true

        else
            ent2sMass = ent2:GetPhysicsObject():GetMass()
            massInvolved = massInvolved + ent2sMass

        end
    end

    if oneIsHeld then
        massInvolved = massInvolved * 2

    end

    local maxSignificance = math.min( ent1sMass * 2, ent2sMass * 2 )
    local significance = math.Clamp( massInvolved, 0, math.min( maxSignificance, strength ) )

    --print( significance, massInvolved, ent1, ent2 )
    return significance, ent1, ent2, wasBreakable

end

function TENSION_TBL.handleContraptionDiameter( constr, data ) -- overcomplicated way to find a simple distance that represents the size of a contraption
    local TENSION_TBL = TENSION_TBL
    local significantConstraints = TENSION_TBL.significantConstraints
    data = data or significantConstraints[constr]
    if data.nextSizeCheck > CurTime() then return end

    if not enabled then return end

    if not IsValid( data.ent1 ) then return end
    if not IsValid( data.ent2 ) then return end

    local pos1 = data.ent1:GetPos()
    local pos2 = data.ent2:GetPos()

    local toUpdate = {}
    local touchedEnts = {}

    local furthestDistSqr = 0
    local connectedEnts = constraint.GetAllConstrainedEntities( data.ent1 )
    for _, ent in pairs( connectedEnts ) do
        table.insert( touchedEnts, ent )
        local entsPos = ent:GetPos()
        local toPos1 = entsPos:DistToSqr( pos1 )
        if toPos1 > furthestDistSqr then
            pos2 = entsPos
            furthestDistSqr = toPos1

        else
            local toPos2 = entsPos:DistToSqr( pos2 )
            if toPos2 > furthestDistSqr then
                pos1 = entsPos
                furthestDistSqr = toPos2

            end
        end

        local setupConstraints = ent.tension_Constraints
        if setupConstraints then
            for _, currConstr in ipairs( setupConstraints ) do
                table.insert( toUpdate, currConstr )

            end
        end
    end

    local furthestDist = math.sqrt( furthestDistSqr )
    local nextCheck = 1 -- not at all stable

    local dataToUpdate = {}

    for _, currConstr in ipairs( toUpdate ) do
        local currData = significantConstraints[currConstr]
        if currData then
            table.insert( dataToUpdate, currData )
            local lastSize = currData.contraptionDiameter or 0
            local diff = furthestDist - lastSize
            local currNextCheck = 0

            if diff < -100 then -- structure BROKE, doesn't happen like ever, but maybe in the future
                currNextCheck = math.huge -- this is max size EVER, not current size, sorry

            elseif diff < 10 then -- stabilized
                currNextCheck = 60

            elseif diff < 100 then -- kinda stable
                currNextCheck = 10

            elseif diff < 500 then -- not stable
                currNextCheck = 5

            end
            if currNextCheck > nextCheck then
                nextCheck = currNextCheck

            end
        end
    end

    for _, touchedEnt in pairs( touchedEnts ) do
        touchedEnt.tension_contraptionDiameter = furthestDist -- for easy access

    end

    for _, currData in ipairs( dataToUpdate ) do
        currData.nextSizeCheck = CurTime() + nextCheck
        currData.contraptionDiameter = furthestDist

    end
end



local downFar = Vector( 0, 0, -64000 )
local down = Vector( 0, 0, -1 )
local scaleAlwaysFreeze = 50
local function reallyLagginHook( ent, lagScale ) -- freezes stuff thats landed
    if lagScale and math_random( lagScale, 100 ) < scaleAlwaysFreeze then return end -- only freeze sometimes if its not alot of lag

    local nextCheck = ent.tension_nextFreezeCheck or 0
    if nextCheck > CurTime() then return end -- dont spam these too much

    local entsObj = ent:GetPhysicsObject()
    if not IsValid( entsObj ) then return end
    if not entsObj:IsMotionEnabled() then hook.Remove( "tension_onreallylaggin", ent ) return end

    local size = ent:GetModelRadius()
    local addedSpeed = lagScale / 200
    local speedToFreeze = 5 + addedSpeed
    if size > 100 then
        speedToFreeze = 2 + addedSpeed

    elseif size > 1000 then -- they'll really notice if this one is freezing, better be worth it
        speedToFreeze = 1 + addedSpeed

    end
    if entsObj:GetVelocity():Length() > speedToFreeze then return end

    local nearestToGround = ent:NearestPoint( ent:WorldSpaceCenter() + downFar )
    local findGroundOffset = down * math.Clamp( size / 100, 5, 100 )

    local doFreeze

    local trStruc = {
        start = nearestToGround,
        endpos = nearestToGround + findGroundOffset,
        mask = MASK_SOLID,
        filter = function( hit )
            if hit:IsWorld() then return true end
            if not IsValid( hit ) then return end
            local hitsObj = hit:GetPhysicsObject()
            if IsValid( hitsObj ) and not hitsObj:IsMotionEnabled() then return true end

        end,
    }
    local result = util.TraceLine( trStruc )

    if not result.Hit then return end

    local hitEnt = result.Entity
    if IsValid( hitEnt ) then
        local hitsObj = hitEnt:GetPhysicsObject()
        if IsValid( hitsObj ) and not hitsObj:IsMotionEnabled() then
            doFreeze = true

        end
    elseif result.HitWorld then
        doFreeze = true

    end
    if doFreeze then
        wasSomethingWorthFreezing = true
        entsObj:EnableMotion( false )
        hook.Remove( "tension_onreallylaggin", ent )

    else
        ent.tension_nextFreezeCheck = CurTime() + math_Rand( 0.01, 0.1 )

    end
end


local function HandleSNAP( const )
    TENSION_TBL.significantConstraints[const] = nil

    if not enabled then return end

    local significance, ent1, ent2, wasBreakable = getConstraintSignificance( const )
    if significance > 15000 then
        if not ent1.tensionFallInfo then -- dont do this if any other SNAPs beat us to it
            local allConstrainedEnts = constraint.GetAllConstrainedEntities( ent1 )
            for _, ent in pairs( allConstrainedEnts ) do
                TENSION_TBL.bigFallEffects( ent, ent:GetPhysicsObject() )

            end
        end

        if not ent2.tensionFallInfo then -- ditto
            local allConstrainedEnts = constraint.GetAllConstrainedEntities( ent2 )
            for _, ent in pairs( allConstrainedEnts ) do
                TENSION_TBL.bigFallEffects( ent, ent:GetPhysicsObject() )

            end
        end
    end

    local obj1 = ent1 and ent1:GetPhysicsObject()
    local obj2 = ent2 and ent2:GetPhysicsObject()

    if not ( IsValid( obj1 ) and IsValid( obj2 ) ) then return end

    local obj1Mass = obj1:GetMass()
    local obj2Mass = obj2:GetMass()

    local leastMass
    local mostMass
    if obj1Mass > obj2Mass then
        leastMass = ent2
        mostMass = ent1
    else
        leastMass = ent1
        mostMass = ent2

    end

    local ent1sHealth = leastMass:GetMaxHealth()
    local ent2sHealth = mostMass:GetMaxHealth()

    local oneHadHealth = ent1sHealth > 1 or ent2sHealth > 1 -- all prop_physics has 1 health??
    local matFallback = getMaterialForEnt( leastMass )

    timer.Simple( 0, function()
        if not wasBreakable and IsValid( leastMass ) and IsValid( mostMass ) then -- constraint was REMOVED!
            return

        elseif oneHadHealth then
            local oneIsValid = IsValid( leastMass ) or IsValid( mostMass )
            if not oneIsValid then return end -- assume it was removed ( not like we can play sounds on NULL ents anyway )

        elseif not ( IsValid( leastMass ) and IsValid( mostMass ) ) then
            return

        elseif ( IsValid( obj1 ) and IsValid( obj2 ) ) and not obj1:IsMotionEnabled() and not obj2:IsMotionEnabled() then -- both are frozen, likely the constraint was undone
            return

        end

        TENSION_TBL.playSnapSound( leastMass, mostMass, significance, matFallback )
        TENSION_TBL.playSnapEffects( leastMass, mostMass, significance )

        if IsValid( ent1 ) then
            TENSION_TBL.tryInternalEcho( ent1 ) -- make the snap echo through the contraption
            hook.Add( "tension_onreallylaggin", ent1, function( self, lagScale ) return reallyLagginHook( self, lagScale ) end ) -- and freeze this prop if the session starts lagging

        end
        if IsValid( ent2 ) then
            TENSION_TBL.tryInternalEcho( ent2 )
            hook.Add( "tension_onreallylaggin", ent2, function( self, lagScale ) return reallyLagginHook( self, lagScale ) end )

        end
    end )
end

local function getAppropriateSoundDat( sounds, stress, mat )
    local pickedSoundDat
    local bestStress = -1
    local needsOneOfMat = noGenericMats[mat]

    for _, currDat in ipairs( sounds ) do
        local currStress = currDat.stress

        if currStress > stress then continue end -- this sound is too stressful, dont pick

        if bestStress > currStress then continue end -- this one is too weak, dont pick

        local soundsForMats = currDat.sounds
        local currSoundDat = soundsForMats[mat]

        if not currSoundDat then
            if needsOneOfMat then continue end -- this mat cant fall back to generic
            currSoundDat = soundsForMats["generic"]

        end

        bestStress = currStress
        pickedSoundDat = currSoundDat

    end
    return pickedSoundDat

end


util.AddNetworkString( "tension_send_clientashake" )

local function SendShake( pos, amp, freq, dur, radius, airshake, filter )
    if not filter then
        filter = RecipientFilter()
        if radius > 10000 then
            filter:AddAllPlayers() -- just.... add all players

        elseif radius > 1000 then
            local radiusSqr = radius^2
            for _, ply in player.Iterator() do
                if ply:GetPos():DistToSqr( pos ) < radiusSqr then
                    filter:AddPlayer( ply )

                end
            end
        else
            filter:AddPAS( pos ) -- use this if radius is small, shake should go thru walls on big radiuses

        end
    end
    net.Start( "tension_send_clientashake" )
        net.WriteVector( pos )
        net.WriteFloat( amp )
        net.WriteFloat( freq )
        net.WriteFloat( dur )
        net.WriteInt( radius, 32 )
        net.WriteBool( airshake or false )
    net.Send( filter )

end


local bitCount = 10

util.AddNetworkString( "tension_send_clientasound" )

local function SendSound( ent, path, level, pitch, vol, channel, flags, dsp, filter )
    if not filter then
        filter = RecipientFilter()
        if level > 125 then -- loud, rare sound, supposed to be mapwide, PAS will probably fail it.
            filter:AddAllPlayers()

        else
            filter:AddPAS( ent:GetPos() )

        end
    end
    net.Start( "tension_send_clientasound" )
        net.WriteEntity( ent )
        net.WriteString( path )
        net.WriteInt( level or 75, bitCount )
        net.WriteFloat( pitch or 100 )
        net.WriteFloat( vol or 1 )
        net.WriteInt( channel or CHAN_AUTO, bitCount )
        net.WriteInt( flags or SND_NOFLAGS, bitCount )
        net.WriteInt( dsp or 0, bitCount )
    net.Send( filter )

end


local function playSoundDat( ent, dat )
    if not IsValid( ent ) then return end -- world
    local filter
    if dat.global then
        filter = RecipientFilter()
        filter:AddPVS( ent:WorldSpaceCenter() )

    end
    local paths = dat.paths
    SendSound( ent, paths[math_random( 1, #paths )], dat.lvl, math_random( dat.minpitch, dat.maxpitch ), 1, dat.chan, 0, 0, filter )
    if dat.twicedoublepitch then
        local newLvl = dat.lvl * 0.95
        SendSound( ent, paths[math_random( 1, #paths )], newLvl, math_random( dat.minpitch, dat.maxpitch ) * 2, 1, dat.chan, 0, 0, filter )

    end

    shake = dat.shake
    if shake and shakeEnabled then
        local obj = ent:GetPhysicsObject()
        if IsValid( obj ) and not obj:IsMotionEnabled() then
            shake.amp = shake.amp / 10

        end
        SendShake( ent:GetPos(), shake.amp, 20, shake.amp / 5, shake.rad, false )

    end
end


local function sparkEffect( sparkPos, scale )
    local sparks = EffectData()
    sparks:SetOrigin( sparkPos )
    sparks:SetMagnitude( math.ceil( 2 * scale ) )
    sparks:SetScale( 1 )
    sparks:SetRadius( 6 * scale )
    sparks:SetNormal( VectorRand() )
    util.Effect( "Sparks", sparks )

end

local function snapGibsMetal( sparkPos, ent, scale )
    local gibEff = EffectData()
    gibEff:SetOrigin( sparkPos )
    gibEff:SetMagnitude( math.ceil( 2 * scale ) )
    gibEff:SetScale( math.ceil( 1 * scale ) )
    gibEff:SetEntity( ent )
    util.Effect( "eff_tension_metalgibs", gibEff )

end

local function snapGibsWood( sparkPos, ent, scale )
    local gibEff = EffectData()
    gibEff:SetOrigin( sparkPos )
    gibEff:SetMagnitude( math.ceil( 2 * scale ) )
    gibEff:SetScale( math.ceil( 1 * scale ) )
    gibEff:SetEntity( ent )
    util.Effect( "eff_tension_woodgibs", gibEff )

end

function TENSION_TBL.playSnapEffects( ent1, ent2, significance )
    local ent1Mat = getMaterialForEnt( ent1 )
    local ent2Mat = getMaterialForEnt( ent2 )
    if not ( ent1Mat and ent2Mat ) then return end

    if ent1Mat == "generic" and ent2Mat == "generic" then
        local sparkScale = significance / math_random( 30000, 100000 )
        if sparkScale > 0.1 then
            local ent1sCenter = ent1:WorldSpaceCenter()
            local ent2sCenter = ent2:WorldSpaceCenter()

            local ent1sNearest = ent1:NearestPoint( ent2sCenter )
            local ent2sNearest = ent2:NearestPoint( ent1sCenter )

            sparkEffect( ent1sNearest, sparkScale )
            sparkEffect( ent2sNearest, sparkScale )

            local gibScale = significance / 15000
            snapGibsMetal( ent1sNearest, ent1, gibScale )
            snapGibsMetal( ent2sNearest, ent2, gibScale )
        end
    elseif ent1Mat == "wood" and ent2Mat == "wood" then
        local splinterScale = significance / math_random( 500, 7500 )
        if splinterScale > 0.05 then
            local ent1sCenter = ent1:WorldSpaceCenter()
            local ent2sCenter = ent2:WorldSpaceCenter()

            local ent1sNearest = ent1:NearestPoint( ent2sCenter )
            local ent2sNearest = ent2:NearestPoint( ent1sCenter )

            local gibScale = significance / 500
            snapGibsWood( ent1sNearest, ent1, gibScale )
            snapGibsWood( ent2sNearest, ent2, gibScale )

        end
    end
end

local function playAppropriateSound( ent1, ent2, sounds, stress, matFallback )

    local ent1Mat = getMaterialForEnt( ent1 )
    local ent2Mat = getMaterialForEnt( ent2 )
    local mat = ent1Mat

    if overridingMats[ ent2Mat ] and not overridingMats[ ent1Mat ] then
        mat = ent2Mat

    end
    if not mat then
        mat = matFallback

    end

    local bestDat = getAppropriateSoundDat( sounds, stress, mat )
    if not bestDat then return end

    if IsValid( ent1 ) then
        playSoundDat( ent1, bestDat )

    end
    if IsValid( ent2 ) then
        playSoundDat( ent2, bestDat )

    end
    return bestDat

end


TENSION_TBL.stressSounds = {
    {
        stress = 100,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/metal_stress1.wav",
                    "ambient/materials/metal_stress2.wav",
                    "ambient/materials/metal_stress3.wav",
                    "ambient/materials/metal_stress4.wav",
                    "ambient/materials/metal_stress5.wav",
                    "ambient/materials/bump1.wav",

                },
                chan = CHAN_BODY,
                lvl = 64,
                minpitch = 100,
                maxpitch = 120,
            },
            wood = {
                paths = {
                    "ambient/materials/wood_creak1.wav",
                    "ambient/materials/wood_creak2.wav",
                    "ambient/materials/wood_creak3.wav",
                    "ambient/materials/wood_creak4.wav",
                    "ambient/materials/wood_creak5.wav",
                    "ambient/materials/wood_creak6.wav",

                },
                chan = CHAN_BODY,
                lvl = 70,
                minpitch = 80,
                maxpitch = 110,
                shake = { rad = 500, amp = 1 }
            },
            flesh = {
                paths = {
                    "physics/body/body_medium_impact_soft1.wav",
                    "physics/body/body_medium_impact_soft2.wav",
                    "physics/body/body_medium_impact_soft3.wav",
                    "physics/body/body_medium_impact_soft4.wav",
                    "physics/body/body_medium_impact_soft5.wav",
                    "physics/body/body_medium_impact_soft6.wav",
                    "physics/body/body_medium_impact_soft7.wav",

                },
                chan = CHAN_BODY,
                lvl = 82,
                minpitch = 80,
                maxpitch = 110,
                shake = { rad = 500, amp = 1 }
            },
        }
    },
    {
        stress = 600,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/cartrap_rope1.wav",
                    "ambient/materials/cartrap_rope2.wav",
                    "ambient/materials/cartrap_rope3.wav",
                    "ambient/materials/metal_stress1.wav",
                    "ambient/materials/metal_stress2.wav",
                    "ambient/materials/metal_stress3.wav",
                    "ambient/materials/metal_stress4.wav",
                    "ambient/materials/metal_stress5.wav",
                    "ambient/materials/metal_rattle2.wav",
                    "ambient/materials/rustypipes2.wav",

                },
                chan = CHAN_BODY,
                lvl = 72,
                minpitch = 80,
                maxpitch = 100,
                shake = { rad = 1000, amp = 1 }
            },
            wood = {
                paths = {
                    "ambient/materials/wood_creak1.wav",
                    "ambient/materials/wood_creak6.wav",
                    "ambient/materials/wood_creak4.wav",
                    "physics/wood/wood_strain2.wav",
                    "physics/wood/wood_strain3.wav",
                    "physics/wood/wood_strain4.wav",

                },
                chan = CHAN_BODY,
                lvl = 78,
                minpitch = 60,
                maxpitch = 80,
                shake = { rad = 1000, amp = 2 }
            },
            flesh = {
                paths = {
                    "physics/body/body_medium_break2.wav",
                    "physics/body/body_medium_break3.wav",
                    "physics/body/body_medium_break4.wav",

                },
                chan = CHAN_BODY,
                lvl = 88,
                minpitch = 70,
                maxpitch = 90,
                shake = { rad = 500, amp = 1 }
            },
        }
    },
    {
        stress = 1000,
        sounds = {
            generic = {
                paths = {
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "ambient/materials/rustypipes1.wav",
                    "ambient/materials/rustypipes3.wav",
                    "ambient/materials/cartrap_rope1.wav",
                    "ambient/materials/cartrap_rope2.wav",
                    "ambient/materials/cartrap_rope3.wav",
                    "ambient/materials/metal_stress1.wav",
                    "ambient/materials/metal_stress2.wav",
                    "ambient/materials/metal_stress3.wav",
                    "ambient/materials/metal_stress4.wav",
                    "ambient/materials/metal_stress5.wav",

                },
                chan = CHAN_BODY,
                lvl = 76,
                minpitch = 75,
                maxpitch = 95,
                shake = { rad = 1500, amp = 2 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_strain2.wav",
                    "physics/wood/wood_strain3.wav",
                    "physics/wood/wood_strain4.wav",

                },
                chan = CHAN_STATIC,
                lvl = 82,
                minpitch = 50,
                maxpitch = 70,
                shake = { rad = 1500, amp = 2 }
            },
        }
    },
    {
        stress = 5000,
        sounds = {
            generic = {
                paths = {
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "physics/metal/metal_solid_strain1.wav",
                    "ambient/materials/shipgroan3.wav",
                    "ambient/materials/shipgroan4.wav",

                },
                chan = CHAN_STATIC,
                lvl = 78,
                minpitch = 80,
                maxpitch = 110,
                shake = { rad = 2000, amp = 3 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_strain2.wav",
                    "physics/wood/wood_strain3.wav",
                    "physics/wood/wood_strain4.wav",

                },
                chan = CHAN_STATIC,
                lvl = 90,
                minpitch = 40,
                maxpitch = 60,
                twicedoublepitch = true,
                shake = { rad = 2000, amp = 3 }
            },
        }
    },
    {
        stress = 20000,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/metal_groan.wav",
                    "ambient/machines/wall_move3.wav",
                    "vehicles/crane/crane_creak1.wav",
                    "vehicles/crane/crane_creak2.wav",
                    "vehicles/crane/crane_creak3.wav",
                    "vehicles/crane/crane_creak4.wav",

                },
                chan = CHAN_STATIC,
                lvl = 88,
                minpitch = 30,
                maxpitch = 60,
                shake = { rad = 5000, amp = 7 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_strain2.wav",
                    "physics/wood/wood_strain3.wav",
                    "physics/wood/wood_strain4.wav",
                    "physics/wood/wood_plank_break2.wav",
                    "physics/wood/wood_plank_break3.wav",
                    "physics/wood/wood_plank_break4.wav",
                    "physics/wood/wood_plank_impact_hard5.wav",

                },
                chan = CHAN_STATIC,
                lvl = 92,
                minpitch = 20,
                maxpitch = 50,
                twicedoublepitch = true,
                shake = { rad = 5000, amp = 4 }
            },
        },
    },
}

function TENSION_TBL.playStressSound( ent1, ent2, stressDiff )
    playAppropriateSound( ent1, ent2, TENSION_TBL.stressSounds, stressDiff )

    local oldInternalEchoTolerance = ent1.tension_oldInternalEchoTolerance or 0
    local nextEcho = ent1.tension_NextInternalEcho or 0
    if stressDiff < oldInternalEchoTolerance and nextEcho < CurTime() then -- makes sure this only really happens when the thing either just spawned, or is collapsing
        ent1.tension_oldInternalEchoTolerance = math.max( oldInternalEchoTolerance + stressDiff / 4, stressDiff / 2 )
        TENSION_TBL.tryInternalEcho( ent1, stressDiff )

    end
end

TENSION_TBL.snapSounds = {
    {
        stress = 0,
        sounds = {
            generic = {
                paths = {
                    "physics/metal/metal_box_break1.wav",
                    "physics/metal/metal_box_break2.wav",
                    "ambient/materials/metal_stress1.wav",
                    "ambient/materials/metal_stress2.wav",
                    "ambient/materials/metal_stress3.wav",
                    "ambient/materials/metal_stress4.wav",
                    "ambient/materials/metal_stress5.wav",
                    "ambient/materials/bump1.wav",

                },
                chan = CHAN_STATIC,
                lvl = 64,
                minpitch = 110,
                maxpitch = 160,
                shake = { rad = 500, amp = 0.5 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_furniture_break1.wav",
                    "physics/wood/wood_panel_break1.wav",
                    "physics/wood/wood_box_break1.wav",
                    "physics/wood/wood_plank_break3.wav",
                    "physics/wood/wood_plank_break4.wav",

                },
                chan = CHAN_STATIC,
                lvl = 80,
                minpitch = 110,
                maxpitch = 150,
                shake = { rad = 500, amp = 1 }
            },
            flesh = {
                paths = {
                    "physics/flesh/flesh_squishy_impact_hard1.wav",
                    "physics/flesh/flesh_squishy_impact_hard2.wav",
                    "physics/flesh/flesh_squishy_impact_hard3.wav",
                    "physics/flesh/flesh_squishy_impact_hard4.wav",
                    "physics/body/body_medium_break2.wav",
                    "physics/body/body_medium_break3.wav",
                    "physics/body/body_medium_break4.wav",

                },
                chan = CHAN_STATIC,
                lvl = 90,
                minpitch = 40,
                maxpitch = 60,
                twicedoublepitch = true,
                shake = { rad = 1500, amp = 2 }
            },
        }
    },
    {
        stress = 1000,
        sounds = {
            generic = {
                paths = {
                    "physics/metal/metal_box_break1.wav",
                    "physics/metal/metal_box_break2.wav",
                    "ambient/materials/metal_stress1.wav",
                    "ambient/materials/metal_stress2.wav",
                    "ambient/materials/metal_stress3.wav",
                    "ambient/materials/metal_stress4.wav",
                    "ambient/materials/metal_stress5.wav",
                    "ambient/materials/bump1.wav",

                },
                chan = CHAN_STATIC,
                lvl = 78,
                minpitch = 95,
                maxpitch = 110,
                shake = { rad = 500, amp = 0.5 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_furniture_break2.wav",
                    "physics/wood/wood_box_break2.wav",
                    "physics/wood/wood_plank_break1.wav",
                    "physics/wood/wood_plank_break2.wav",
                    "physics/wood/wood_plank_break3.wav",
                    "physics/wood/wood_plank_break4.wav",

                    "physics/wood/wood_crate_break1.wav",
                    "physics/wood/wood_crate_break2.wav",

                },
                chan = CHAN_STATIC,
                lvl = 82,
                minpitch = 95,
                maxpitch = 110,
                shake = { rad = 500, amp = 1 }
            },
            flesh = {
                paths = {
                    "physics/body/body_medium_break2.wav",
                    "physics/body/body_medium_break3.wav",
                    "physics/body/body_medium_break4.wav",

                },
                chan = CHAN_BODY,
                lvl = 88,
                minpitch = 70,
                maxpitch = 90,
                shake = { rad = 500, amp = 1 }
            },
        }
    },
    {
        stress = 4000,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/metal_big_impact_scrape1.wav",
                    "ambient/materials/cartrap_explode_impact1.wav",
                    "ambient/materials/cartrap_explode_impact2.wav",
                    "ambient/materials/metal_groan.wav",
                    "ambient/materials/shipgroan2.wav",

                },
                chan = CHAN_STATIC,
                lvl = 84,
                minpitch = 90,
                maxpitch = 120,
                shake = { rad = 3000, amp = 5 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_crate_break3.wav",
                    "physics/wood/wood_crate_break4.wav",
                    "physics/wood/wood_crate_break5.wav",

                },
                chan = CHAN_STATIC,
                lvl = 88,
                minpitch = 90,
                maxpitch = 120,
                shake = { rad = 3000, amp = 5 }
            },
        }
    },
    {
        stress = 10000,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/metal_big_impact_scrape1.wav",
                    "ambient/materials/cartrap_explode_impact1.wav",
                    "ambient/materials/cartrap_explode_impact2.wav",
                    "ambient/materials/metal_groan.wav",
                    "ambient/materials/shipgroan2.wav",

                },
                chan = CHAN_STATIC,
                lvl = 88,
                minpitch = 80,
                maxpitch = 150,
                shake = { rad = 3000, amp = 5 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_crate_break3.wav",
                    "physics/wood/wood_crate_break4.wav",
                    "physics/wood/wood_crate_break5.wav",
                    "physics/wood/wood_plank_impact_hard2.wav",
                    "physics/wood/wood_plank_impact_hard3.wav",
                    "physics/wood/wood_plank_impact_hard4.wav",
                    "physics/wood/wood_plank_impact_hard5.wav",

                },
                chan = CHAN_STATIC,
                lvl = 94,
                minpitch = 10,
                maxpitch = 30,
                twicedoublepitch = true,
                shake = { rad = 3000, amp = 5 }
            },
        }
    },
    {
        stress = 16000,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/metal_big_impact_scrape1.wav",
                    "ambient/materials/cartrap_explode_impact1.wav",
                    "ambient/materials/cartrap_explode_impact2.wav",
                    "ambient/materials/metal_groan.wav",
                    "ambient/materials/shipgroan2.wav",

                },
                chan = CHAN_STATIC,
                global = true,
                lvl = 90,
                minpitch = 80,
                maxpitch = 150,
                shake = { rad = 3000, amp = 5 }
            },
        },
        wood = {
            generic = {
                paths = {
                    "physics/wood/wood_crate_break3.wav",
                    "physics/wood/wood_crate_break4.wav",
                    "physics/wood/wood_crate_break5.wav",
                    "physics/wood/wood_plank_impact_hard5.wav",

                },
                chan = CHAN_STATIC,
                global = true,
                lvl = 98,
                minpitch = 5,
                maxpitch = 20,
                twicedoublepitch = true,
                shake = { rad = 3000, amp = 7.5 }
            },
        }
    },
    {
        stress = 25000,
        sounds = {
            generic = {
                paths = {
                    "ambient/materials/shipgroan2.wav",
                    "ambient/materials/metal_groan.wav",
                    "physics/metal/metal_large_debris2.wav",
                    "ambient/materials/metal_big_impact_scrape1.wav",
                    "ambient/materials/cartrap_explode_impact1.wav",
                    "ambient/materials/cartrap_explode_impact2.wav",
                    "ambient/materials/metal_groan.wav",

                },
                chan = CHAN_STATIC,
                global = true,
                lvl = 105,
                minpitch = 40,
                maxpitch = 60,
                twicedoublepitch = true,
                shake = { rad = 4000, amp = 15 }
            },
            wood = {
                paths = {
                    "physics/wood/wood_plank_impact_hard5.wav",

                },
                chan = CHAN_STATIC,
                global = true,
                lvl = 105,
                minpitch = 5,
                maxpitch = 15,
                twicedoublepitch = true,
                shake = { rad = 4000, amp = 15 }
            },
        }
    },
}

function TENSION_TBL.playSnapSound( ent1, ent2, stress, matFallback )
    playAppropriateSound( ent1, ent2, TENSION_TBL.snapSounds, stress, matFallback )

end

local wooshShounds = {
    "physics/nearmiss/whoosh_large1.wav",
    "physics/nearmiss/whoosh_large4.wav",
    "physics/nearmiss/whoosh_huge1.wav",
    "physics/nearmiss/whoosh_huge2.wav",

}

local nearHitSounds = {
    "vehicles/airboat/pontoon_impact_hard1.wav",
    "vehicles/airboat/pontoon_impact_hard2.wav",
    "doors/door_metal_large_chamber_close1.wav",
    "physics/concrete/boulder_impact_hard1.wav",
    "physics/concrete/boulder_impact_hard2.wav",
    "physics/concrete/boulder_impact_hard3.wav"

}

local dustFindOffset = Vector( 0, 0, -16000 )
local vertOnly = Vector( 0.25, 0.25, 1 )

function TENSION_TBL.bigFallEffects( ent, obj )
    if ent.tensionFallInfo then return end

    if not IsValid( ent ) then return end
    if not IsValid( obj ) then return end

    ent.tensionFallInfo = {
        lastVelLengSqr = obj:GetVelocity():LengthSqr(),
        decreasesInARow = 0,
        increasesInARow = 0,
        bestSpeedAchieved = 0,
    }

    local timerId = "tension_dustwhenitlands_" .. ent:GetCreationID()
    timer.Create( timerId, 0.25, 0, function()
        if not IsValid( ent ) then timer.Remove( timerId ) return end
        if not IsValid( obj ) then ent.tensionFallInfo = nil timer.Remove( timerId ) return end

        local tensionFallInfo = ent.tensionFallInfo

        local itsVel = obj:GetVelocity()
        itsVel = itsVel * vertOnly -- only if its FALLING please, caused problems with destructible vehicles

        local currLengSqr = itsVel:LengthSqr()
        local oldLengSqr = tensionFallInfo.lastVelLengSqr

        if currLengSqr > tensionFallInfo.bestSpeedAchieved then
            tensionFallInfo.bestSpeedAchieved = currLengSqr

        end

        if oldLengSqr > currLengSqr then
            tensionFallInfo.decreasesInARow = tensionFallInfo.decreasesInARow + 1
            tensionFallInfo.increasesInARow = 0

        else
            tensionFallInfo.increasesInARow = tensionFallInfo.increasesInARow + 1
            tensionFallInfo.decreasesInARow = 0
            if tensionFallInfo.increasesInARow >= 4 then
                tensionFallInfo.tension_BounceSoundDone = nil

            end
        end
        if TENSION_TBL.nextFallWoosh < CurTime() and not tensionFallInfo.doneFallWoosh and currLengSqr > 550^2 and tensionFallInfo.increasesInARow > math_random( 15, 35 ) and obj:GetMass() > math_random( 5000, 15000 ) then
            TENSION_TBL.nextFallWoosh = CurTime() + 0.1
            tensionFallInfo.doneFallWoosh = true

            local speed = math.sqrt( currLengSqr )
            local scale = math.abs( speed - 550 )
            scale = scale / 100

            local pit = 120
            local lvl = 110
            lvl = lvl + scale
            lvl = math.min( lvl, 150 )

            pit = pit + -scale * 2
            pit = math.Clamp( pit, 10, 120 )

            local filter = RecipientFilter()
            filter:AddPVS( ent:WorldSpaceCenter() )

            local path = wooshShounds[ math_random( 1, #wooshShounds ) ]


            SendSound( ent, path, lvl, pit, 0.5, CHAN_STATIC, 0, 0, filter )

            TENSION_TBL.tryInternalEcho( ent, ( speed + obj:GetMass() ) * 20 )

        elseif tensionFallInfo.decreasesInARow >= 1 or currLengSqr < 25^2 then
            local mass = obj:GetMass()
            local volume = obj:GetVolume()

            local passVolume = volume and volume > math_random( 641002, 854670 ) -- mmm, magic numbers
            local bestSpeedSqr = tensionFallInfo.bestSpeedAchieved

            -- give punch to bouncing debris
            if bestSpeedSqr > 1000^2 and mass > 5000 and passVolume and not tensionFallInfo.tension_BounceSoundDone then
                tensionFallInfo.tension_BounceSoundDone = true
                local nearHitPath = nearHitSounds[math_random( 1, #nearHitSounds )]
                local speedComp = math.sqrt( bestSpeedSqr ) / 2000
                local pit = math_random( 60, 70 )
                pit = pit + -( mass / 2500 )
                pit = pit + -speedComp
                pit = math.Clamp( pit, math_random( 25, 35 ), 100 )
                SendSound( ent, nearHitPath, 88 + speedComp, pit, 1 )

            end

            if tensionFallInfo.decreasesInARow < 10 and currLengSqr > 25^2 then return end

            ent.tensionFallInfo = nil
            timer.Remove( timerId )

            if bestSpeedSqr < 500^2 then return end

            local myPos = ent:WorldSpaceCenter()

            local bestSpeed = math.sqrt( bestSpeedSqr )

            local speedForScale = bestSpeed - 500
            local scale = 5 -- base of 5
            scale = scale + ( speedForScale / 200 )

            local dust = EffectData()
                dust:SetOrigin( ent:NearestPoint( ent:GetPos() + dustFindOffset ) )
                dust:SetNormal( down + ( itsVel:GetNormalized() * 0.25 ) )
                dust:SetScale( scale )
            util.Effect( "eff_tension_dustpuff", dust )

            local passMass = mass > math_random( 1000, 5000 )
            if scale <= math_random( 2, 15 ) or not passVolume or not passMass then return end

            if TENSION_TBL.doBigFallAmbiance < CurTime() then -- dont do the ambiance with just 1 thing....
                TENSION_TBL.doBigFallAmbiance = CurTime() + 0.5

            elseif TENSION_TBL.nextBigFallAmbiance < CurTime() then
                TENSION_TBL.doBigFallAmbiance = CurTime() + 0.5
                TENSION_TBL.nextBigFallAmbiance = CurTime() + 0.18
                local pit = 50
                local lvl = 75
                lvl = lvl + scale
                lvl = math.min( lvl, 90 )

                pit = pit + -scale
                pit = math.Clamp( pit, 20, 50 )

                local filter = RecipientFilter()
                filter:AddPVS( myPos )

                SendSound( ent, "ambient/levels/labs/teleport_postblast_thunder1.wav", lvl, pit, 0.5, CHAN_STATIC, 0, 0, filter )

            end

            -- instant stop, fell fast, and we're really heavy, ECHO!
            if TENSION_TBL.nextGlobalEcho < CurTime() and tensionFallInfo.decreasesInARow <= 11 and bestSpeed > 500 and mass >= 5000 then
                TENSION_TBL.nextGlobalEcho = CurTime() + 0.35
                local echoFilter = RecipientFilter()
                local farEnoughPlys = {}
                local dist = 3500
                for _, ply in player.Iterator() do
                    if ply:GetPos():Distance( myPos ) > dist then
                        table.insert( farEnoughPlys, ply )

                    end
                end
                echoFilter:AddPlayers( farEnoughPlys )

                local speedScale = bestSpeed / 1500 -- 1500 is max scale
                speedScale = math.Clamp( speedScale, 0, 1 )

                if shakeEnabled then
                    SendShake( ent:GetPos(), speedScale, 10 * speedScale, 12, 15000, true, echoFilter )

                end
                SendSound( ent, "ambient/explosions/explode_9.wav", 150, math_random( 15, 30 ), speedScale, CHAN_STATIC, 0, 131, echoFilter ) -- boooooom

            end
        end
    end )
end




local constraintClasses = {
    phys_constraint = true,
    phys_lengthconstraint = true,
    phys_ballsocket = true,
    phys_hinge = true,
    phys_pulleyconstraint = true,
    phys_slideconstraint = true,

}

local ropeTypes = {
    phys_lengthconstraint = true,
    phys_pulleyconstraint = true,
    phys_slideconstraint = true,

}

hook.Add( "OnEntityCreated", "tension_findconstraints", function( constr )
    if not constraintClasses[ constr:GetClass() ] then return end

    timer.Simple( 0, function()
        if not IsValid( constr ) then return end
        local significance, ent1, ent2 = getConstraintSignificance( constr )

        if not ( ent1 and ent2 ) then return end

        if adminOnly and CPPI and IsValid( ent1 ) then
            local owner = ent1:CPPIGetOwner()
            if not IsValid( owner ) and IsValid( ent2 ) then
                owner = ent2:CPPIGetOwner()

            end
            if IsValid( owner ) and not owner:IsAdmin() then return end -- works on world props too

        end

        if ent1 == ent2 then return end -- ragdoll welded to itself?
        if ent1:IsNPC() or ent2:IsNPC() then return end -- vj base....

        -- all good, now we setup the ent

        constr:CallOnRemove( "tension_makenoise", function( removed )
            HandleSNAP( removed )

        end )

        if significance <= math_random( 250, 1500 ) then return end -- not significant, this is random so that tension sounds arent overplayed

        local data = {
            nextSnd = 0,
            nextThink = 0,
            lastStress = 0,
            nextValidityCheck = 0,
            const = constr,
            significance = significance,
            rope = ropeTypes[constr],
            contraptionDiameter = nil,
            nextSizeCheck = 0,
            ent1 = ent1,
            ent2 = ent2,
            obj1 = ent1:GetPhysicsObject(),
            obj2 = ent2:GetPhysicsObject(),

        }
        TENSION_TBL.significantConstraints[constr] = data

        if not ent1.tension_Constraints then
            ent1.tension_Constraints = { constr }

        else
            table.insert( ent1.tension_Constraints, constr )

        end
        if not ent2.tension_Constraints then
            ent2.tension_Constraints = { constr }

        else
            table.insert( ent2.tension_Constraints, constr )

        end

        timer.Simple( math.random( 1, 8 ), function()
            if not IsValid( constr ) then return end
            TENSION_TBL.handleContraptionDiameter( constr, data ) -- another way we dont play big sounds on small stuff

        end )
    end )
end )

local nextThink = 0
local nextWhine = 0

hook.Add( "Think", "tension_mainthinker", function()
    local cur = CurTime()
    if nextThink > cur then return end
    nextThink = cur + 0.05
    if not enabled then
        nextThink = cur + 1
        return

    end

    if autoFreeze then
        local lagScale = physenv.GetLastSimulationTime() * 1000
        if lagScale > 5 then
            hook.Run( "tension_onreallylaggin", lagScale )

        end
        if wasSomethingWorthFreezing and lagScale > 25 and nextWhine < cur then
            nextWhine = cur + 5
            print( "TENSION; Freezing some select props to prevent session lock-up." )

        end
    end

    for _, data in pairs( TENSION_TBL.significantConstraints ) do

        if data.nextThink > cur then continue end

        local obj1 = data.obj2
        local obj2 = data.obj1
        if not ( IsValid( obj1 ) and IsValid( obj2 ) ) then
            TENSION_TBL.significantConstraints[ data.const ] = nil
            continue

        end

        if not obj1:IsMotionEnabled() and not obj2:IsMotionEnabled() then
            data.nextThink = cur + math_Rand( 0.5, 1.5 )
            continue

        end

        if data.nextValidityCheck < cur then
            data.nextValidityCheck = math_random( 10, 45 )
            if IsValid( data.ent1:GetParent() ) or IsValid( data.ent2:GetParent() ) then -- multi-parented without remove constraints checked...
                TENSION_TBL.significantConstraints[ data.const ] = nil
                continue

            end
        end

        local stressOf1 = obj1:GetStress()
        local stressOf2 = obj2:GetStress()
        local currStress = stressOf1 + stressOf2

        --debugoverlay.Text( data.ent1:WorldSpaceCenter(), tostring( currStress ), 0.1, false )

        local stressDiff = math.abs( currStress - data.lastStress )
        data.lastStress = currStress

        local nextSnd = data.nextSnd
        if nextSnd > cur then continue end

        if stressDiff > math_random( 25, 250 ) then -- random so we dont overplay tension sounds

            local obj1Mass = obj1:GetMass()
            local obj2Mass = obj2:GetMass()

            local clamp = obj1Mass + obj2Mass
            stressDiff = math.Clamp( stressDiff, 0, clamp ) -- so tiny stuff doesnt make bridge tension noises!

            local nextSndAdd = stressDiff / 750
            if stressDiff < 1000 then
                nextSndAdd = nextSndAdd + 1

            end
            data.nextSnd = cur + nextSndAdd

            -- do this after the sound interval setting
            local contraptionSize = data.contraptionDiameter or math.huge -- another tiny stuff check!
            stressDiff = math.Clamp( stressDiff, 0, contraptionSize * math.Rand( 4, 6 ) ) -- makes it so small contraptions dont play mega sounds

            local mostMass
            local leastMass
            if obj1Mass > obj2Mass then
                mostMass = data.ent1
                leastMass = data.ent2
            else
                mostMass = data.ent2
                leastMass = data.ent1

            end

            TENSION_TBL.playStressSound( leastMass, mostMass, stressDiff ) -- play using least stressed so material picker doesnt pick generic sounds on wood structures

        else
            if currStress < 10 then
                data.nextThink = cur + math_Rand( 0.5, 1.5 )

            else
                data.nextThink = cur + math_Rand( 0.1, 0.25 )

            end
        end
    end
end )