if getgenv then getgenv().ConfirmLuna = true end
if not identifyexecutor then identifyexecutor = function() return "Unknown" end end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera

local Cfg = {
    Aimbot = {
        Enabled    = false,
        HoldMode   = true,
        FOV        = 150,
        Smoothness = 8,
        Prediction = 0,
        LockPart   = "Head",
        TeamCheck  = false,
        AliveCheck = true,
        WallCheck  = false,
        ShowFOV    = true,
    },
    ESP = {
        Enabled    = false,
        Boxes      = true,
        Tracers    = true,
        HealthBars = true,
        Names      = true,
        Distance   = true,
    },
}

local State = {
    AimbotOn   = false,
    Target     = nil,
    ESPPool    = {},
    RenderConn = nil,
    Unloaded   = false,
}

local FOVCircle, FOVCircleOutline

local function InitFOV()
    FOVCircleOutline           = Drawing.new("Circle")
    FOVCircleOutline.Visible   = false
    FOVCircleOutline.Filled    = false
    FOVCircleOutline.Color     = Color3.fromRGB(0, 0, 0)
    FOVCircleOutline.Thickness = 3
    FOVCircleOutline.NumSides  = 64

    FOVCircle               = Drawing.new("Circle")
    FOVCircle.Visible       = false
    FOVCircle.Filled        = false
    FOVCircle.Color         = Color3.fromRGB(255, 255, 255)
    FOVCircle.Thickness     = 1.5
    FOVCircle.Transparency  = 1
    FOVCircle.NumSides      = 64
end

local function StepFOV()
    if not FOVCircle then return end
    local show = Cfg.Aimbot.Enabled and Cfg.Aimbot.ShowFOV
    local mpos = UserInputService:GetMouseLocation()

    FOVCircle.Position        = mpos
    FOVCircle.Radius          = Cfg.Aimbot.FOV
    FOVCircle.Visible         = show

    FOVCircleOutline.Position = mpos
    FOVCircleOutline.Radius   = Cfg.Aimbot.FOV
    FOVCircleOutline.Visible  = show

    FOVCircle.Color = State.Target
        and Color3.fromRGB(255, 70, 70)
        or  Color3.fromRGB(255, 255, 255)
end

local function W2V(pos)
    local v, vis = Camera:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), v.Z > 0 and vis
end

local function IsAlive(plr)
    local c = plr.Character
    if not c then return false end
    local h = c:FindFirstChildWhichIsA("Humanoid")
    return h ~= nil and h.Health > 0
end

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude

local function IsOccluded(pos)
    if not Cfg.Aimbot.WallCheck then return false end
    if LocalPlayer.Character then
        RayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    end
    local origin    = Camera.CFrame.Position
    local direction = pos - origin
    local result    = workspace:Raycast(origin, direction, RayParams)
    return result ~= nil
end

local function FindTarget()
    local best     = nil
    local bestDist = math.huge
    local mpos     = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local skip = false

            if Cfg.Aimbot.AliveCheck and not IsAlive(plr) then skip = true end
            if Cfg.Aimbot.TeamCheck and LocalPlayer.Team ~= nil
                and plr.Team == LocalPlayer.Team then skip = true end

            if not skip then
                local char = plr.Character
                if char then
                    local part = char:FindFirstChild(Cfg.Aimbot.LockPart)
                               or char:FindFirstChild("HumanoidRootPart")

                    if part and not IsOccluded(part.Position) then
                        local spos, vis = W2V(part.Position)
                        if vis then
                            local dist = (spos - mpos).Magnitude
                            if dist < Cfg.Aimbot.FOV and dist < bestDist then
                                bestDist = dist
                                best     = part
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

local function ValidateTarget()
    if not State.Target then return false end

    local part = State.Target
    if not part or not part.Parent then return false end

    local char = part.Parent
    if not char then return false end

    local plr = Players:GetPlayerFromCharacter(char)
    if not plr then return false end

    if Cfg.Aimbot.AliveCheck and not IsAlive(plr) then return false end
    if Cfg.Aimbot.TeamCheck and LocalPlayer.Team ~= nil
        and plr.Team == LocalPlayer.Team then return false end
    if IsOccluded(part.Position) then return false end

    local spos, vis = W2V(part.Position)
    if not vis then return false end

    local mpos = UserInputService:GetMouseLocation()
    if (spos - mpos).Magnitude > Cfg.Aimbot.FOV then return false end

    return true
end

