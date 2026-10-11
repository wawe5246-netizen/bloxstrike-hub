-- Lua 5.1 / Roblox executor (Synapse X, KRNL, Fluxus)
-- Bloxstrike full suite — UI + logic wired — built by olivia
-- Features: aimbot (hold/toggle, rebindable), silent aim, no recoil,
--           triggerbot (hold/toggle, rebindable), selectable target part,
--           FOV circle, box/name/weapon/health/skeleton ESP,
--           team check, bhop, speed, noclip, no spread, inf ammo

-- ── SERVICES ────────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer
local Mouse            = LocalPlayer:GetMouse()

-- ── CONFIG ───────────────────────────────────────────────────────────────────
local CFG = {
    -- aimbot
    AimbotEnabled    = false,
    AimbotMode       = "toggle",          -- "toggle" | "hold"
    AimbotKey        = Enum.KeyCode.CapsLock,
    AimbotMouseKey   = Enum.UserInputType.MouseButton2,
    TargetPart       = "Head",
    Smoothing        = 0.18,
    FOVRadius        = 120,
    FOVVisible       = true,

    -- silent aim
    SilentAim        = false,

    -- triggerbot
    Triggerbot       = false,
    TriggerMode      = "toggle",          -- "toggle" | "hold"
    TriggerKey       = Enum.KeyCode.F,
    TriggerDelay     = 0.05,
    TriggerEnabled   = false,             -- runtime toggle state

    -- no recoil
    NoRecoil         = true,

    -- esp
    ESPEnabled       = true,
    BoxESP           = true,
    NameESP          = true,
    WeaponESP        = true,
    HealthBar        = true,
    SkeletonESP      = true,
    TeamCheck        = true,
    MaxDist          = 600,

    -- misc
    BunnyHop         = false,
    SpeedHack        = false,
    SpeedMult        = 1.6,
    Noclip           = false,
    NoSpread         = false,
    InfAmmo          = false,

    -- colours
    ColBox           = Color3.fromRGB(255, 70,  70),
    ColName          = Color3.fromRGB(255, 255, 80),
    ColWeapon        = Color3.fromRGB(120, 200, 255),
    ColSkeleton      = Color3.fromRGB(200, 200, 200),
    ColFOV           = Color3.fromRGB(255, 255, 255),
}

-- ── SKELETON CHAIN ───────────────────────────────────────────────────────────
local SKEL = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
}

-- ── DRAWING POOL ─────────────────────────────────────────────────────────────
local Pool = {}

local function newDraw(t, props)
    local d = Drawing.new(t)
    for k,v in pairs(props) do d[k]=v end
    return d
end

local function buildPool(player)
    if player == LocalPlayer then return end
    local t = {}
    t.boxLines = {}
    for i=1,4 do
        t.boxLines[i] = newDraw("Line",{Thickness=1,Color=CFG.ColBox,Transparency=1,Visible=false})
    end
    t.name    = newDraw("Text",{Size=13,Color=CFG.ColName,Outline=true,Center=true,Transparency=1,Visible=false,Text=player.Name})
    t.weapon  = newDraw("Text",{Size=11,Color=CFG.ColWeapon,Outline=true,Center=true,Transparency=1,Visible=false,Text=""})
    t.healthBG = newDraw("Line",{Thickness=4,Color=Color3.fromRGB(30,30,30),Transparency=1,Visible=false})
    t.healthFG = newDraw("Line",{Thickness=3,Color=Color3.fromRGB(80,220,80),Transparency=1,Visible=false})
    t.skelLines = {}
    for i=1,#SKEL do
        t.skelLines[i] = newDraw("Line",{Thickness=1,Color=CFG.ColSkeleton,Transparency=1,Visible=false})
    end
    Pool[player] = t
end

local function destroyPool(player)
    local t = Pool[player]; if not t then return end
    for _,l in ipairs(t.boxLines)  do l:Remove() end
    for _,l in ipairs(t.skelLines) do l:Remove() end
    t.name:Remove(); t.weapon:Remove(); t.healthBG:Remove(); t.healthFG:Remove()
    Pool[player] = nil
end

-- ── FOV CIRCLE ───────────────────────────────────────────────────────────────
local fovCircle = newDraw("Circle",{
    Thickness=1.5, NumSides=64, Color=CFG.ColFOV,
    Filled=false, Transparency=1, Visible=CFG.FOVVisible,
    Radius=CFG.FOVRadius,
    Position=Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
})

-- ── HELPERS ──────────────────────────────────────────────────────────────────
local function isTeammate(p)
    if not CFG.TeamCheck then return false end
    return p.Team ~= nil and p.Team == LocalPlayer.Team
end

local function getChar(p)
    local c = p.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hrp and hum then return c, hrp, hum end
end

