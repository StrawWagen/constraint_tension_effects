

local enabledVar = GetConVar( "tension_cl_enabled" )
local enabled = enabledVar:GetBool()
cvars.AddChangeCallback( "tension_cl_enabled", function( _, _, new )
    enabled = tobool( new )

end, "updatemetalgibs" )

local gibModels = {
    "models/props_debris/rebar001a_32.mdl",
    "models/props_debris/rebar001b_48.mdl",
    "models/props_debris/rebar001c_64.mdl",
    "models/props_debris/rebar001d_96.mdl",

    "models/props_debris/rebar002a_32.mdl",
    "models/props_debris/rebar002b_48.mdl",
    "models/props_debris/rebar002c_64.mdl",
    "models/props_debris/rebar002d_96.mdl",

    "models/props_debris/rebar003a_32.mdl",
    "models/props_debris/rebar003b_48.mdl",
    "models/props_debris/rebar003c_64.mdl",

    "models/props_debris/rebar004a_32.mdl",
    "models/props_debris/rebar004b_48.mdl",
    "models/props_debris/rebar004c_64.mdl",
    "models/props_debris/rebar004d_96.mdl",

    "models/props_debris/rebar_cluster001a.mdl",
    "models/props_debris/rebar_cluster001b.mdl",
    "models/props_debris/rebar_cluster002a.mdl",
    "models/props_debris/rebar_cluster002b.mdl",

    "models/props_debris/rebar_medthin01a.mdl",
    "models/props_debris/rebar_medthin02a.mdl",
    "models/props_debris/rebar_medthin02b.mdl",
    "models/props_debris/rebar_medthin02c.mdl",
    "models/props_debris/rebar_medthin03a.mdl",

    "models/props_debris/rebar_smallnorm01a.mdl",
    "models/props_debris/rebar_smallnorm01c.mdl",

    "models/props_debris/concrete_spawnchunk001a.mdl",
    "models/props_debris/concrete_spawnchunk001b.mdl",
    "models/props_debris/concrete_spawnchunk001c.mdl",
    "models/props_debris/concrete_spawnchunk001d.mdl",
    "models/props_debris/concrete_spawnchunk001e.mdl",
    "models/props_debris/concrete_spawnchunk001f.mdl",
    "models/props_debris/concrete_spawnchunk001g.mdl",
    "models/props_debris/concrete_spawnchunk001h.mdl",
    "models/props_debris/concrete_spawnchunk001i.mdl",
    "models/props_debris/concrete_spawnchunk001j.mdl",
    "models/props_debris/concrete_spawnchunk001k.mdl",

    "models/props_debris/concrete_column001a_chunk01.mdl",
    "models/props_debris/concrete_column001a_chunk02.mdl",
    "models/props_debris/concrete_column001a_chunk03.mdl",
    "models/props_debris/concrete_column001a_chunk04.mdl",
    "models/props_debris/concrete_column001a_chunk05.mdl",
    "models/props_debris/concrete_column001a_chunk06.mdl",
    "models/props_debris/concrete_column001a_chunk07.mdl",
    "models/props_debris/concrete_column001a_chunk08.mdl",
    "models/props_debris/concrete_column001a_chunk09.mdl",

}
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

    -- try and conserve fps a lil bit
    if fps <= 30 or math.random( 1, 100 ) < 15 then
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