local function ApplyAim(dt)
    local part = State.Target
    if not part then return end

    local aimPos = part.Position
    if Cfg.Aimbot.Prediction > 0 then
        local char = part.Parent
        local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
        if hum and hum.MoveDirection.Magnitude > 0 then
            aimPos = aimPos + hum.MoveDirection * Cfg.Aimbot.Prediction
        end
    end

    local alpha   = math.clamp((1 / math.max(Cfg.Aimbot.Smoothness, 1)) * (dt * 60), 0, 1)
    local current = Camera.CFrame
    local goal    = CFrame.new(current.Position, aimPos)

    local newCF = CFrame.new(current.Position) * current:ToObjectSpace(
        CFrame.new(current.Position)
    ):Lerp(CFrame.new(current.Position):ToObjectSpace(goal), alpha)

    Camera.CFrame = current:Lerp(goal, alpha)
end

local function StepAimbot(dt)
    if not Cfg.Aimbot.Enabled or not State.AimbotOn then
        State.Target = nil
        return
    end

    if not ValidateTarget() then
        State.Target = FindTarget()
    end

    if State.Target then
        ApplyAim(dt)
    end
end

local function MakeESPEntry()
    local function Sq()
        local s = Drawing.new("Square")
        s.Thickness = 1; s.Filled = false
        s.Color = Color3.fromRGB(255, 50, 50); s.Visible = false
        return s
    end
    local function SqOutline()
        local s = Drawing.new("Square")
        s.Thickness = 3; s.Filled = false
        s.Color = Color3.fromRGB(0, 0, 0); s.Visible = false
        return s
    end
    local function Ln(thick, col)
        local l = Drawing.new("Line")
        l.Thickness = thick; l.Color = col; l.Visible = false
        return l
    end

    local nameTag      = Drawing.new("Text")
    nameTag.Size       = 13
    nameTag.Center     = true
    nameTag.Outline    = true
    nameTag.Color      = Color3.fromRGB(255, 255, 255)
    nameTag.Visible    = false

    return {
        box            = Sq(),
        boxOutline     = SqOutline(),
        tracer         = Ln(1, Color3.fromRGB(255, 50, 50)),
        tracerOutline  = Ln(3, Color3.fromRGB(0, 0, 0)),
        hpBg           = Ln(4, Color3.fromRGB(0, 0, 0)),
        hpBar          = Ln(3, Color3.fromRGB(0, 255, 0)),
        nameTag        = nameTag,
    }
end

local function DestroyESPEntry(e)
    if not e then return end
    for _, d in pairs(e) do pcall(function() d:Remove() end) end
end

local function HideEntry(e)
    for _, d in pairs(e) do d.Visible = false end
end

local function AddPlayer(plr)
    if plr == LocalPlayer then return end
    if State.ESPPool[plr] then return end
    State.ESPPool[plr] = MakeESPEntry()
end

local function RemovePlayer(plr)
    local e = State.ESPPool[plr]
    if not e then return end
    DestroyESPEntry(e)
    State.ESPPool[plr] = nil
end

local function StepESP()
    for plr, e in pairs(State.ESPPool) do
        if not plr or not plr.Parent then
            RemovePlayer(plr)
        else
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")
            local hum  = char and char:FindFirstChildWhichIsA("Humanoid")

            local hidden = not Cfg.ESP.Enabled
                or not char or not root or not head or not hum
                or hum.Health <= 0

            if hidden then
                HideEntry(e)
            else
                local headTop    = head.Position + Vector3.new(0, head.Size.Y * 0.5, 0)
                local rootBottom = root.Position - Vector3.new(0, 3.0, 0)

                local topSc,  topD,  topVis  = W2V(headTop)
                local botSc,  botD,  botVis  = W2V(rootBottom)
                local rootSc, rootD, rootVis = W2V(root.Position)

                if not rootVis or topD <= 0 then
                    HideEntry(e)
                else
                    local h = math.abs(botSc.Y - topSc.Y)
                    local w = h * 0.55
                    if h < 1 then h = 1 end

                    local left = rootSc.X - w * 0.5
                    local top2 = topSc.Y

                    if Cfg.ESP.Boxes then
                        e.boxOutline.Size     = Vector2.new(w + 2, h + 2)
                        e.boxOutline.Position = Vector2.new(left - 1, top2 - 1)
                        e.boxOutline.Visible  = true
                        e.box.Size            = Vector2.new(w, h)
                        e.box.Position        = Vector2.new(left, top2)
                        e.box.Visible         = true
                    else
                        e.box.Visible = false; e.boxOutline.Visible = false
                    end

                    if Cfg.ESP.Tracers then
                        local origin = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        e.tracerOutline.From = origin; e.tracerOutline.To = rootSc; e.tracerOutline.Visible = true
                        e.tracer.From        = origin; e.tracer.To        = rootSc; e.tracer.Visible        = true
                    else
                        e.tracer.Visible = false; e.tracerOutline.Visible = false
                    end

                    if Cfg.ESP.HealthBars then
                        local hp   = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        local barX = left - 5
                        local g    = math.floor(255 * hp)
                        local r    = 255 - g

                        e.hpBg.From    = Vector2.new(barX, top2)
                        e.hpBg.To      = Vector2.new(barX, top2 + h)
                        e.hpBg.Visible = true

                        e.hpBar.From    = Vector2.new(barX, top2 + h)
                        e.hpBar.To      = Vector2.new(barX, top2 + h - h * hp)
                        e.hpBar.Color   = Color3.fromRGB(r, g, 0)
                        e.hpBar.Visible = true
                    else
                        e.hpBg.Visible = false; e.hpBar.Visible = false
                    end

                    if Cfg.ESP.Names then
                        local label = plr.Name
                        if Cfg.ESP.Distance then
                            local d = math.floor((Camera.CFrame.Position - root.Position).Magnitude)
                            label   = plr.Name .. " [" .. d .. "m]"
                        end
                        e.nameTag.Text     = label
                        e.nameTag.Position = Vector2.new(rootSc.X, top2 - 16)
                        e.nameTag.Visible  = true
                    else
                        e.nameTag.Visible = false
                    end
                end
            end
        end
    end