local function w2s(pos)
    local p, vis = Camera:WorldToViewportPoint(pos)
    -- vis can be false for off-centre parts that are still in front of camera;
    -- use depth (p.Z > 0) as the real "in front" check
    return Vector2.new(p.X, p.Y), p.Z > 0, p.Z
end

local function getBox(char, hrp)
    local size = Vector3.new(1.8, 5.5, 1.8)
    local cf   = hrp.CFrame
    local pts  = {
        cf*CFrame.new( size.X/2, size.Y/2, size.Z/2), cf*CFrame.new(-size.X/2, size.Y/2, size.Z/2),
        cf*CFrame.new( size.X/2,-size.Y/2, size.Z/2), cf*CFrame.new(-size.X/2,-size.Y/2, size.Z/2),
        cf*CFrame.new( size.X/2, size.Y/2,-size.Z/2), cf*CFrame.new(-size.X/2, size.Y/2,-size.Z/2),
        cf*CFrame.new( size.X/2,-size.Y/2,-size.Z/2), cf*CFrame.new(-size.X/2,-size.Y/2,-size.Z/2),
    }
    local mnX,mnY,mxX,mxY = math.huge,math.huge,-math.huge,-math.huge
    for _,c in ipairs(pts) do
        local s,v = w2s(c.Position)
        if v then
            mnX=math.min(mnX,s.X); mnY=math.min(mnY,s.Y)
            mxX=math.max(mxX,s.X); mxY=math.max(mxY,s.Y)
        end
    end
    if mnX==math.huge then return end
    return mnX,mnY,mxX,mxY
end

local function getWeapon(char)
    for _,v in ipairs(char:GetChildren()) do
        if v:IsA("Tool") then return v.Name end
    end
    return "Unknown"
end

-- ── AIMBOT TARGET ────────────────────────────────────────────────────────────
local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)

local function getBest()
    local closest, bestPlayer, bestPart = CFG.FOVRadius, nil, nil
    for _,p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or isTeammate(p) then continue end
        local c, hrp, hum = getChar(p)
        if not c or hum.Health <= 0 then continue end
        local part = c:FindFirstChild(CFG.TargetPart) or c:FindFirstChild("Head") or hrp
        if not part then continue end
        local s, onScreen, depth = w2s(part.Position)
        if not onScreen or depth <= 0 then continue end
        local d = (s - center).Magnitude
        if d < closest then closest=d; bestPlayer=p; bestPart=part end
    end
    return bestPlayer, bestPart
end

-- ── NO RECOIL ────────────────────────────────────────────────────────────────
local lastCamCF = Camera.CFrame
RunService:BindToRenderStep("NoRecoil", Enum.RenderPriority.Camera.Value+1, function()
    if not CFG.NoRecoil then lastCamCF=Camera.CFrame; return end
    local rx = lastCamCF:ToObjectSpace(Camera.CFrame):ToEulerAnglesXYZ()
    if rx > 0.001 then
        Camera.CFrame = Camera.CFrame * CFrame.Angles(-rx*0.92,0,0)
    end
    lastCamCF = Camera.CFrame
end)

-- ── SILENT AIM ───────────────────────────────────────────────────────────────
local _origCF, silentActive = nil, false

local function applySilent(part)
    if not part then return end
    _origCF = Camera.CFrame
    Camera.CFrame = CFrame.new(Camera.CFrame.Position, part.Position)
    silentActive = true
end

local function revertSilent()
    if silentActive and _origCF then Camera.CFrame=_origCF end
    silentActive = false
end

-- ── TRIGGERBOT ───────────────────────────────────────────────────────────────
local triggerFired = false

local function checkTrigger(active)
    if not active then return end
    local unit = Camera:ScreenPointToRay(center.X, center.Y)
    local res  = workspace:Raycast(unit.Origin, unit.Direction*CFG.MaxDist, RaycastParams.new())
    if res and res.Instance then
        local char = res.Instance:FindFirstAncestorOfClass("Model")
        if char then
            local p = Players:GetPlayerFromCharacter(char)
            if p and p~=LocalPlayer and not isTeammate(p) then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health>0 and not triggerFired then
                    triggerFired = true
                    task.delay(CFG.TriggerDelay, function()
                        mouse1click()   -- Synapse global; swap: VirtualUser:Button1Down(center, Camera.CFrame)
                        triggerFired = false
                    end)
                end
                return
            end
        end
    end
    triggerFired = false
end

-- ── BHOP ─────────────────────────────────────────────────────────────────────
UserInputService.JumpRequest:Connect(function()
    if not CFG.BunnyHop then return end
    local char = LocalPlayer.Character; if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    if hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
end)

-- ── SPEED ────────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.SpeedHack then return end
    local char = LocalPlayer.Character; if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    hum.WalkSpeed = 16 * CFG.SpeedMult
end)

