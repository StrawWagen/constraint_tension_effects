
TENSION_TBL = TENSION_TBL or {}

TENSION_TBL.significantConstraints = TENSION_TBL.significantConstraints or {}
local IsValid = IsValid

local function getConstraintSignificance( const )
    local keys = const:GetKeyValues()
    local strength = math.max( keys.forcelimit, keys.torquelimit )
    if strength == 0 then strength = math.huge end

    local ent1, ent2 = const:GetConstrainedEntities()
    local ent1sMass = 0
    local ent2sMass = 0
    local massInvolved = 0
    if IsValid( ent1 ) and IsValid( ent1:GetPhysicsObject() ) and not ent1:IsPlayerHolding() then -- physgun sets ent's mass to 50k...
        ent1sMass = ent1:GetPhysicsObject():GetMass()
        massInvolved = massInvolved + ent1sMass

    end

    if IsValid( ent2 ) and IsValid( ent2:GetPhysicsObject() ) and not ent2:IsPlayerHolding() then
        ent2sMass = ent2:GetPhysicsObject():GetMass()
        massInvolved = massInvolved + ent2sMass

    end

    local maxSignificance = math.min( ent1sMass * 2, ent2sMass * 2 )
    local significance = math.Clamp( massInvolved, 0, math.min( maxSignificance, strength ) )

    --print( significance, massInvolved, ent1, ent2 )
    return significance, ent1, ent2

end

local function HandleSNAP( const )
    local significance, ent1, ent2 = getConstraintSignificance( const )
    TENSION_TBL.significantConstraints[const] = nil

    timer.Simple( 0, function()
        if not ( IsValid( ent1 ) and IsValid( ent2 ) ) then return end -- was removed!
        TENSION_TBL.playSnapSound( ent1, ent2, significance )

    end )
end

local constraintClasses = {
    phys_constraint = true,
    phys_lengthconstraint = true,
    phys_ballsocket = true,
    phys_hinge = true,
    phys_pulleyconstraint = true,
    phys_slideconstraint = true,
    phys_spring = true

}

hook.Add( "OnEntityCreated", "tension_findconstraints", function( ent )
    if not constraintClasses[ ent:GetClass() ] then return end

    timer.Simple( 0, function()
        if not IsValid( ent ) then return end
        ent:CallOnRemove( "tension_makenoise", function( removed )
            HandleSNAP( removed )

        end )
        local significance, ent1, ent2 = getConstraintSignificance( ent )
        if significance <= 1000 then return end

        TENSION_TBL.significantConstraints[ent] = {
            nextSnd = 0,
            lastStress = 0,
            const = ent,
            significance = significance,
            ent1 = ent1,
            ent2 = ent2,
            obj1 = ent1:GetPhysicsObject(),
            obj2 = ent2:GetPhysicsObject(),

        }
    end )
end )

local nextThink = 0

hook.Add( "Think", "tension_stresssounds", function()
    local cur = CurTime()
    if nextThink > cur then return end
    nextThink = cur + 0.05
    for _, data in pairs( TENSION_TBL.significantConstraints ) do

        local obj1 = data.obj2
        local obj2 = data.obj1
        if not ( IsValid( obj1 ) and IsValid( obj2 ) ) then TENSION_TBL.significantConstraints[ data.const ] = nil continue end

        local currStress = obj1:GetStress() + obj2:GetStress()

        local stressDiff = math.abs( currStress - data.lastStress )
        data.lastStress = currStress

        local nextSnd = data.nextSnd
        if nextSnd > cur then continue end

        if stressDiff < 100 then continue end

        local add = stressDiff / 1000
        data.nextSnd = cur + add

        TENSION_TBL.playStressSound( data.ent1, data.ent2, stressDiff )

    end
end )

local function getAppropriateSoundDat( sounds, stress, mat )
    local pickedSoundDat
    local bestStress = 0
    for _, currDat in ipairs( sounds ) do
        local currStress = currDat.stress

        if currStress > stress then continue end

        if bestStress > currStress then continue end
        bestStress = currStress

        local soundsForMats = currDat.sounds
        pickedSoundDat = soundsForMats[mat] or soundsForMats["generic"]

    end
    return pickedSoundDat

end

local function playSoundDat( ent, dat )
    if not IsValid( ent ) then return end -- world
    local paths = dat.paths
    ent:EmitSound( paths[math.random( 1, #paths )], dat.lvl, math.random( dat.minpitch, dat.maxpitch ), 1, dat.chan )
    if dat.twicedoublepitch then
        ent:EmitSound( paths[math.random( 1, #paths )], dat.lvl, math.random( dat.minpitch, dat.maxpitch ) * 2, 1, dat.chan )

    end

    shake = dat.shake
    if shake then
        util.ScreenShake( ent:GetPos(), shake.amp, 20, shake.amp / 10, shake.rad, false )

    end
end

local function playAppropriateSound( ent1, ent2, sounds, stress, mat )
    local bestDat = getAppropriateSoundDat( sounds, stress, mat )
    if not bestDat then return end

    playSoundDat( ent1, bestDat )
    playSoundDat( ent2, bestDat )

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
                lvl = 68,
                minpitch = 90,
                maxpitch = 110,
                shake = { rad = 500, amp = 1 }
            },
        }
    },
    {
        stress = 500,
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
                shake = { rad = 1000, amp = 2 }
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
                shake = { rad = 1500, amp = 4 }
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
                shake = { rad = 2000, amp = 6 }
            },
        }
    },
    {
        stress = 10000,
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
                minpitch = 20,
                maxpitch = 50,
                shake = { rad = 5000, amp = 8 }
            },
        }
    },
}

function TENSION_TBL.playStressSound( ent1, ent2, stressDiff )
    playAppropriateSound( ent1, ent2, TENSION_TBL.stressSounds, stressDiff )


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
                chan = CHAN_BODY,
                lvl = 75,
                minpitch = 110,
                maxpitch = 150,
                shake = { rad = 500, amp = 1 }
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
                chan = CHAN_BODY,
                lvl = 78,
                minpitch = 95,
                maxpitch = 110,
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
                chan = CHAN_BODY,
                lvl = 84,
                minpitch = 90,
                maxpitch = 120,
                shake = { rad = 3000, amp = 10 }
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
                chan = CHAN_BODY,
                lvl = 88,
                minpitch = 80,
                maxpitch = 150,
                shake = { rad = 3000, amp = 10 }
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
                lvl = 90,
                minpitch = 80,
                maxpitch = 150,
                shake = { rad = 3000, amp = 10 }
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
                lvl = 100,
                minpitch = 40,
                maxpitch = 60,
                twicedoublepitch = true,
                shake = { rad = 4000, amp = 60 }
            },
        }
    },
}

function TENSION_TBL.playSnapSound( ent1, ent2, stress )
    playAppropriateSound( ent1, ent2, TENSION_TBL.snapSounds, stress )

end