end

local function StartRender()
    if State.RenderConn then return end
    State.RenderConn = RunService.RenderStepped:Connect(function(dt)
        if State.Unloaded then return end
        StepFOV()
        StepAimbot(dt)
        StepESP()
    end)
end

local function Unload()
    if State.Unloaded then return end
    State.Unloaded = true
    if State.RenderConn then State.RenderConn:Disconnect() end
    for plr in pairs(State.ESPPool) do RemovePlayer(plr) end
    pcall(function() FOVCircle:Remove() end)
    pcall(function() FOVCircleOutline:Remove() end)
    pcall(function() Luna:Destroy() end)
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if Cfg.Aimbot.HoldMode then
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.AimbotOn = true
        end
    else
        if input.KeyCode == Enum.KeyCode.Z then
            State.AimbotOn = not State.AimbotOn
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end
    if Cfg.Aimbot.HoldMode then
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.AimbotOn = false
            State.Target   = nil
        end
    end
end)

Players.PlayerAdded:Connect(function(plr)
    AddPlayer(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        if not State.ESPPool[plr] then AddPlayer(plr) end
    end)
end)

Players.PlayerRemoving:Connect(RemovePlayer)

for _, plr in ipairs(Players:GetPlayers()) do
    AddPlayer(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        if not State.ESPPool[plr] then AddPlayer(plr) end
    end)
end

InitFOV()
StartRender()

local Luna = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/refs/heads/master/source.lua",
    true
))()

local Window = Luna:CreateWindow({
    Name           = "Aimbot + ESP",
    Subtitle       = "by EpicScripts67",
    LogoID         = nil,
    LoadingEnabled = false,
    KeySystem      = false,
    ConfigSettings = { RootFolder = nil, ConfigFolder = "AimbotESP" }
})

Window:CreateHomeTab({ SupportedExecutors = {}, DiscordInvite = "", Icon = 1 })

local AimbotTab = Window:CreateTab({
    Name = "Aimbot", Icon = "view_in_ar", ImageSource = "Material", ShowTitle = true
})

local AimMain = AimbotTab:CreateSection("Main")

AimMain:CreateToggle({
    Name = "Enable Aimbot",
    Description = "Activates aim assistance.",
    CurrentValue = Cfg.Aimbot.Enabled,
    Callback = function(v) Cfg.Aimbot.Enabled = v end
}, "AimbotEnabled")

AimMain:CreateToggle({
    Name = "Hold Mode (Right Click)",
    Description = "Hold RMB to aim. Off = press Z to toggle.",
    CurrentValue = Cfg.Aimbot.HoldMode,
    Callback = function(v)
        Cfg.Aimbot.HoldMode = v
        State.AimbotOn = false
        State.Target   = nil
    end
}, "HoldMode")

AimMain:CreateToggle({
    Name = "Show FOV Circle",
    Description = "Draws the aim radius on screen.",
    CurrentValue = Cfg.Aimbot.ShowFOV,
    Callback = function(v) Cfg.Aimbot.ShowFOV = v end
}, "ShowFOV")

local AimFilters = AimbotTab:CreateSection("Filters")

AimFilters:CreateToggle({
    Name = "Alive Check",
    Description = "Only target players with health above 0.",
    CurrentValue = Cfg.Aimbot.AliveCheck,
    Callback = function(v) Cfg.Aimbot.AliveCheck = v end
}, "AliveCheck")