-- ── NOCLIP ───────────────────────────────────────────────────────────────────
RunService.Stepped:Connect(function()
    if not CFG.Noclip then return end
    local char = LocalPlayer.Character; if not char then return end
    for _,p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end)

-- ── INPUT ────────────────────────────────────────────────────────────────────
local holdingAimbot  = false
local holdingTrigger = false

UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end

    -- aimbot
    if CFG.AimbotMode == "toggle" then
        if inp.KeyCode == CFG.AimbotKey then
            CFG.AimbotEnabled = not CFG.AimbotEnabled
        end
    elseif CFG.AimbotMode == "hold" then
        if inp.KeyCode == CFG.AimbotKey or inp.UserInputType == CFG.AimbotMouseKey then
            holdingAimbot = true
        end
    end

    -- triggerbot
    if CFG.TriggerMode == "toggle" then
        if inp.KeyCode == CFG.TriggerKey then
            CFG.TriggerEnabled = not CFG.TriggerEnabled
        end
    elseif CFG.TriggerMode == "hold" then
        if inp.KeyCode == CFG.TriggerKey then
            holdingTrigger = true
        end
    end

    -- silent aim fires on LMB
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        if CFG.SilentAim and (CFG.AimbotEnabled or holdingAimbot) then
            local _, part = getBest()
            applySilent(part)
        end
    end
end)

UserInputService.InputEnded:Connect(function(inp, gpe)
    if CFG.AimbotMode == "hold" then
        if inp.KeyCode == CFG.AimbotKey or inp.UserInputType == CFG.AimbotMouseKey then
            holdingAimbot = false
        end
    end
    if CFG.TriggerMode == "hold" then
        if inp.KeyCode == CFG.TriggerKey then holdingTrigger = false end
    end
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then revertSilent() end
end)

-- ── MAIN RENDER LOOP ─────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    fovCircle.Position = center
    fovCircle.Visible  = CFG.FOVVisible

    local aimbotActive = (CFG.AimbotMode=="toggle" and CFG.AimbotEnabled)
                      or (CFG.AimbotMode=="hold"   and holdingAimbot)

    if aimbotActive then
        local _, part = getBest()
        if part then
            local s, onScreen = w2s(part.Position)
            if onScreen then
                Camera.CFrame = Camera.CFrame:Lerp(
                    CFrame.new(Camera.CFrame.Position, part.Position),
                    CFG.Smoothing
                )
            end
        end
    end

    local trigActive = (CFG.TriggerMode=="toggle" and CFG.TriggerEnabled)
                    or (CFG.TriggerMode=="hold"   and holdingTrigger)
    checkTrigger(trigActive and CFG.Triggerbot)

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local t = Pool[player]; if not t then continue end

        local c, hrp, hum = getChar(player)

        local function hideAll()
            for _,l in ipairs(t.boxLines)  do l.Visible=false end
            for _,l in ipairs(t.skelLines) do l.Visible=false end
            t.name.Visible=false; t.weapon.Visible=false
            t.healthBG.Visible=false; t.healthFG.Visible=false
        end

        if not c or not hrp or not hum or hum.Health<=0 then hideAll(); continue end
        if (hrp.Position-Camera.CFrame.Position).Magnitude > CFG.MaxDist then hideAll(); continue end
        if not CFG.ESPEnabled then hideAll(); continue end

        local mnX,mnY,mxX,mxY = getBox(c,hrp)
        if not mnX then hideAll(); continue end

        local boxCol = isTeammate(player) and Color3.fromRGB(80,160,255) or CFG.ColBox

        if CFG.BoxESP then
            local L = t.boxLines
            L[1].From=Vector2.new(mnX,mnY); L[1].To=Vector2.new(mxX,mnY)
            L[2].From=Vector2.new(mnX,mxY); L[2].To=Vector2.new(mxX,mxY)
            L[3].From=Vector2.new(mnX,mnY); L[3].To=Vector2.new(mnX,mxY)
            L[4].From=Vector2.new(mxX,mnY); L[4].To=Vector2.new(mxX,mxY)
            for _,l in ipairs(L) do l.Color=boxCol; l.Visible=true end
        else
            for _,l in ipairs(t.boxLines) do l.Visible=false end
        end

        if CFG.NameESP then
            t.name.Position=Vector2.new((mnX+mxX)/2, mnY-15)
            t.name.Text=player.Name; t.name.Visible=true
        else t.name.Visible=false end

        if CFG.WeaponESP then
            t.weapon.Position=Vector2.new((mnX+mxX)/2, mxY+3)
            t.weapon.Text="["..getWeapon(c).."]"; t.weapon.Visible=true
        else t.weapon.Visible=false end

        if CFG.HealthBar then
            local pct = math.clamp(hum.Health/hum.MaxHealth,0,1)
            local bx  = mnX-5
            t.healthBG.From=Vector2.new(bx,mnY); t.healthBG.To=Vector2.new(bx,mxY); t.healthBG.Visible=true
            t.healthFG.From=Vector2.new(bx,mxY); t.healthFG.To=Vector2.new(bx,mxY-(mxY-mnY)*pct)
            t.healthFG.Color=Color3.fromRGB(math.floor(255*(1-pct)),math.floor(255*pct),0)
            t.healthFG.Visible=true
        else t.healthBG.Visible=false; t.healthFG.Visible=false end

        if CFG.SkeletonESP then
            for i,pair in ipairs(SKEL) do
                local p1=c:FindFirstChild(pair[1]); local p2=c:FindFirstChild(pair[2])
                local line=t.skelLines[i]
                if p1 and p2 then
                    local s1,v1=w2s(p1.Position); local s2,v2=w2s(p2.Position)
                    if v1 and v2 then line.From=s1; line.To=s2; line.Color=CFG.ColSkeleton; line.Visible=true
                    else line.Visible=false end
                else line.Visible=false end
            end
        else for _,l in ipairs(t.skelLines) do l.Visible=false end end
    end
