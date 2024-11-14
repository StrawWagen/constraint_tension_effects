TENSION_TBL = TENSION_TBL or {}

local IsValid = IsValid
local CurTime = CurTime

function TENSION_TBL.tryInternalEcho( ent, echoStress )
    if not IsValid( ent ) then return end

    local myObj = ent:GetPhysicsObject()
    if not IsValid( myObj ) then return end

    local massThresh = myObj:GetMass() / 4

    local entsPos = ent:WorldSpaceCenter()
    local biggestDistSqr = 1500^2 -- anything less than this is not worth
    local furthest

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

            furthest = currEnt
            biggestDistSqr = currDist

        end

        local finalDist = math.sqrt( biggestDistSqr )

        if IsValid( furthest ) then
            local delay = finalDist / 10000
            timer.Simple( delay, function()
                echoStress = echoStress or massThresh * 2
                echoStress = echoStress + ( finalDist * 2 )
                TENSION_TBL.playStressSound( furthest, nil, echoStress )

            end )
        end
    end )
end

