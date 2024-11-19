TENSION_TBL = TENSION_TBL or {}

local IsValid = IsValid
local CurTime = CurTime

function TENSION_TBL.tryInternalEcho( ent, echoStress )
    if not IsValid( ent ) then return end

    local myObj = ent:GetPhysicsObject()
    if not IsValid( myObj ) then return end

    local massThresh = myObj:GetMass() / 4

    local entsPos = ent:WorldSpaceCenter()
    local biggestDistSqr = 1000^2 -- anything less than this is not worth
    local middlemen = {}
    local furthest
    local furthestsObj
    local furthestsPos

    timer.Simple( 0, function()
        if not IsValid( ent ) then return end

        local nextEcho = ent.tension_NextInternalEcho or 0
        if nextEcho > CurTime() then return end -- someone beat us to it!

        ent.tension_NextInternalEcho = CurTime() + math.Rand( 0.1, 1 ) -- getAllConstrainedEntities is lagggy

        local getMaterialForEnt = TENSION_TBL.getMaterialForEnt
        local entsMat = getMaterialForEnt( ent )
        local constrainedEnts = constraint.GetAllConstrainedEntities( ent )

        for _, currEnt in pairs( constrainedEnts ) do
            if not IsValid( currEnt ) then continue end
            currEnt.tension_NextInternalEcho = CurTime() + math.Rand( 0.1, 1 )

            local currsPos = currEnt:WorldSpaceCenter()

            if not util.IsInWorld( currsPos ) then continue end -- cant hear that ent!
            if getMaterialForEnt( currEnt ) ~= entsMat then continue end -- dont play metal sounds on wood structures, etc

            local currDist = currsPos:DistToSqr( entsPos )
            if currDist < biggestDistSqr then continue end

            if math.random( 0, 100 ) < 75 then continue end

            local currsObj = currEnt:GetPhysicsObject()
            if currsObj:GetMass() < massThresh then continue end

            if furthestsObj and furthestsObj:GetStress() <= 100 and furthestsObj:IsMotionEnabled() then -- thing with no stress ( stress doesnt happen in the middle of simple builds )
                middlemen[#middlemen + 1] = furthest

            end

            furthest = currEnt
            furthestsObj = currsObj
            furthestsPos = currsPos
            biggestDistSqr = currDist

        end

        local finalDist = math.sqrt( biggestDistSqr )

        if IsValid( furthest ) then
            local middleman -- play sound on one in the middle too
            local middlemansPos
            local distToStart
            for _ = 1, 20 do
                if #middlemen < 1 then -- bad middleman
                    middleman = nil
                    middlemansPos = nil
                    distToStart = nil
                    break

                end
                middleman = table.remove( middlemen, 1 )
                if not IsValid( middleman ) then continue end

                middlemansPos = middleman:WorldSpaceCenter()
                if middlemansPos:Distance( furthestsPos ) < finalDist / 4 then continue end

                distToStart = middlemansPos:Distance( entsPos )
                if distToStart < finalDist / 4 then continue end

                break -- good middleman

            end
            if IsValid( middleman ) then
                local mmDelay = distToStart / 10000
                timer.Simple( mmDelay, function()
                    echoStress = echoStress or massThresh * 2
                    echoStress = echoStress + ( distToStart * 4 )
                    TENSION_TBL.playStressSound( middleman, nil, echoStress )

                end )
            end

            local delay = finalDist / 10000
            timer.Simple( delay, function()
                echoStress = echoStress or massThresh * 2
                echoStress = echoStress + ( finalDist * 4 )
                TENSION_TBL.playStressSound( furthest, nil, echoStress )

            end )
        end
    end )
end