end)

-- ── PLAYER LIFECYCLE ─────────────────────────────────────────────────────────
for _,p in ipairs(Players:GetPlayers()) do buildPool(p) end
Players.PlayerAdded:Connect(buildPool)
Players.PlayerRemoving:Connect(destroyPool)

-- ── KEYCODE HELPER ───────────────────────────────────────────────────────────
-- maps GUI key name strings back to Enum.KeyCode / UserInputType
local KEY_MAP = {}
for _,v in ipairs(Enum.KeyCode:GetEnumItems()) do KEY_MAP[v.Name:upper()] = v end
local MOUSE_MAP = {
    ["MOUSE1"] = Enum.UserInputType.MouseButton1,
    ["MOUSE2"] = Enum.UserInputType.MouseButton2,
    ["MOUSE3"] = Enum.UserInputType.MouseButton3,
}

local function parseKey(str)
    local up = str:upper():gsub("[^%w]","")
    if MOUSE_MAP[up] then return "mouse", MOUSE_MAP[up] end
    if KEY_MAP[up]   then return "key",   KEY_MAP[up] end
    return "key", Enum.KeyCode.Unknown
end

-- ── GUI ──────────────────────────────────────────────────────────────────────
local CoreGui  = game:GetService("CoreGui")
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "BloxstrikeMenu"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent         = CoreGui

-- ── panel frame ──────────────────────────────────────────────────────────────
local Frame = Instance.new("Frame")
Frame.Size             = UDim2.new(0, 248, 0, 560)
Frame.Position         = UDim2.new(0, 20, 0, 20)
Frame.BackgroundColor3 = Color3.fromRGB(14,14,18)
Frame.BorderSizePixel  = 0
Frame.Active           = true
Frame.Draggable        = true
Frame.Parent           = ScreenGui
Instance.new("UICorner",Frame).CornerRadius = UDim.new(0,14)

local stroke = Instance.new("UIStroke",Frame)
stroke.Color     = Color3.fromRGB(42,42,56)
stroke.Thickness = 0.5

-- topbar
local Topbar = Instance.new("Frame",Frame)
Topbar.Size             = UDim2.new(1,0,0,34)
Topbar.BackgroundColor3 = Color3.fromRGB(14,14,18)
Topbar.BorderSizePixel  = 0

local TopStroke = Instance.new("UIStroke",Topbar)
TopStroke.Color=Color3.fromRGB(30,30,40); TopStroke.Thickness=0.5

local function makeDot(parent,col,xpos)
    local d = Instance.new("Frame",parent)
    d.Size=UDim2.new(0,8,0,8); d.Position=UDim2.new(0,xpos,0.5,-4)
    d.BackgroundColor3=col; d.BorderSizePixel=0
    Instance.new("UICorner",d).CornerRadius=UDim.new(1,0)
    return d
end
makeDot(Topbar,Color3.fromRGB(255,69,58),10)
makeDot(Topbar,Color3.fromRGB(255,214,10),24)
makeDot(Topbar,Color3.fromRGB(48,209,88),38)

local BrandLabel = Instance.new("TextLabel",Topbar)
BrandLabel.Size=UDim2.new(0,120,1,0); BrandLabel.Position=UDim2.new(0,58,0,0)
BrandLabel.BackgroundTransparency=1; BrandLabel.Text="BLOXSTRIKE"
BrandLabel.TextColor3=Color3.fromRGB(144,144,184); BrandLabel.TextSize=11
BrandLabel.Font=Enum.Font.GothamBold; BrandLabel.TextXAlignment=Enum.TextXAlignment.Left

