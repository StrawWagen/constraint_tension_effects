local enabledVar = CreateClientConVar( "tension_cl_enabled", "1", true, true, "Enable/disable TENSION clientside?", 0, 1 )
local enabled = enabledVar:GetBool()
cvars.AddChangeCallback( "tension_cl_enabled", function( _, _, new )
    enabled = tobool( new )

end, "updatemain" )

local shakeEnabledVar = CreateClientConVar( "tension_cl_screenshake_enabled", "1", true, true, "Enable/disable tension screenshake clientside?", 0, 1 )
local shakeEnabled = shakeEnabledVar:GetBool()
cvars.AddChangeCallback( "tension_cl_screenshake_enabled", function( _, _, new )
    shakeEnabled = tobool( new )

end, "updatemain" )

local volumeMulVar = CreateClientConVar( "tension_cl_volumemul", "1", true, true, "Change the volume/scale of TENSION sounds/screenshake.", 0.01, 1 )
local volumeMul = volumeMulVar:GetFloat()
cvars.AddChangeCallback( "tension_cl_volumemul", function( _, _, new )
    volumeMul = new

end, "updatemain" )

local IsValid = IsValid
local LocalPlayer = LocalPlayer
local MOVETYPE_NOCLIP = MOVETYPE_NOCLIP

local goodDelayMagicNum = 60000

local function getTimeDelayToFeel( ref )
    local dist = ref:Distance( LocalPlayer():GetPos() )
    local timeDelay = dist / goodDelayMagicNum
    return timeDelay, dist

end

local block = 0
local tooSmol = 0.02

net.Receive( "tension_send_clientashake", function()
    if not shakeEnabled then return end

    local pos = net.ReadVector()
    local amp = net.ReadFloat()
    local freq = net.ReadFloat()
    local dur = net.ReadFloat()
    local radius = net.ReadInt( 32 )
    local airshake = net.ReadBool()
    if not airshake then
        local ply = LocalPlayer()
        if not IsValid( ply ) then return end -- not loaded
        local moveType = ply:GetMoveType()
        if moveType == MOVETYPE_NOCLIP and not ply:InVehicle() then -- no shake in air feels lame, do barely any shake instead
            amp = amp / 8

        end
    end

    amp = amp * volumeMul
    freq = freq * volumeMul

    if amp <= tooSmol then return end -- nonsense shake
    if freq <= tooSmol then return end

    local timeDelay, dist = getTimeDelayToFeel( pos )
    if dist > 8000 then
        amp = amp / 8
        freq = freq / 2

        if amp <= tooSmol then return end
        if freq <= tooSmol then return end

    end

    timer.Simple( timeDelay, function()
        local added = ( amp / 1500 ) -- stop screenshake from going too crazy please
        local currBlock = block + added
        if currBlock > CurTime() then return end

        block = math.max( block + added, CurTime() + added )
        util.ScreenShake( pos, amp, freq, dur, radius )

    end )
end )


local bitCount = 10

net.Receive( "tension_send_clientasound", function()
    if not enabled then return end

    local ent = net.ReadEntity()
    if not IsValid( ent ) then return end

    local path = net.ReadString()
    local level = net.ReadInt( bitCount )
    local pitch = net.ReadFloat()
    local vol = net.ReadFloat()
    local channel = net.ReadInt( bitCount )
    local flags = net.ReadInt( bitCount )
    local dsp = net.ReadInt( bitCount )

    vol = vol * volumeMul
    local delay, dist = getTimeDelayToFeel( ent:GetPos() )
    timer.Simple( delay, function()
        if not IsValid( ent ) then return end
        local newpitch = math.Clamp( pitch + -dist / 1000, 1, 200 ) -- far away stuff is lower pitch wow
        ent:EmitSound( path, level, newpitch, vol, channel, flags, dsp )

    end )
end )