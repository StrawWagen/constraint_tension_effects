
local math = math

local enabledVar = GetConVar( "tension_cl_enabled" )
local enabled = enabledVar:GetBool()
cvars.AddChangeCallback( "tension_cl_enabled", function( _, _, new )
    enabled = tobool( new )

end, "updatedustpuff" )

local grav = Vector( 0, 0, -1 )
function EFFECT:Init( data )
    if not enabled then return end

    local vOffset = data:GetOrigin()
    self.Normal = data:GetNormal()
    self.Position = vOffset
    self.Scale = data:GetScale() or 25
    self.ParticleCount = self.Scale

    if self.Scale <= 0 then return end

    local emitter = ParticleEmitter( data:GetOrigin() )
    local lifetime = 40

    local fps = 1 / FrameTime()
    local particleScale = 1
    local cheap

    if fps <= 10 then -- this player is suffering.... no dust
        return

    elseif fps <= 30 or math.random( 1, 100 ) < 15 then -- try and conserve fps a lil bit
        cheap = true
        self.ParticleCount = self.Scale * 0.25
        particleScale = particleScale * 1.75
        lifetime = lifetime / 6

    elseif fps <= 60 or math.random( 1, 100 ) < 30 then
        self.ParticleCount = self.Scale * 0.75
        particleScale = particleScale * 1.25
        lifetime = lifetime / 4

    end

    for _ = 1, self.ParticleCount do
        local rollparticle = emitter:Add( "particle/particle_smokegrenade1", vOffset )
        rollparticle:SetPos( vOffset )
        rollparticle:SetDieTime( lifetime * math.Rand( 0.5, 1 ) )
        rollparticle:SetColor( 250, 255, 220 )
        rollparticle:SetStartAlpha( 100 )
        rollparticle:SetEndAlpha( 0 )
        rollparticle:SetStartSize( math.Rand( 5, 15 ) * particleScale )
        rollparticle:SetEndSize( math.Rand( 450, 550 ) * particleScale )
        rollparticle:SetRoll( math.Rand( -360, 360 ) )
        rollparticle:SetRollDelta( math.Rand( -0.1, 0.1 ) )
        rollparticle:SetAirResistance( 5 )
        rollparticle:SetCollide( true )

        if not cheap then
            local vel = self.Normal + ( VectorRand() * 0.25 )
            vel = vel * math.random( 100, 600 )
            if math.random( 1, 100 ) > 85 then
                vel = vel * 4

            end
            vel.z = math.Clamp( vel.z, 10, math.huge )
            rollparticle:SetVelocity( vel )
            rollparticle:SetGravity( grav )

        end
    end

    emitter:Finish()

end

function EFFECT:Render()
end