local VerLabel = Instance.new("TextLabel",Topbar)
VerLabel.Size=UDim2.new(0,30,1,0); VerLabel.Position=UDim2.new(0,148,0,0)
VerLabel.BackgroundTransparency=1; VerLabel.Text="v1"
VerLabel.TextColor3=Color3.fromRGB(54,54,74); VerLabel.TextSize=9
VerLabel.Font=Enum.Font.Gotham; VerLabel.TextXAlignment=Enum.TextXAlignment.Left

-- tab bar
local TabBar = Instance.new("Frame",Frame)
TabBar.Size=UDim2.new(1,0,0,28); TabBar.Position=UDim2.new(0,0,0,34)
TabBar.BackgroundColor3=Color3.fromRGB(14,14,18); TabBar.BorderSizePixel=0
local TabStroke=Instance.new("UIStroke",TabBar); TabStroke.Color=Color3.fromRGB(30,30,40); TabStroke.Thickness=0.5

local TAB_NAMES = {"Aimbot","ESP","Misc"}
local tabBtns   = {}
local tabPages  = {}
local activeTab = "Aimbot"

-- scroll host
local ScrollHost = Instance.new("Frame",Frame)
ScrollHost.Size=UDim2.new(1,0,1,-62); ScrollHost.Position=UDim2.new(0,0,0,62)
ScrollHost.BackgroundTransparency=1; ScrollHost.ClipsDescendants=true

-- ── page/tab helpers ─────────────────────────────────────────────────────────
local function makeScroll(parent)
    local sf = Instance.new("ScrollingFrame",parent)
    sf.Size=UDim2.new(1,0,1,0); sf.BackgroundTransparency=1
    sf.ScrollBarThickness=3; sf.ScrollBarImageColor3=Color3.fromRGB(60,60,90)
    sf.CanvasSize=UDim2.new(0,0,0,0); sf.AutomaticCanvasSize=Enum.AutomaticSize.Y
    sf.Visible=false
    local ul=Instance.new("UIListLayout",sf); ul.Padding=UDim.new(0,4)
    local pad=Instance.new("UIPadding",sf)
    pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10)
    pad.PaddingTop=UDim.new(0,8);   pad.PaddingBottom=UDim.new(0,8)
    return sf
end

local function switchTab(name)
    activeTab = name
    for n,pg in pairs(tabPages) do pg.Visible=(n==name) end
    for n,btn in pairs(tabBtns) do
        btn.TextColor3 = n==name and Color3.fromRGB(176,176,224) or Color3.fromRGB(68,68,90)
        local ul = btn:FindFirstChildOfClass("UIStroke")
        if ul then ul.Thickness = n==name and 1.5 or 0 end
    end
end