AimFilters:CreateToggle({
    Name = "Team Check",
    Description = "Skip players on your team.",
    CurrentValue = Cfg.Aimbot.TeamCheck,
    Callback = function(v) Cfg.Aimbot.TeamCheck = v end
}, "TeamCheck")

AimFilters:CreateToggle({
    Name = "Wall Check",
    Description = "Skip players behind walls.",
    CurrentValue = Cfg.Aimbot.WallCheck,
    Callback = function(v) Cfg.Aimbot.WallCheck = v end
}, "WallCheck")

local AimSettings = AimbotTab:CreateSection("Settings")

AimSettings:CreateDropdown({
    Name = "Lock Part",
    Options = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
    CurrentOption = { Cfg.Aimbot.LockPart },
    MultipleOptions = false,
    Callback = function(v)
        Cfg.Aimbot.LockPart = type(v) == "table" and v[1] or v
        State.Target = nil
    end
}, "LockPart")

AimSettings:CreateSlider({
    Name = "FOV Radius",
    Range = { 30, 400 }, Increment = 5, CurrentValue = Cfg.Aimbot.FOV,
    Callback = function(v) Cfg.Aimbot.FOV = v end
}, "FOVRadius")

AimSettings:CreateSlider({
    Name = "Smoothness",
    Description = "1 = instant lock. Higher = slower, smoother arc.",
    Range = { 1, 30 }, Increment = 1, CurrentValue = Cfg.Aimbot.Smoothness,
    Callback = function(v) Cfg.Aimbot.Smoothness = v end
}, "Smoothness")

AimSettings:CreateSlider({
    Name = "Prediction",
    Description = "Lead the target by their movement direction. 0 = off.",
    Range = { 0, 20 }, Increment = 1, CurrentValue = 0,
    Callback = function(v) Cfg.Aimbot.Prediction = v * 0.15 end
}, "Prediction")

local ESPTab = Window:CreateTab({
    Name = "ESP", Icon = "visibility", ImageSource = "Material", ShowTitle = true
})

local ESPToggles = ESPTab:CreateSection("Toggles")

ESPToggles:CreateToggle({
    Name = "Enable ESP",
    Description = "Master toggle for all ESP elements.",
    CurrentValue = Cfg.ESP.Enabled,
    Callback = function(v) Cfg.ESP.Enabled = v end
}, "ESPEnabled")

ESPToggles:CreateToggle({
    Name = "Boxes",
    Description = "Bounding boxes around players.",
    CurrentValue = Cfg.ESP.Boxes,
    Callback = function(v) Cfg.ESP.Boxes = v end
}, "ESPBoxes")

ESPToggles:CreateToggle({
    Name = "Tracers",
    Description = "Lines from screen bottom to each player.",
    CurrentValue = Cfg.ESP.Tracers,
    Callback = function(v) Cfg.ESP.Tracers = v end
}, "ESPTracers")

ESPToggles:CreateToggle({
    Name = "Health Bars",
    Description = "HP bars on the left side of each box.",
    CurrentValue = Cfg.ESP.HealthBars,
    Callback = function(v) Cfg.ESP.HealthBars = v end
}, "ESPHealth")

ESPToggles:CreateToggle({
    Name = "Name Tags",
    Description = "Player name above each box.",
    CurrentValue = Cfg.ESP.Names,
    Callback = function(v) Cfg.ESP.Names = v end
}, "ESPNames")

ESPToggles:CreateToggle({
    Name = "Distance",
    Description = "Show studs distance next to name.",
    CurrentValue = Cfg.ESP.Distance,
    Callback = function(v) Cfg.ESP.Distance = v end
}, "ESPDistance")

local MiscTab = Window:CreateTab({
    Name = "Misc", Icon = "settings", ImageSource = "Material", ShowTitle = true
})

local MiscSection = MiscTab:CreateSection("Script")

MiscSection:CreateButton({
    Name = "Copy Discord",
    Description = "Copy the Discord invite link.",
    Callback = function()
        setclipboard("https://discord.com/invite/u5SM9tFFTV")
        Luna:Notification({
            Title       = "Copied",
            Content     = "Discord link copied to clipboard.",
            Icon        = "content_copy",
            ImageSource = "Material",
        })
    end
})

MiscSection:CreateButton({
    Name = "Unload",
    Description = "Remove the script entirely.",
    Callback = Unload
})

setclipboard("https://discord.com/invite/u5SM9tFFTV")
Luna:Notification({
    Title       = "Aimbot + ESP",
    Icon        = "sports_esports",
    ImageSource = "Material",
    Content     = "Loaded. Right click to aim. Discord copied."
})
