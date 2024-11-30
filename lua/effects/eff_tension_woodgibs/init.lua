

local enabledVar = GetConVar( "tension_cl_enabled" )
local enabled = enabledVar:GetBool()
cvars.AddChangeCallback( "tension_cl_enabled", function( _, _, new )
    enabled = tobool( new )

end, "updatewoodgibs" )

local gibModels = {
    "models/gibs/wood_gib01a.mdl",
    "models/gibs/wood_gib01b.mdl",
    "models/gibs/wood_gib01c.mdl",
    "models/gibs/wood_gib01d.mdl",
    "models/gibs/wood_gib01e.mdl",

    "models/props_wasteland/wood_fence02a_board03a.mdl",
    "models/props_wasteland/wood_fence02a_board04a.mdl",
    "models/props_wasteland/wood_fence02a_board05a.mdl",
    "models/props_wasteland/wood_fence02a_board06a.mdl",
    "models/props_wasteland/wood_fence02a_board07a.mdl",
    "models/props_wasteland/wood_fence02a_board08a.mdl",
    "models/props_wasteland/wood_fence02a_board09a.mdl",

    "models/props_wasteland/wood_fence02a_shard01a.mdl",

    "models/props_wasteland/cafeteria_bench001a_chunk02.mdl",
    "models/props_wasteland/cafeteria_bench001a_chunk03.mdl",
    "models/props_wasteland/cafeteria_bench001a_chunk04.mdl",

    "models/props_wasteland/cafeteria_table001a_chunk01.mdl",
    "models/props_wasteland/cafeteria_table001a_chunk04.mdl",
    "models/props_wasteland/cafeteria_table001a_chunk05.mdl",
    "models/props_wasteland/cafeteria_table001a_chunk06.mdl",
    "models/props_wasteland/cafeteria_table001a_chunk07.mdl",
    "models/props_wasteland/cafeteria_table001a_chunk0.mdl",

    "models/props_junk/wood_crate001a_chunk05.mdl",
    "models/props_junk/wood_crate001a_chunk06.mdl",

    "models/props_junk/wood_pallet001a_chunka1.mdl",
    "models/props_junk/wood_pallet001a_shard01.mdl",
    "models/props_junk/wood_pallet001a_chunkb2.mdl",

    "models/props_debris/wood_chunk01a.mdl",
    "models/props_debris/wood_chunk01b.mdl",
    "models/props_debris/wood_chunk01c.mdl",
    "models/props_debris/wood_chunk01d.mdl",
    "models/props_debris/wood_chunk01e.mdl",
    "models/props_debris/wood_chunk01f.mdl",

    "models/props_debris/wood_chunk02a.mdl",
    "models/props_debris/wood_chunk02b.mdl",
    "models/props_debris/wood_chunk02c.mdl",
    "models/props_debris/wood_chunk02d.mdl",
    "models/props_debris/wood_chunk02e.mdl",
    "models/props_debris/wood_chunk02f.mdl",

    "models/props_debris/wood_chunk03a.mdl",
    "models/props_debris/wood_chunk03b.mdl",
    "models/props_debris/wood_chunk03c.mdl",
    "models/props_debris/wood_chunk03d.mdl",
    "models/props_debris/wood_chunk03e.mdl",
    "models/props_debris/wood_chunk03f.mdl",

    "models/props_debris/wood_chunk04a.mdl",
    "models/props_debris/wood_chunk04b.mdl",
    "models/props_debris/wood_chunk04c.mdl",
    "models/props_debris/wood_chunk04d.mdl",
    "models/props_debris/wood_chunk04e.mdl",
    "models/props_debris/wood_chunk04f.mdl",

    "models/props_debris/wood_chunk05a.mdl",
    "models/props_debris/wood_chunk05b.mdl",
    "models/props_debris/wood_chunk05c.mdl",
    "models/props_debris/wood_chunk05d.mdl",
    "models/props_debris/wood_chunk05e.mdl",
    "models/props_debris/wood_chunk05f.mdl",

    -- skipping 06-07
}

-- below is copied from metalgibs

local precachedGibMdls

local math = math
local Color = Color

function EFFECT:Init( data )
    if not enabled then return end

    if not precachedGibMdls then
        precachedGibMdls = true
        for _, mdl in ipairs( gibModels ) do
            util.PrecacheModel( mdl )

        end
    end

    self.Normal = data:GetNormal()
    self.Position = data:GetOrigin()
    self.Scale = data:GetScale() or 25
    self.GibCount = self.Scale
    local owner = data:GetEntity()

    if self.Scale <= 0 then return end

    local lifetime = math.Rand( 10, 20 )

    local fps = 1 / FrameTime()

    if fps <= 10 or fps <= math.random( 0, 15 ) then -- :skull:
        return

    elseif fps <= 15 then -- hell naw this guy is crashin
        lifetime = lifetime / 10
        self.GibCount = 1

    elseif fps <= 30 or math.random( 1, 100 ) < 15 then -- try and conserve fps a lil bit
        lifetime = lifetime / 4
        self.GibCount = self.Scale * 0.25

    elseif fps <= 60 or math.random( 1, 100 ) < 30 then
        lifetime = lifetime / 2
        self.GibCount = self.Scale * 0.75

    end

    for _ = 1, self.GibCount do
        local mdl = gibModels[math.random( 1, #gibModels )]
        local gib = ents.CreateClientProp( mdl )
        SafeRemoveEntityDelayed( gib, lifetime * 2 ) -- backup
        gib:SetPos( self.Position + VectorRand() * math.random( 5, 25 ) )
        gib:SetAngles( AngleRand() )
        gib:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
        gib:Spawn()
        local vel
        local angVel
        local speed
        local ownersObj = IsValid( owner ) and owner:GetPhysicsObject()
        if IsValid( ownersObj ) then
            vel = owner:GetPhysicsObject():GetVelocity()
            speed = vel:Length()

        else
            vel = VectorRand() * self.Scale * 500
            speed = vel:Length()

        end

        local added = ( speed / 8 )
        vel = vel + ( VectorRand() * added )
        angVel = VectorRand() * added * math.Rand( 1, 10 )

        local gibsObj = gib:GetPhysicsObject()
        if not IsValid( gibsObj ) then SafeRemoveEntity( gib ) continue end

        gibsObj:SetVelocity( vel )
        gibsObj:SetAngleVelocity( angVel )

        timer.Simple( lifetime, function()
            if not IsValid( gib ) then return end
            gib:SetRenderMode( RENDERMODE_TRANSCOLOR )
            local timerName = "tension_fadeouthack_" .. gib:GetCreationID()
            local alpha = 255

            timer.Create( timerName, 0, 0, function()
                if not IsValid( gib ) then timer.Remove( timerName ) return end
                local oldColor = gib:GetColor()
                alpha = math.Clamp( alpha + -1, 0, 255 )

                if alpha <= 0 then
                    SafeRemoveEntity( gib )
                    timer.Remove( timerName )

                else
                    local newColor = Color( oldColor.r, oldColor.g, oldColor.b, alpha )
                    gib:SetColor( newColor )

                end
            end )
        end )
    end
end

function EFFECT:Render()
end