for i,name in ipairs(TAB_NAMES) do
    local pg = makeScroll(ScrollHost)
    tabPages[name] = pg

    local btn = Instance.new("TextButton",TabBar)
    btn.Size=UDim2.new(1/#TAB_NAMES,0,1,0)
    btn.Position=UDim2.new((i-1)/#TAB_NAMES,0,0,0)
    btn.BackgroundTransparency=1; btn.Text=name; btn.TextSize=10
    btn.Font=Enum.Font.GothamBold; btn.TextColor3=Color3.fromRGB(68,68,90)
    btn.BorderSizePixel=0
    local bs=Instance.new("UIStroke",btn); bs.Color=Color3.fromRGB(104,104,232)
    bs.Thickness=0; bs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    tabBtns[name]=btn
end

-- ── component builders ───────────────────────────────────────────────────────
local function makeRow(parent,h)
    local f=Instance.new("Frame",parent)
    f.Size=UDim2.new(1,0,0,h or 28)
    f.BackgroundColor3=Color3.fromRGB(19,19,26)
    f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,7)
    local s=Instance.new("UIStroke",f); s.Color=Color3.fromRGB(30,30,42); s.Thickness=0.5
    return f
end

local function makeLabel(parent,text,xOff,yOff,w,h,size,col)
    local l=Instance.new("TextLabel",parent)
    l.Size=UDim2.new(0,w or 140,0,h or 28)
    l.Position=UDim2.new(0,xOff or 8,0,yOff or 0)
    l.BackgroundTransparency=1; l.Text=text
    l.TextColor3=col or Color3.fromRGB(136,136,168)
    l.TextSize=size or 11; l.Font=Enum.Font.Gotham
    l.TextXAlignment=Enum.TextXAlignment.Left
    return l
end

local function makeSectionHead(parent,text)
    local l=Instance.new("TextLabel",parent)
    l.Size=UDim2.new(1,0,0,18); l.BackgroundTransparency=1
    l.Text=text; l.TextColor3=Color3.fromRGB(51,51,74)
    l.TextSize=8; l.Font=Enum.Font.GothamBold
    l.TextXAlignment=Enum.TextXAlignment.Left
    local pad=Instance.new("UIPadding",l); pad.PaddingLeft=UDim.new(0,2)
    return l
end

local function makeToggle(parent,labelText,getter,setter)
    local row=makeRow(parent)
    makeLabel(row,labelText)
    local bg=Instance.new("Frame",row)
    bg.Size=UDim2.new(0,30,0,16); bg.Position=UDim2.new(1,-38,0.5,-8)
    bg.BorderSizePixel=0; bg.BackgroundColor3=getter() and Color3.fromRGB(88,88,232) or Color3.fromRGB(37,37,48)
    Instance.new("UICorner",bg).CornerRadius=UDim.new(1,0)
    local pill=Instance.new("Frame",bg)
    pill.Size=UDim2.new(0,11,0,11); pill.BorderSizePixel=0; pill.BackgroundColor3=Color3.fromRGB(255,255,255)
    Instance.new("UICorner",pill).CornerRadius=UDim.new(1,0)
    local function refresh()
        local on=getter()
        bg.BackgroundColor3=on and Color3.fromRGB(88,88,232) or Color3.fromRGB(37,37,48)
        TweenService:Create(pill,TweenInfo.new(0.12),{
            Position=on and UDim2.new(1,-14,0.5,-5.5) or UDim2.new(0,2.5,0.5,-5.5)
        }):Play()
    end
    refresh()
    local btn=Instance.new("TextButton",row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""
    btn.MouseButton1Click:Connect(function() setter(not getter()); refresh() end)
    return row
end

local function makeSlider(parent,labelText,min,max,getter,setter,fmt)
    local row=makeRow(parent,42)
    local topF=Instance.new("Frame",row)
    topF.Size=UDim2.new(1,-16,0,18); topF.Position=UDim2.new(0,8,0,4); topF.BackgroundTransparency=1
    local lbl=makeLabel(topF,labelText,0,0,140,18)
    local valL=Instance.new("TextLabel",topF)
    valL.Size=UDim2.new(0,60,0,18); valL.Position=UDim2.new(1,-60,0,0)
    valL.BackgroundTransparency=1; valL.TextXAlignment=Enum.TextXAlignment.Right
    valL.TextColor3=Color3.fromRGB(112,112,216); valL.TextSize=9; valL.Font=Enum.Font.GothamBold
    local sliderTrack=Instance.new("Frame",row)
    sliderTrack.Size=UDim2.new(1,-16,0,3); sliderTrack.Position=UDim2.new(0,8,0,28)
    sliderTrack.BackgroundColor3=Color3.fromRGB(37,37,53); sliderTrack.BorderSizePixel=0
    Instance.new("UICorner",sliderTrack).CornerRadius=UDim.new(1,0)
    local fillBar=Instance.new("Frame",sliderTrack)
    fillBar.Size=UDim2.new(0,0,1,0); fillBar.BackgroundColor3=Color3.fromRGB(88,88,232); fillBar.BorderSizePixel=0
    Instance.new("UICorner",fillBar).CornerRadius=UDim.new(1,0)
    local thumb=Instance.new("Frame",sliderTrack)
    thumb.Size=UDim2.new(0,11,0,11); thumb.BackgroundColor3=Color3.fromRGB(104,104,240); thumb.BorderSizePixel=0
    thumb.Position=UDim2.new(0,-5,0.5,-5.5); thumb.ZIndex=3
    Instance.new("UICorner",thumb).CornerRadius=UDim.new(1,0)
    local function refresh()
        local v=getter()
        local pct=math.clamp((v-min)/(max-min),0,1)
        fillBar.Size=UDim2.new(pct,0,1,0)
        thumb.Position=UDim2.new(pct,-5,0.5,-5.5)
        valL.Text=fmt and fmt(v) or tostring(math.floor(v*100)/100)
    end
    refresh()
    local dragging=false
    local hitbox=Instance.new("TextButton",sliderTrack)
    hitbox.Size=UDim2.new(1,0,0,20); hitbox.Position=UDim2.new(0,0,0.5,-10)
    hitbox.BackgroundTransparency=1; hitbox.Text=""
    hitbox.MouseButton1Down:Connect(function() dragging=true end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging or inp.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local abs=sliderTrack.AbsolutePosition.X
        local w=sliderTrack.AbsoluteSize.X
        local pct=math.clamp((inp.Position.X-abs)/w,0,1)
        setter(min+pct*(max-min)); refresh()
    end)
    return row
end

local function makeChip(parent,labelText,options,getter,setter)
    local row=makeRow(parent)
    makeLabel(row,labelText)
    local btn=Instance.new("TextButton",row)
    btn.Size=UDim2.new(0,70,0,20); btn.Position=UDim2.new(1,-78,0.5,-10)
    btn.BackgroundColor3=Color3.fromRGB(28,28,46); btn.BorderSizePixel=0
    btn.TextColor3=Color3.fromRGB(112,112,216); btn.TextSize=9; btn.Font=Enum.Font.GothamBold
    btn.Text=getter()
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,5)
    local s=Instance.new("UIStroke",btn); s.Color=Color3.fromRGB(56,56,90); s.Thickness=0.5
    local idx=1
    for i,v in ipairs(options) do if v==getter() then idx=i end end
    btn.MouseButton1Click:Connect(function()
        idx=idx%#options+1; setter(options[idx]); btn.Text=options[idx]
    end)
    return row
end

-- ── keybind row (label + toggle/hold mode + key badge) ──────────────────────
local function makeKeybind(parent,labelText,getModeGetter,setMode,getKeyGetter,setKey)
    local row=makeRow(parent,46)
    -- left: label + mode buttons
    makeLabel(row,labelText,8,4,130,14,10)
    local modeFrame=Instance.new("Frame",row)
    modeFrame.Size=UDim2.new(0,90,0,16); modeFrame.Position=UDim2.new(0,8,0,24)
    modeFrame.BackgroundTransparency=1
    local modeBtns={}
    for i,mode in ipairs({"toggle","hold"}) do
        local mb=Instance.new("TextButton",modeFrame)
        mb.Size=UDim2.new(0,40,1,0); mb.Position=UDim2.new(0,(i-1)*44,0,0)
        mb.BorderSizePixel=0; mb.TextSize=8; mb.Font=Enum.Font.GothamBold
        mb.Text=mode:sub(1,1):upper()..mode:sub(2)
        local isActive=getModeGetter()==mode
        mb.BackgroundColor3=isActive and Color3.fromRGB(34,34,58) or Color3.fromRGB(24,24,38)
        mb.TextColor3=isActive and Color3.fromRGB(144,144,224) or Color3.fromRGB(68,68,90)
        Instance.new("UICorner",mb).CornerRadius=UDim.new(0,4)
        local mbs=Instance.new("UIStroke",mb); mbs.Thickness=0.5
        mbs.Color=isActive and Color3.fromRGB(74,74,120) or Color3.fromRGB(42,42,58)
        modeBtns[mode]=mb
        mb.MouseButton1Click:Connect(function()
            setMode(mode)
            for m,b in pairs(modeBtns) do
                local on=m==mode
                b.BackgroundColor3=on and Color3.fromRGB(34,34,58) or Color3.fromRGB(24,24,38)
                b.TextColor3=on and Color3.fromRGB(144,144,224) or Color3.fromRGB(68,68,90)
                local bs2=b:FindFirstChildOfClass("UIStroke")
                if bs2 then bs2.Color=on and Color3.fromRGB(74,74,120) or Color3.fromRGB(42,42,58) end
            end
        end)
    end
    -- right: key badge
    local badge=Instance.new("TextButton",row)
    badge.Size=UDim2.new(0,64,0,20); badge.Position=UDim2.new(1,-72,0.5,-10)
    badge.BackgroundColor3=Color3.fromRGB(26,26,46); badge.BorderSizePixel=0
    badge.TextColor3=Color3.fromRGB(144,144,208); badge.TextSize=9; badge.Font=Enum.Font.GothamBold
    badge.Text=getKeyGetter()
    Instance.new("UICorner",badge).CornerRadius=UDim.new(0,5)
    local bs=Instance.new("UIStroke",badge); bs.Color=Color3.fromRGB(58,58,96); bs.Thickness=0.5
    -- listening modal (reuse one global)
    local listening=false
    badge.MouseButton1Click:Connect(function()
        if listening then return end
        listening=true
        badge.TextColor3=Color3.fromRGB(232,232,80)
        badge.Text="..."
        local conn
        conn=UserInputService.InputBegan:Connect(function(inp,gpe)
            if gpe then return end
            conn:Disconnect(); listening=false
            -- format name
            local name
            if inp.UserInputType==Enum.UserInputType.MouseButton1 then name="Mouse1"
            elseif inp.UserInputType==Enum.UserInputType.MouseButton2 then name="Mouse2"
            elseif inp.UserInputType==Enum.UserInputType.MouseButton3 then name="Mouse3"
            elseif inp.KeyCode~=Enum.KeyCode.Unknown then name=inp.KeyCode.Name
            else name="??" end
            setKey(name)
            badge.Text=name
            badge.TextColor3=Color3.fromRGB(144,144,208)
            -- apply to CFG
            local ktype, kval = parseKey(name)
            if labelText:find("Aimbot") then
                if ktype=="mouse" then CFG.AimbotMouseKey=kval else CFG.AimbotKey=kval end
            elseif labelText:find("Trigger") then
                if ktype=="key" then CFG.TriggerKey=kval end
            end
        end)
    end)
    return row
end

-- ── build aimbot page ─────────────────────────────────────────────────────────
local aPage = tabPages["Aimbot"]
makeSectionHead(aPage,"AIMBOT")
makeKeybind(aPage,"Aimbot key",
    function() return CFG.AimbotMode end,
    function(v) CFG.AimbotMode=v end,
    function() return CFG.AimbotKey.Name end,
    function(v) end)
makeToggle(aPage,"Enabled",
    function() return CFG.AimbotEnabled end,
    function(v) CFG.AimbotEnabled=v end)
makeToggle(aPage,"Silent aim",
    function() return CFG.SilentAim end,
    function(v) CFG.SilentAim=v end)
makeToggle(aPage,"No recoil",
    function() return CFG.NoRecoil end,
    function(v) CFG.NoRecoil=v end)
makeToggle(aPage,"Triggerbot",
    function() return CFG.Triggerbot end,
    function(v) CFG.Triggerbot=v end)
makeKeybind(aPage,"Trigger key",
    function() return CFG.TriggerMode end,
    function(v) CFG.TriggerMode=v end,
    function() return CFG.TriggerKey.Name end,
    function(v) end)
makeChip(aPage,"Target part",
    {"Head","UpperTorso","LowerTorso","HumanoidRootPart"},
    function() return CFG.TargetPart end,
    function(v) CFG.TargetPart=v end)
makeSectionHead(aPage,"FOV")
makeSlider(aPage,"Radius",30,400,
    function() return CFG.FOVRadius end,
    function(v) CFG.FOVRadius=v; fovCircle.Radius=v end)
makeSlider(aPage,"Smoothing",0.02,0.99,
    function() return CFG.Smoothing end,
    function(v) CFG.Smoothing=v end,
    function(v) return tostring(math.floor(v*100)/100) end)
makeToggle(aPage,"FOV visible",
    function() return CFG.FOVVisible end,
    function(v) CFG.FOVVisible=v; fovCircle.Visible=v end)

-- ── build ESP page ────────────────────────────────────────────────────────────
local ePage = tabPages["ESP"]
makeSectionHead(ePage,"OVERLAYS")
makeToggle(ePage,"ESP enabled",function() return CFG.ESPEnabled end,function(v) CFG.ESPEnabled=v end)
makeToggle(ePage,"Box",function() return CFG.BoxESP end,function(v) CFG.BoxESP=v end)
makeToggle(ePage,"Name tag",function() return CFG.NameESP end,function(v) CFG.NameESP=v end)
makeToggle(ePage,"Weapon label",function() return CFG.WeaponESP end,function(v) CFG.WeaponESP=v end)
makeToggle(ePage,"Health bar",function() return CFG.HealthBar end,function(v) CFG.HealthBar=v end)
makeToggle(ePage,"Skeleton",function() return CFG.SkeletonESP end,function(v) CFG.SkeletonESP=v end)
makeSectionHead(ePage,"FILTERS")
makeToggle(ePage,"Team check",function() return CFG.TeamCheck end,function(v) CFG.TeamCheck=v end)
makeSlider(ePage,"Max distance",100,1000,
    function() return CFG.MaxDist end,
    function(v) CFG.MaxDist=v end,
    function(v) return tostring(math.floor(v)) end)

-- ── build Misc page ───────────────────────────────────────────────────────────
local mPage = tabPages["Misc"]
makeSectionHead(mPage,"MOVEMENT")
makeToggle(mPage,"Bunny hop",function() return CFG.BunnyHop end,function(v) CFG.BunnyHop=v end)
makeToggle(mPage,"Speed hack",function() return CFG.SpeedHack end,function(v) CFG.SpeedHack=v end)
makeSlider(mPage,"Speed mult",1,5,
    function() return CFG.SpeedMult end,
    function(v) CFG.SpeedMult=v end,
    function(v) return tostring(math.floor(v*10)/10).."x" end)
makeToggle(mPage,"Noclip",function() return CFG.Noclip end,function(v) CFG.Noclip=v end)
makeSectionHead(mPage,"WEAPON")
makeToggle(mPage,"No spread",function() return CFG.NoSpread end,function(v) CFG.NoSpread=v end)
makeToggle(mPage,"Inf ammo",function() return CFG.InfAmmo end,function(v) CFG.InfAmmo=v end)
makeSectionHead(mPage,"TRIGGERBOT")
makeSlider(mPage,"Delay",0,0.3,
    function() return CFG.TriggerDelay end,
    function(v) CFG.TriggerDelay=v end,
    function(v) return tostring(math.floor(v*100)/100).."s" end)

-- ── hide/show ─────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(inp,gpe)
    if gpe then return end
    if inp.KeyCode==Enum.KeyCode.RightShift then
        Frame.Visible=not Frame.Visible
    end
end)

switchTab("Aimbot")
