-- ============================================================
--  STEAL AN EGG -- Rebuild v2.0
--  Clean architecture, no external dependencies
-- ============================================================

-- ============================================================
-- SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer

-- ============================================================
-- MODULE LOADER
-- ============================================================
local EggState, PlotState, Assets, RarityModule, AreaEggSlotIdentity
local ModulesLoaded = false

local function tryRequire(...)
    for _, path in ipairs({...}) do
        local ok, result = pcall(function()
            local cur = ReplicatedStorage
            for seg in string.gmatch(path, "[^.]+") do
                cur = cur:FindFirstChild(seg)
                if not cur then return nil end
            end
            return require(cur)
        end)
        if ok and result then return result end
    end
    return nil
end

local function loadModules()
    if ModulesLoaded then return true end
    EggState            = tryRequire("Client.EggState",  "Shared.EggState")
    PlotState           = tryRequire("Client.PlotState", "Shared.PlotState")
    Assets              = tryRequire("Data.Assets",      "Shared.Assets", "Assets")
    RarityModule        = tryRequire("Data.Rarity",      "Shared.Rarity", "Rarity")
    AreaEggSlotIdentity = tryRequire("Shared.Util.AreaEggSlotIdentity", "Util.AreaEggSlotIdentity")
    -- GameRemotes dihapus -- require(Shared.Remotes) = BAC
    ModulesLoaded       = EggState ~= nil and PlotState ~= nil
    return ModulesLoaded
end

-- ============================================================
-- STATE
-- ============================================================
local State = {
    -- Farm
    running           = false,
    busy              = false,
    stealCount        = 0,
    lockedRecord      = nil,
    -- Movement
    speed             = 120,
    antiGuard         = true,
    -- Farm rarity filter
    targetRarities    = {},
    minEarningRate    = 0,
    minModelWeight    = 0,
    maxModelWeight    = 999999999,
    -- Float
    floatEnabled      = false,
    floatHeight       = 3,
    -- Animation
    animEnabled       = true,
    -- Auto Place (independent loop)
    placeEnabled      = false,
    placeInterval     = 5,
    placeMinRarity    = "All",
    -- Auto Place Pet
    placePetEnabled      = false,
    placePetInterval     = 5,
    placeBestPetEnabled  = false,
    placeBestPetInterval = 10,
    -- No Knockback
    noKnockback       = false,
    -- Backpack threshold auto place
    _placing          = false,
    -- Collect Money
    collectEnabled    = false,
    collectInterval   = 60,
    -- Auto Favorite
    favPetEnabled     = false,
    favEggEnabled     = false,
    favoriteInterval  = 30,
    favMinRarities    = {},  -- multi-select {[name]=true}
    -- Auto Hatch (independent loop)
    hatchEnabled      = false,
    hatchInterval     = 3,
    -- Auto Sell
    sellEnabled       = false,
    sellAll           = false,
    sellInterval      = 5,
    sellMaxRarities   = {},  -- {[name]=true}
    -- Auto Sell Egg
    sellEggEnabled    = false,
    sellEggInterval   = 10,
    sellEggMaxRarities = {},
    -- Auto Sell Pet
    sellPetMaxRarities = {},
    sellPetInterval   = 5,
    -- Bat Aura (independent loop)
    batAura           = false,
    batInterval       = 0.1,
    -- ESP
    espEnabled        = false,
    -- Mutation filter
    targetMutations   = {}, -- {["Golden"]=true,...} empty=all
    -- Misc
    reducedMap        = false,
    antiAfk           = false,
}

-- Base teleport koordinat
local START_POS = Vector3.new(519.155, 70.576, -356.103)
local SAFE_POS  = Vector3.new(519.155, 70.576, -356.103)

-- ============================================================
-- HELPERS
-- ============================================================
local function root()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- ============================================================
-- EGG NAME LOOKUP BY RARITY (Source: IGN wiki + in-game confirmed)
-- Tool di Backpack = nama pet saja (tanpa " Egg")
-- ============================================================
-- ============================================================
-- RARITY ORDER (global)
-- ============================================================
local RARITY_ORDER = {
    Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,
    SuperRare=7,Exotic=8,Limited=9,Divine=10,Secret=11,Titan=12,
    Cosmic=13,Celestial=14,Transcendent=15,Prismatic=16,Rainbow=17,
    Eternal=18,Brainrot=19,Mythical=20,Exclusive=21,
}

-- ============================================================
-- PET RARITY MAP (nama tool di backpack = nama pet)
-- ============================================================
local PET_BY_RARITY = {
    ["Common"]    = {"Chicken","Dog","Frog","Duckling","Jerboa"},
    ["Uncommon"]  = {"Bird","Catfish","Fennec"},
    ["Rare"]      = {"Owl","Raccoon","Turtle","Camel","Toucan","Chimpanzee","Penguin","Lava Gecko","Parrotfish","Dodo","Tung Tung Sahur"},
    ["Epic"]      = {"Bear","Fox","Trulimero Trulicina","Swan","Tob Tobi Tob Tob","Crocodile","Walrus","Lava Frog","Swordfish","Centapede","Crane","Bananita Dolphinita"},
    ["Legendary"] = {"Brr Brr Patapim","Axolotl","Snake","Gorilla","Orangutini Ananassini","Polar Bear","Flaming Bull","Lava Iguana","Shark","Pterodactyl","Cosmic Gecko","Salamander","Crustacia","Spideron","Scorpio","Mecha Scorpio"},
    ["Mythic"]    = {"Scorpion","Sand Spider","Spider","Tiger","Sabertooth Tiger","Mammoth","Chillin Chilli","Orca","Ankylosaurus","Cosmic Gorilla","Red Panda","Bladehide","Belula Beluga","Froggo","Mecha Froggo"},
    ["Divine"]    = {"Unicorn","Kitsune","Dreadscale","Mecha Dreadscale"},
    ["Secret"]    = {"King Snake","Yeti","Cerberus","Kraken","Tralaledon","TRex","Cosmic Dragon","Cosmic Skeleton Boss","Stag","Mutant Shark","Bomboclat Crocolat","Crocodon","Mecha Crocodon"},
    ["Cosmic"]    = {"Leviathan","Royal Sphinx","King Mammoth","Whale Shark","Beluga Whale","Triceratops","Bronto","Mosasaurus","Koi","Snowy Owl","Mantaris","Rhinotaur","Mangolini Parrochini","Crawler","Mecha Crawler"},
    ["Eternal"]   = {"Ice Dragon","Phoenix","Lava Dragon","El Maja","Eternal Lunar Dragon","Oni Tiger","Gorilla King","Strawberry Elephant","Krakenoid","Mecha Krakenoid"},
}
local PET_RARITY_MAP = {}
for rarity, pets in pairs(PET_BY_RARITY) do
    for _, name in ipairs(pets) do
        PET_RARITY_MAP[name] = rarity
    end
end

-- ============================================================
-- EGG AREA NAMES (biome names di backpack)
-- ============================================================
local AREA_NAMES = {
    "Forest","Lake","Desert","Jungle","Snow","Volcano",
    "Abyss Ocean","Prehistoric","Cosmic","Cherry Blossom","Titan Temple"
}
local AREA_SET = {}
for _, a in ipairs(AREA_NAMES) do AREA_SET[a] = true end

-- Helper: ambil semua egg dari Backpack
-- Identifikasi via ItemType = AssetEgg/PetEgg, atau nama area
local function getEggsFromBackpack(minRarity)
    local result = {}
    local minNum = RARITY_ORDER[minRarity] or 0
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if not tool:IsA("Tool") then continue end
        local itemType = tool:GetAttribute("ItemType")
        -- Egg kalau ItemType = AssetEgg/PetEgg ATAU nama tool ada di AREA_SET
        local isEgg = (itemType == "AssetEgg" or itemType == "PetEgg") or AREA_SET[tool.Name]
        if not isEgg then continue end
        -- Rarity dari attribute atau 0 (unknown)
        local rarNum = 0
        local rarity = "Unknown"
        -- Coba baca rarity dari attribute
        local rarAttr = tool:GetAttribute("Rarity") or tool:GetAttribute("rarity")
        if rarAttr and RARITY_ORDER[rarAttr] then
            rarity = rarAttr
            rarNum = RARITY_ORDER[rarAttr]
        end
        if minNum <= 0 or rarNum >= minNum or rarNum == 0 then
            table.insert(result, {
                tool    = tool,
                name    = tool.Name,
                rarity  = rarity,
                rarNum  = rarNum,
            })
        end
    end
    return result
end

local function formatNumber(n)
    n = tonumber(n) or 0
    if n >= 1e9  then return string.format("%.1fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.1fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

-- ============================================================
-- ASSET HELPERS
-- ============================================================
local function getAssetData(record)
    if not record then return {} end
    -- Coba Assets.Directory dulu
    if Assets and record.AssetCategory then
        local ok, d = pcall(function()
            return (Assets.Directory or Assets)[record.AssetCategory] or {}
        end)
        if ok and d and next(d) then return d end
    end
    -- Fallback: bangun dari field record langsung (record punya Rarity, EarningRate, dll)
    return {
        EarningRate = record.EarningRate,
        ModelWeight = record.ModelWeight,
        DropWeight  = record.DropWeight,
        DisplayName = record.AssetCategory,
        Rarity      = record.Rarity,
        _id         = record.AssetCategory,
    }
end

local function getEarningRate(record)
    if record and record.EarningRate then return tonumber(record.EarningRate) or 0 end
    return tonumber(getAssetData(record).EarningRate) or 0
end

local function getModelWeight(record)
    if record and record.ModelWeight then return tonumber(record.ModelWeight) or 0 end
    return tonumber(getAssetData(record).ModelWeight) or 0
end

local function getRarityName(record)
    -- Cek record.Rarity langsung (paling reliable, gak butuh Assets)
    if record and record.Rarity then
        if type(record.Rarity) == "table" and record.Rarity._id then
            return record.Rarity._id
        end
        if type(record.Rarity) == "string" then return record.Rarity end
    end
    local d = getAssetData(record)
    return (d.Rarity and d.Rarity._id) or "Unknown"
end

local function getRarityColor(record)
    if record and record.Rarity and type(record.Rarity) == "table" then
        if typeof(record.Rarity.Color) == "Color3" then return record.Rarity.Color end
    end
    local d = getAssetData(record)
    if d.Rarity and typeof(d.Rarity.Color) == "Color3" then return d.Rarity.Color end
    if RarityModule and RarityModule.Rarities then
        local rn = getRarityName(record)
        local rm = RarityModule.Rarities[rn]
        if rm and typeof(rm.Color) == "Color3" then return rm.Color end
    end
    return Color3.fromRGB(255, 255, 255)
end

local function getRarityNumber(record)
    if record and record.Rarity and type(record.Rarity) == "table" then
        if type(record.Rarity.RarityNumber) == "number" then
            return record.Rarity.RarityNumber
        end
    end
    local d = getAssetData(record)
    if d.Rarity and d.Rarity.RarityNumber then return d.Rarity.RarityNumber end
    if RarityModule and RarityModule.Rarities then
        local rn = getRarityName(record)
        local rm = RarityModule.Rarities[rn]
        if rm then return rm.RarityNumber or 0 end
    end
    return 0
end

local function getRarityNumberByName(name)
    if name == "All" then return -1 end
    if RarityModule and RarityModule.Rarities and RarityModule.Rarities[name] then
        return RarityModule.Rarities[name].RarityNumber or 1
    end
    local map = {
        Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6,
        SuperRare=7, Exotic=8, Limited=9, Divine=10, Secret=11, Titan=12,
        Cosmic=13, Celestial=14, Transcendent=15, Prismatic=16, Rainbow=17,
        Eternal=18, Brainrot=19, Mythical=20, Exclusive=21
    }
    return map[name] or 1
end

-- ============================================================
-- RARITY FILTER
-- ============================================================
-- ============================================================
-- MUTATIONS (SAE confirmed: Silver 1.25x, Bloom 1.5x, Golden 2x, Rainbow 2.5x, Spirit Bloom 3x)
-- ============================================================
local MUTATIONS = {"Silver", "Bloom", "Golden", "Rainbow", "Spirit Bloom"}

local function isMutationAllowed(record)
    if not next(State.targetMutations) then return true end
    -- record.Mutations = {table} -- cek apakah ada mutasi yang match
    if not record or not record.Mutations then return false end
    if type(record.Mutations) ~= "table" then return false end
    for mutName, _ in pairs(State.targetMutations) do
        -- Cek di mutations table
        for k, v in pairs(record.Mutations) do
            local name = type(k) == "string" and k or tostring(v)
            if name:lower():find(mutName:lower()) then return true end
        end
    end
    return false
end

local function isRarityAllowed(record)
    local t = State.targetRarities
    if not t then return true end
    local hasAny = false
    if type(t) == "table" then
        for _ in pairs(t) do hasAny = true; break end
    end
    if not hasAny then return true end

    local name = getRarityName(record)
    if not name or name == "Unknown" then return true end -- unknown = skip filter

    -- Debug: print sekali per uid baru
    -- print("[RarityFilter] egg=" .. tostring(record.AssetCategory) .. " rarity=" .. name)

    -- VVind multi-dropdown return {[name]=true}
    if t[name] == true then return true end
    -- Case-insensitive fallback
    local nameLower = name:lower()
    for k, v in pairs(t) do
        if v == true and type(k) == "string" and k:lower() == nameLower then
            return true
        end
    end
    -- Array fallback
    for _, v in ipairs(t) do
        if type(v) == "string" and v:lower() == nameLower then return true end
    end
    return false
end

local function isValueAllowed(record)
    if State.minEarningRate > 0 and getEarningRate(record) < State.minEarningRate then
        return false
    end
    local w = getModelWeight(record)
    if State.minModelWeight > 0 and w < State.minModelWeight then return false end
    if w > State.maxModelWeight then return false end
    return true
end

-- ============================================================
-- NO KNOCKBACK -- disconnect RE/RigSync/Refresh (Lutosys/opensrc)
-- ============================================================
local function applyNoKnockback()
    if type(getconnections) ~= "function" then
        warn("[NoKnockback] getconnections not available")
        return
    end
    local net = ReplicatedStorage:FindFirstChild("Packages")
        and ReplicatedStorage.Packages:FindFirstChild("Networking")
    if not net then warn("[NoKnockback] Networking not found"); return end
    local remote = net:FindFirstChild("RE/RigSync/Refresh")
    if not remote then warn("[NoKnockback] RE/RigSync/Refresh not found"); return end
    local ok, conns = pcall(function() return getconnections(remote.OnClientEvent) end)
    if not ok or not conns then warn("[NoKnockback] getconnections failed"); return end
    local patched = 0
    for _, conn in next, conns do
        pcall(function() conn:Disconnect() end)
        patched += 1
    end
    print("[NoKnockback] patched", patched, "connections")
end

-- ============================================================
-- AUTO UPGRADE BASE -- RE/Homestead/AskBaseTierRaise (Lutosys/opensrc)
-- ============================================================
local function upgradeBase()
    local net = ReplicatedStorage:FindFirstChild("Packages")
        and ReplicatedStorage.Packages:FindFirstChild("Networking")
    if not net then warn("[UpgradeBase] Networking not found"); return end
    local remote = net:FindFirstChild("RE/Homestead/AskBaseTierRaise")
    if not remote then warn("[UpgradeBase] remote not found"); return end
    pcall(function() remote:FireServer() end)
    print("[UpgradeBase] fired")
end

-- Auto upgrade treadmill
local function upgradeTreadmill(id)
    local net = ReplicatedStorage:FindFirstChild("Packages")
        and ReplicatedStorage.Packages:FindFirstChild("Networking")
    if not net then return end
    local remote = net:FindFirstChild("RF/Treadmill/AskTierRaise")
    if not remote then return end
    pcall(function() remote:InvokeServer(id) end)
    print("[UpgradeTreadmill] fired id:", tostring(id))
end

-- ============================================================
-- HUMANOID BYPASS
-- ============================================================
local _camConn = nil
local _speedConn = nil

local function doHumanoidBypass()
    local char = LocalPlayer.Character
    if not char then char = LocalPlayer.CharacterAdded:Wait() end

    local origHum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    if not origHum or not rootPart then return end

    pcall(function()
        local clone = origHum:Clone()
        clone.WalkSpeed   = origHum.WalkSpeed
        clone.JumpPower   = origHum.JumpPower
        clone.MaxHealth   = origHum.MaxHealth
        clone.Health      = origHum.Health
        clone.AutoRotate  = origHum.AutoRotate
        clone.DisplayName = origHum.DisplayName
        clone.Parent      = char
        task.wait(0.05)
        origHum:Destroy()

        -- Teleport ke StartPosition
        if rootPart and rootPart.Parent then
            rootPart.CFrame                  = CFrame.new(START_POS)
            rootPart.AssemblyLinearVelocity  = Vector3.new(0, 35, 0)
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end

        task.wait(0.05)
        clone.PlatformStand = false
        clone.Sit           = false
        pcall(function() clone:ChangeState(Enum.HumanoidStateType.Running) end)
    end)

    -- Camera lock via Heartbeat
    if _camConn then _camConn:Disconnect() end
    _camConn = RunService.Heartbeat:Connect(function()
        local c = LocalPlayer.Character
        if not c then return end
        local h2 = c:FindFirstChildOfClass("Humanoid")
        if h2 then
            pcall(function() Workspace.CurrentCamera.CameraSubject = h2 end)
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function()
    if State.running then
        task.wait(0.3)
        doHumanoidBypass()
    end
end)

-- ============================================================
-- FLOAT SYSTEM -- client-side visual only (RenderStepped)
-- Direct offset tanpa lerp biar gak bouncing
-- ============================================================
local _floatConn = nil
local function updateFloat()
    if _floatConn then _floatConn:Disconnect(); _floatConn = nil end
    if not State.floatEnabled then return end
    _floatConn = RunService.RenderStepped:Connect(function()
        if not State.floatEnabled then return end
        local c = LocalPlayer.Character
        if not c then return end
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local rot = hrp.CFrame - hrp.CFrame.Position
        hrp.CFrame = CFrame.new(
            hrp.Position.X,
            hrp.Position.Y + State.floatHeight,
            hrp.Position.Z
        ) * rot
    end)
end

-- ============================================================
-- ANIMATION TOGGLE -- Heartbeat loop biar gak re-apply
-- ============================================================
local _animTracks = {}
local _animConn   = nil

local function stopAllAnims()
    local c = LocalPlayer.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() track:Stop(0) end)
        end
    end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        pcall(function() track:Stop(0) end)
    end
    -- Reset semua Motor6D ke identity = pose R6 tegak
    for _, obj in ipairs(c:GetDescendants()) do
        if obj:IsA("Motor6D") then
            pcall(function() obj.Transform = CFrame.identity end)
        end
    end
end

local function updateAnim()
    if _animConn then _animConn:Disconnect(); _animConn = nil end
    if State.animEnabled then return end
    -- Stop sekali dulu
    stopAllAnims()
    -- Loop terus stop animasi baru yang di-apply game
    _animConn = RunService.Heartbeat:Connect(function()
        if State.animEnabled then
            if _animConn then _animConn:Disconnect(); _animConn = nil end
            return
        end
        stopAllAnims()
    end)
end
-- ============================================================
local function walkTo(goal, timeout, isReturning, checkFn)
    local h2 = hum()
    local r  = root()
    if not h2 or not r then return false end
    if typeof(goal) == "Instance" then goal = goal.Position end

    timeout = timeout or 20
    local speed      = isReturning and (State.antiGuard and 1000 or State.speed) or State.speed
    local targetDist = 4  -- flat, biar karakter beneran sampai dekat egg

    -- Kalau returning ke base, langsung snap via CFrame -- lebih reliable di speed tinggi
    if isReturning then
        r = root(); h2 = hum()
        if r and h2 then
            pcall(function() r.CFrame = CFrame.new(START_POS) end)
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            h2.WalkSpeed = 16
        end
        return true
    end

    if (r.Position - goal).Magnitude <= targetDist then
        h2.WalkSpeed = 16; return true
    end

    h2.WalkSpeed = speed
    h2:MoveTo(goal)

    local t0       = workspace.DistributedGameTime
    local lastPos  = r.Position
    local stuckT   = t0

    local shouldContinue = checkFn or function() return State.running end

    while workspace.DistributedGameTime - t0 < timeout do
        if not shouldContinue() then break end
        task.wait(0.02)
        r  = root(); h2 = hum()
        if not r or not h2 then break end

        local dist = (r.Position - goal).Magnitude

        if dist <= targetDist then
            h2.WalkSpeed = 0
            h2:Move(Vector3.zero, false)
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            pcall(function()
                r.CFrame = CFrame.new(goal) * (r.CFrame - r.CFrame.Position)
            end)
            break
        end

        -- Brake zone kecil biar gak mulai rem terlalu jauh
        local brake = math.min(speed * 0.05, 12)
        if dist <= brake then
            h2.WalkSpeed = math.max(16, speed * (dist/brake)^1.5)
        else
            h2.WalkSpeed = speed
        end
        h2:MoveTo(goal)

        local now = workspace.DistributedGameTime
        if now - stuckT >= 2 then
            if (r.Position - lastPos).Magnitude < 0.5 then
                h2:MoveTo(goal)
                h2.Jump = true
            end
            lastPos = r.Position
            stuckT  = now
        end
    end

    h2 = hum()
    if h2 then h2.WalkSpeed = 16 end
    return true
end

-- ============================================================
-- EGG FINDER
-- ============================================================
local function findBestEgg()
    if not EggState then return nil, nil end
    local ok, fieldEggs = pcall(function() return EggState.ReadFieldEggs() end)
    if not ok or not fieldEggs or not fieldEggs.Records then return nil, nil end

    local r = root()
    if not r then return nil, nil end

    -- Coba locked record dulu
    if State.lockedRecord then
        for _, rec in ipairs(fieldEggs.Records) do
            if rec.Uid == State.lockedRecord.Uid then
                if isRarityAllowed(rec) and isValueAllowed(rec) then
                    local model = Workspace:FindFirstChild("AreaEggSlotsClient", true)
                        and Workspace.AreaEggSlotsClient:FindFirstChild(rec.Uid)
                        or Workspace:FindFirstChild(rec.Uid, true)
                    if model then return rec, model end
                end
                break
            end
        end
        State.lockedRecord = nil
    end

    local bestRec, bestModel, bestDist = nil, nil, math.huge

    for _, rec in ipairs(fieldEggs.Records) do
        if not isRarityAllowed(rec) then continue end
        if not isValueAllowed(rec)  then continue end
        if not isMutationAllowed(rec) then continue end

        local model = Workspace:FindFirstChild("AreaEggSlotsClient", true)
            and Workspace.AreaEggSlotsClient:FindFirstChild(rec.Uid)
            or Workspace:FindFirstChild(rec.Uid, true)

        if model then
            local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            if part then
                local d = (part.Position - r.Position).Magnitude
                if d < bestDist then
                    bestDist  = d
                    bestRec   = rec
                    bestModel = model
                end
            end
        end
    end

    if bestRec then State.lockedRecord = bestRec end
    return bestRec, bestModel
end

-- ============================================================
-- AUTO PLACE
-- ============================================================
-- ============================================================
-- AUTO PLACE -- independent loop
-- ============================================================
local function runAutoPlace()
    if not PlotState then loadModules() end
    if not PlotState then return end
    pcall(function()
        local myPlot = PlotState.ResolvePlot()
        if not myPlot or not myPlot.CenterPoint or not myPlot.PetArea then
            warn("[AutoPlace] ResolvePlot gagal")
            return
        end

        -- Walk ke plot dulu (independent dari State.running)
        local plotPos = myPlot.CenterPoint.Position
        local r = root()
        if r and (r.Position - plotPos).Magnitude > 5 then
            walkTo(plotPos, 15, false, function() return State.placeEnabled end)
        end
        task.wait(0.3)

        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        local placeRemote = net and net:FindFirstChild("RF/EggWorld/AskPlaceEgg")
        local wearRemote  = net and net:FindFirstChild("RF/EggWorld/AskWearTool")
        if not placeRemote then warn("[AutoPlace] AskPlaceEgg not found"); return end

        -- Scan semua slot di PetArea -- random offset biar egg tersebar
        local petArea = myPlot.PetArea
        local centerCF = myPlot.CenterPoint.CFrame
        local petSize = petArea.Size
        -- Base localPos dari PetArea
        local basePetPos = myPlot.PetArea.Position

        -- Fungsi buat generate localCFrame dengan random offset di dalam PetArea bounds
        local slotIndex = 0
        local function nextLocalCFrame()
            slotIndex += 1
            -- Grid offset: spread egg di seluruh area
            local halfX = (petSize.X * 0.4)
            local halfZ = (petSize.Z * 0.4)
            local offsetX = (math.random() * 2 - 1) * halfX
            local offsetZ = (math.random() * 2 - 1) * halfZ
            local worldPos = basePetPos + Vector3.new(offsetX, 0, offsetZ)
            local localPos = centerCF:PointToObjectSpace(worldPos)
            return CFrame.new(localPos) * CFrame.fromMatrix(
                Vector3.zero,
                Vector3.new(0,0,-1),
                Vector3.new(0,1,0),
                Vector3.new(1,0,0)
            )
        end

        -- Sync dulu dari server biar ReadOwnerEggs up-to-date
        if not EggState then
            print("[AutoPlace] EggState nil"); return
        end

        -- Sync -- lanjut meski gagal
        local syncOk, syncErr = pcall(function() EggState.SyncOwnedEggs() end)
        if not syncOk then
            warn("[AutoPlace] SyncOwnedEggs error:", tostring(syncErr))
        end
        task.wait(0.3)

        local ok, owned = pcall(function()
            return EggState.ReadOwnerEggs(LocalPlayer.UserId)
        end)
        if not ok or type(owned) ~= "table" or not next(owned) then
            print("[AutoPlace] owned egg kosong -- ok:", ok, "type:", type(owned))
            return
        end

        print("[AutoPlace] owned eggs count:", (function()
            local c = 0; for _ in pairs(owned) do c += 1 end; return c
        end)())

        local minRarNum = RARITY_ORDER[State.placeMinRarity] or 0
        local placed = 0
        local skippedPlacement = 0
        local MAX_PER_RUN = 10

        for k, rec in pairs(owned) do
            if placed >= MAX_PER_RUN then break end
            local uid
            if type(k) == "string" then
                uid = k
            elseif type(rec) == "table" and rec.Uid then
                uid = rec.Uid
            end
            if not uid or type(k) ~= "string" then continue end

            -- Skip yang sudah di-place
            if rec.Placement ~= nil then
                skippedPlacement += 1
                continue
            end

            -- Filter rarity
            if minRarNum > 0 then
                local rarNum = 0
                if rec.Rarity and type(rec.Rarity) == "table" then
                    rarNum = rec.Rarity.RarityNumber or 0
                elseif rec.RarityNumber and type(rec.RarityNumber) == "number" then
                    rarNum = rec.RarityNumber
                end
                -- Debug rarity sekali
                if rarNum == 0 then
                    -- print("[AutoPlace] rarity unknown for uid:", uid:sub(1,8), "rec.Rarity:", type(rec.Rarity))
                end
                if rarNum > 0 and rarNum < minRarNum then continue end
            end

            -- 1. Equip egg -- sama kayak auto place pet (pindah tool ke Character)
            -- Cari tool di backpack yang match uid atau ItemType=AssetEgg
            local eggTool = nil
            for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
                if t:IsA("Tool") then
                    local itype = t:GetAttribute("ItemType")
                    if itype == "AssetEgg" or itype == "PetEgg" then
                        eggTool = t
                        break
                    end
                end
            end
            if eggTool then
                pcall(function() eggTool.Parent = LocalPlayer.Character end)
                task.wait(0.2)
            elseif wearRemote then
                -- Fallback remote
                pcall(function() wearRemote:InvokeServer(uid) end)
                task.wait(0.25)
            end

            -- 2. AskPlaceEgg dengan random slot offset
            local localCFrame = nextLocalCFrame()
            local ok3, res = pcall(function()
                return placeRemote:InvokeServer({Uid = uid, LocalCFrame = localCFrame})
            end)
            warn(">>>PLACE<<< ok="..tostring(ok3).." res="..tostring(res).." uid="..uid:sub(1,8))
            if ok3 and res == true then placed += 1 end
            task.wait(0.1)
        end
        print(string.format("[AutoPlace] DONE placed=%d skipped=%d / total=%d",
            placed, skippedPlacement, (function()
                local c=0; for _ in pairs(owned) do c+=1 end; return c
            end)()))
    end)
end

-- Interval-based trigger
task.spawn(function()
    while true do
        task.wait(State.placeInterval or 5)
        if not State.placeEnabled then continue end
        if State._placing then continue end
        if not EggState then loadModules() end
        State._placing = true
        local wasRunning = State.running
        if wasRunning then State.running = false; State.busy = false end
        pcall(runAutoPlace)
        if wasRunning then
            State.running = true
            task.spawn(function()
                while State.running do farmCycle(); task.wait(0.05) end
            end)
        end
        State._placing = false
    end
end)

-- ============================================================
-- ANTI-STUCK TREADMILL
-- ============================================================
task.spawn(function()
    local lastGoalDist = math.huge
    local stuckTimer   = 0
    while true do
        task.wait(0.5)
        if not State.running and not State.busy then
            stuckTimer = 0; lastGoalDist = math.huge; continue
        end
        local char = LocalPlayer.Character
        local r    = char and char:FindFirstChild("HumanoidRootPart")
        local h    = char and char:FindFirstChildOfClass("Humanoid")
        if not r or not h then stuckTimer = 0; continue end

        -- Cek apakah karakter di-push treadmill:
        -- velocity horizontal tinggi tapi bukan karena kita yang gerak
        local vel   = r.AssemblyLinearVelocity
        local hVel  = Vector3.new(vel.X, 0, vel.Z).Magnitude
        local speed = h.WalkSpeed

        -- Treadmill push: velocity horizontal jauh melebihi walkspeed kita
        -- atau karakter heading tidak ke goal (treadmill berlawanan arah)
        local isTreadmillPush = hVel > (speed * 1.5) and hVel > 20

        if isTreadmillPush then
            stuckTimer += 1
            if stuckTimer >= 2 then
                -- Force keluar: velocity berlawanan + ke atas + jump
                pcall(function()
                    local opposite = Vector3.new(-vel.X, 60, -vel.Z).Unit * speed * 3
                    r.AssemblyLinearVelocity = opposite
                end)
                h.PlatformStand = false
                h.Sit           = false
                h.Jump          = true
                pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end)
                -- Re-issue MoveTo ke tujuan terakhir
                pcall(function() h:MoveTo(r.Position + Vector3.new(-vel.X, 0, -vel.Z).Unit * 10) end)
                stuckTimer = 0
                print("[AntiStuck] treadmill escape triggered, hVel=" .. math.floor(hVel))
            end
        else
            stuckTimer = 0
        end
    end
end)

-- ============================================================
-- CYCLE PANEL -- countdown 5 menit + egg field rarity
-- ============================================================
local _cycleGui = Instance.new("ScreenGui")
_cycleGui.Name = "SAE_CyclePanel"
_cycleGui.ResetOnSpawn = false
_cycleGui.IgnoreGuiInset = true
_cycleGui.DisplayOrder = 99997
_cycleGui.Enabled = false
_cycleGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local _cycleFrame = Instance.new("Frame")
_cycleFrame.Size = UDim2.fromOffset(180, 200)
_cycleFrame.Position = UDim2.new(1, -190, 0, 50)
_cycleFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
_cycleFrame.BackgroundTransparency = 0.1
_cycleFrame.BorderSizePixel = 0
_cycleFrame.Parent = _cycleGui
Instance.new("UICorner", _cycleFrame).CornerRadius = UDim.new(0, 8)

local _cycleTitle = Instance.new("TextLabel")
_cycleTitle.Size = UDim2.new(1, 0, 0, 24)
_cycleTitle.Position = UDim2.new(0,0,0,0)
_cycleTitle.BackgroundTransparency = 1
_cycleTitle.Text = "CYCLE TIMER"
_cycleTitle.TextColor3 = Color3.fromRGB(180,180,200)
_cycleTitle.TextSize = 11
_cycleTitle.Font = Enum.Font.GothamBold
_cycleTitle.Parent = _cycleFrame

local _cycleTimer = Instance.new("TextLabel")
_cycleTimer.Size = UDim2.new(1, 0, 0, 30)
_cycleTimer.Position = UDim2.new(0,0,0,24)
_cycleTimer.BackgroundTransparency = 1
_cycleTimer.Text = "5:00"
_cycleTimer.TextColor3 = Color3.fromRGB(100, 220, 100)
_cycleTimer.TextSize = 22
_cycleTimer.Font = Enum.Font.GothamBold
_cycleTimer.Parent = _cycleFrame

local _cycleList = Instance.new("Frame")
_cycleList.Size = UDim2.new(1, -8, 0, 140)
_cycleList.Position = UDim2.new(0,4,0,58)
_cycleList.BackgroundTransparency = 1
_cycleList.Parent = _cycleFrame
local _cycleListLayout = Instance.new("UIListLayout")
_cycleListLayout.SortOrder = Enum.SortOrder.LayoutOrder
_cycleListLayout.Padding = UDim.new(0,2)
_cycleListLayout.Parent = _cycleList

local RARITY_COLORS = {
    Common="#b0b0b0", Uncommon="#5abf5a", Rare="#4a90d9", Epic="#a64fd6",
    Legendary="#f5a623", Mythic="#e74c3c", Divine="#00e5ff", Otherworldly="#ff6ec7",
    Celestial="#ffe066", Transcendent="#ff9f43", Void="#8e44ad",
    Eternal="#1abc9c", Cosmic="#e056fd", Prismatic="#fd79a8",
    Spectral="#74b9ff", Ethereal="#a29bfe", Astral="#55efc4",
    Radiant="#ffeaa7", Sovereign="#fdcb6e", Omnipotent="#e17055", Exclusive="#ff7675",
}
local function rarityColor(name)
    local hex = RARITY_COLORS[name] or "#ffffff"
    local r,g,b = hex:match("#(%x%x)(%x%x)(%x%x)")
    if r then return Color3.fromRGB(tonumber(r,16),tonumber(g,16),tonumber(b,16)) end
    return Color3.new(1,1,1)
end

local _cycleStart = tick()
local CYCLE_DURATION = 300 -- 5 menit

task.spawn(function()
    while true do
        task.wait(0.5)
        if not _cycleGui.Enabled then continue end

        -- Update timer
        local elapsed = (tick() - _cycleStart) % CYCLE_DURATION
        local remaining = CYCLE_DURATION - elapsed
        local mins = math.floor(remaining / 60)
        local secs = math.floor(remaining % 60)
        _cycleTimer.Text = string.format("%d:%02d", mins, secs)
        -- Warna merah kalau < 30 detik (blackout segera)
        _cycleTimer.TextColor3 = remaining < 30
            and Color3.fromRGB(220, 80, 80)
            or Color3.fromRGB(100, 220, 100)

        -- Update egg list dari EggState
        for _, c in ipairs(_cycleList:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        if EggState and EggState.ReadFieldEggs then
            local ok, fieldData = pcall(function() return EggState.ReadFieldEggs() end)
            if ok and fieldData and fieldData.Records then
                local shown = 0
                for _, rec in ipairs(fieldData.Records) do
                    if shown >= 8 then break end
                    local rarName = getRarityName(rec)
                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.new(1, 0, 0, 16)
                    lbl.BackgroundTransparency = 1
                    lbl.Text = (rec.AssetCategory or "?").." ["..rarName.."]"
                    lbl.TextColor3 = rarityColor(rarName)
                    lbl.TextSize = 10
                    lbl.Font = Enum.Font.Gotham
                    lbl.TextXAlignment = Enum.TextXAlignment.Left
                    lbl.LayoutOrder = shown
                    lbl.Parent = _cycleList
                    shown += 1
                end
            end
        end
    end
end)
local function runAutoPlacePet()
    if not PlotState then loadModules() end
    if not PlotState then return end
    pcall(function()
        local myPlot = PlotState.ResolvePlot()
        if not myPlot or not myPlot.CenterPoint or not myPlot.PetArea then return end

        -- Walk ke plot
        local plotPos = myPlot.CenterPoint.Position
        local r = root()
        if r and (r.Position - plotPos).Magnitude > 5 then
            walkTo(plotPos, 15, false, function() return State.placePetEnabled end)
        end
        task.wait(0.3)

        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        local placeRemote = net and net:FindFirstChild("RF/EggWorld/AskPlaceEgg")
        if not placeRemote then return end

        local localCFrame = myPlot.CenterPoint.CFrame:ToObjectSpace(myPlot.PetArea.CFrame)

        -- Scan backpack buat pet (ItemType = Asset atau Phone)
        local placed = 0
        for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if not tool:IsA("Tool") then continue end
            local itemType = tool:GetAttribute("ItemType")
            if itemType ~= "Asset" and itemType ~= "Phone" then continue end

            -- Equip pet
            pcall(function() tool.Parent = LocalPlayer.Character end)
            task.wait(0.15)

            local uid = tool:GetAttribute("Uid") or tool:GetAttribute("uid") or tool.Name
            local ok3, res = pcall(function()
                return placeRemote:InvokeServer({Uid = uid, LocalCFrame = localCFrame})
            end)
            if ok3 and res then
                placed += 1
                print("[AutoPlacePet] placed:", tool.Name)
            else
                pcall(function() tool.Parent = LocalPlayer.Backpack end)
            end
            task.wait(0.1)
        end
        print(string.format("[AutoPlacePet] total placed=%d", placed))
    end)
end

-- Interval-based trigger
task.spawn(function()
    while true do
        task.wait(State.placePetInterval or 5)
        if not State.placePetEnabled then continue end
        if State._placing then continue end
        State._placing = true
        local wasRunning = State.running
        if wasRunning then State.running = false; State.busy = false end
        pcall(runAutoPlacePet)
        if wasRunning then
            State.running = true
            task.spawn(function()
                while State.running do farmCycle(); task.wait(0.05) end
            end)
        end
        State._placing = false
    end
end)

-- Best pet: timer-based saja (jarang perlu, biar gak gangguin farm)
task.spawn(function()
    while true do
        task.wait(State.placeBestPetInterval or 10)
        if State.placeBestPetEnabled then
            if not PlotState then loadModules() end
            pcall(runAutoPlaceBestPet)
        end
    end
end)

-- ============================================================
-- AUTO HATCH -- independent loop
-- ============================================================
local function runAutoHatch()
    if not EggState then return end
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        if not net then return end
        local AskHatch       = net:FindFirstChild("RF/EggWorld/AskHatch")
        local AskFinishHatch = net:FindFirstChild("RF/EggWorld/AskFinishHatch")
        if not AskHatch and not AskFinishHatch then return end

        -- ReadOwnerEggs(userId) -> {[uid]=record}
        local owned = EggState.ReadOwnerEggs(LocalPlayer.UserId)
        if type(owned) ~= "table" then return end

        local hatched = 0
        for uid, rec in pairs(owned) do
            if type(uid) ~= "string" then continue end
            -- Hatch ALL egg (placed maupun belum)
            if AskHatch then
                pcall(function() AskHatch:InvokeServer(uid) end)
                task.wait(0.05)
            end
            if AskFinishHatch then
                local ok, r1, r2, petUid = pcall(function()
                    return AskFinishHatch:InvokeServer(uid)
                end)
                if ok and r1 == true then
                    hatched += 1
                    print("[AutoHatch] hatched uid:", uid:sub(1,8), "pet:", tostring(petUid or r2))
                end
                task.wait(0.05)
            end
        end
        if hatched > 0 then print("[AutoHatch] total hatched:", hatched) end
    end)
end

task.spawn(function()
    while true do
        task.wait(State.hatchInterval)
        if State.hatchEnabled then
            if not EggState then loadModules() end
            pcall(runAutoHatch)
        end
    end
end)

-- ============================================================
-- AUTO SELL EGG -- ReadOwnerEggs + SellPet:FireServer({uid})
-- ============================================================
local function runAutoSellEgg()
    if not State.sellEggEnabled then return end
    if not EggState then loadModules() end
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        if not net then return end
        local sellRemote = net:FindFirstChild("RE/PetSatchel/SellPet")
        local wearRemote = net:FindFirstChild("RF/EggWorld/AskWearTool")
        if not sellRemote then warn("[SellEgg] SellPet not found"); return end

        local owned = EggState.ReadOwnerEggs(LocalPlayer.UserId)
        if type(owned) ~= "table" then return end

        local maxNum = RARITY_ORDER[State.sellEggMaxRarity] or 0
        local sold = 0

        for uid, rec in pairs(owned) do
            if type(uid) ~= "string" then continue end
            local rarName = getRarityName(rec)
            local rarNum = RARITY_ORDER[rarName] or 0
            -- unknown rarity = skip
            if rarNum == 0 then continue end
            -- filter multi-select: kalau ada pilihan, cek apakah masuk
            if next(State.sellEggMaxRarities) then
                if not State.sellEggMaxRarities[rarName] then continue end
            end
            -- Equip dulu via AskWearTool
            if wearRemote then
                pcall(function() wearRemote:InvokeServer(uid) end)
                task.wait(0.2)
            end
            pcall(function() sellRemote:FireServer({uid}) end)
            sold += 1
            task.wait(0.1)
        end
        if sold > 0 then print("[SellEgg] sold:", sold) end
    end)
end

task.spawn(function()
    while true do
        task.wait(State.sellEggInterval or 10)
        if not State.sellEggEnabled then continue end
        if not EggState then loadModules() end
        pcall(runAutoSellEgg)
    end
end)

-- ============================================================
-- AUTO PLACE BEST PET -- sort by rarity tertinggi dulu
-- ============================================================
local function runAutoPlaceBestPet()
    if not PlotState then loadModules() end
    if not PlotState then return end
    pcall(function()
        local myPlot = PlotState.ResolvePlot()
        if not myPlot or not myPlot.CenterPoint or not myPlot.PetArea then return end

        local plotPos = myPlot.CenterPoint.Position
        local r = root()
        if r and (r.Position - plotPos).Magnitude > 5 then
            walkTo(plotPos, 15, false, function() return State.placeBestPetEnabled end)
        end
        task.wait(0.3)

        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        local placeRemote = net and net:FindFirstChild("RF/EggWorld/AskPlaceEgg")
        if not placeRemote then return end

        local centerCF = myPlot.CenterPoint.CFrame
        local basePetPos = myPlot.PetArea.Position
        local petSize = myPlot.PetArea.Size

        -- Kumpulkan semua pet di backpack + sort by rarity
        local pets = {}
        for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if not tool:IsA("Tool") then continue end
            local itype = tool:GetAttribute("ItemType")
            if itype ~= "Asset" and itype ~= "Phone" then continue end
            local rarity = PET_RARITY_MAP[tool.Name]
            local rarNum = rarity and (RARITY_ORDER[rarity] or 0) or 0
            table.insert(pets, {tool=tool, name=tool.Name, rarNum=rarNum})
        end

        -- Sort descending (best first)
        table.sort(pets, function(a, b) return a.rarNum > b.rarNum end)

        local placed = 0
        for _, pet in ipairs(pets) do
            if placed >= 10 then break end
            -- Random offset
            local ox = (math.random()*2-1) * petSize.X * 0.4
            local oz = (math.random()*2-1) * petSize.Z * 0.4
            local worldPos = basePetPos + Vector3.new(ox, 0, oz)
            local localPos = centerCF:PointToObjectSpace(worldPos)
            local localCFrame = CFrame.new(localPos) * CFrame.fromMatrix(
                Vector3.zero, Vector3.new(0,0,-1), Vector3.new(0,1,0), Vector3.new(1,0,0)
            )

            pcall(function() pet.tool.Parent = LocalPlayer.Character end)
            task.wait(0.15)

            local uid = pet.tool:GetAttribute("Uid") or pet.tool:GetAttribute("uid") or pet.name
            local ok3, res = pcall(function()
                return placeRemote:InvokeServer({Uid=uid, LocalCFrame=localCFrame})
            end)
            if ok3 and res then
                placed += 1
                print("[PlaceBestPet] placed:", pet.name, "rarity:", tostring(PET_RARITY_MAP[pet.name]))
            end
            task.wait(0.1)
        end
        print("[PlaceBestPet] total placed:", placed)
    end)
end

-- ============================================================
-- COLLECT MONEY -- RF/AwayEarnings/AskCollect (confirmed rspy)
-- ============================================================
local function runCollectMoney()
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        if not net then return end
        local remote = net:FindFirstChild("RF/AwayEarnings/AskCollect")
        if not remote then warn("[CollectMoney] remote not found"); return end
        local ok, r1, r2, data = pcall(function()
            return remote:InvokeServer({Kind = "Claim"})
        end)
        if ok and r1 == true then
            local amount = data and data.AwardedAmount or 0
            print(string.format("[CollectMoney] claimed: $%.0f", amount))
        else
            warn("[CollectMoney] failed:", tostring(r1))
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(State.collectInterval or 60)
        if State.collectEnabled then
            pcall(runCollectMoney)
        end
    end
end)

-- ============================================================
-- ============================================================
-- AUTO FAVORITE PET -- event-based, filter rarity/mutasi/weight/value
-- ============================================================

-- Helper: cek apakah tool layak di-favorite
local function shouldFavorite(tool)
    if not tool:IsA("Tool") then return false end
    local itype = tool:GetAttribute("ItemType")
    local isPet = itype == "Asset" or itype == "Phone"
    local isEgg = itype == "AssetEgg" or itype == "PetEgg" or AREA_SET[tool.Name]
    if not isPet and not isEgg then return false end

    -- Cek toggle: pet atau egg harus diaktifkan
    if isPet and not State.favPetEnabled then return false end
    if isEgg and not State.favEggEnabled then return false end

    -- Filter rarity multi-select
    if next(State.favMinRarities) then
        local rarity
        if isPet then
            rarity = PET_RARITY_MAP[tool.Name]
        else
            -- Egg: baca dari attribute
            rarity = tool:GetAttribute("Rarity") or tool:GetAttribute("rarity")
        end
        if not rarity or not State.favMinRarities[rarity] then return false end
    end

    -- Filter mutasi
    if State.favMutations and next(State.favMutations) then
        local mut = tool:GetAttribute("Mutations")
        local hasMut = false
        if type(mut) == "string" then
            for m, _ in pairs(State.favMutations) do
                if mut:lower():find(m:lower()) then hasMut = true; break end
            end
        elseif type(mut) == "table" then
            for _, mv in ipairs(mut) do
                for m, _ in pairs(State.favMutations) do
                    if tostring(mv):lower():find(m:lower()) then hasMut = true; break end
                end
            end
        end
        if not hasMut then return false end
    end

    -- Filter weight
    local weight = tool:GetAttribute("ModelWeight") or tool:GetAttribute("Weight") or 0
    if State.favMinWeight and State.favMinWeight > 0 and weight < State.favMinWeight then return false end
    if State.favMaxWeight and State.favMaxWeight > 0 and weight > State.favMaxWeight then return false end

    -- Filter value
    local value = tool:GetAttribute("EarningRate") or tool:GetAttribute("Value") or 0
    if State.favMinValue and State.favMinValue > 0 and value < State.favMinValue then return false end

    return true
end

local function favoriteTool(tool)
    local uid = tool:GetAttribute("Uid") or tool:GetAttribute("uid")
    if not uid then return false end
    local net = ReplicatedStorage:FindFirstChild("Packages")
        and ReplicatedStorage.Packages:FindFirstChild("Networking")
    if not net then return false end
    local remote     = net:FindFirstChild("RE/PetSatchel/WriteFavourite")
    local wearRemote = net:FindFirstChild("RF/EggWorld/AskWearTool")
    if not remote then return false end
    -- Equip via AskWearTool (sama seperti sell)
    if wearRemote then pcall(function() wearRemote:InvokeServer(uid) end) end
    pcall(function() remote:FireServer(uid, true) end)
    return true
end

local function runAutoFavorite()
    if not State.favPetEnabled and not State.favEggEnabled then return end
    pcall(function()
        local count = 0
        for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if shouldFavorite(tool) then
                if favoriteTool(tool) then
                    count += 1
                    task.wait(0.05)
                end
            end
        end
        if count > 0 then print("[AutoFavorite] favorited:", count) end
    end)
end

-- Event-based: langsung cek saat tool masuk backpack
LocalPlayer.Backpack.ChildAdded:Connect(function(tool)
    if not State.favPetEnabled and not State.favEggEnabled then return end
    -- tunggu attributes sync (minimal)
    task.wait(0.1)
    if shouldFavorite(tool) then
        if favoriteTool(tool) then
            print("[AutoFavorite] fav new:", tool.Name)
        end
    end
end)

-- ============================================================
-- AUTO SELL -- AskWearTool + getnilinstances + ToolTrigger
-- Confirmed dari rspy SAE KONTOL.txt
-- ============================================================
local function getToolFromNil(name)
    if type(getnilinstances) ~= "function" then return nil end
    local ok, result = pcall(function()
        for _, obj in ipairs(getnilinstances()) do
            if obj:IsA("Tool") and obj.Name == name then
                return obj
            end
        end
        return nil
    end)
    return ok and result or nil
end

local function runAutoSell()
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        if not net then return end

        -- Sell All pets
        if State.sellAll then
            local remote = net:FindFirstChild("RE/PetSatchel/SellEveryPet")
            if remote then
                remote:FireServer()
                print("[AutoSell] SellEveryPet fired")
            end
            return
        end

        if not EggState then loadModules() end
        if not EggState then warn("[AutoSell] EggState nil"); return end

        local wearRemote    = net:FindFirstChild("RF/EggWorld/AskWearTool")
        local triggerRemote = net:FindFirstChild("RE/ToolTrigger/Trigger")
        if not wearRemote or not triggerRemote then
            warn("[AutoSell] remote missing -- wearTool:" .. tostring(wearRemote ~= nil) ..
                 " trigger:" .. tostring(triggerRemote ~= nil))
            return
        end

        local maxNum = getRarityNumberByName(State.sellMaxRarity)
        local ok, owned = pcall(function() return EggState.ReadOwnerEggs(LocalPlayer.UserId) end)
        if not ok or type(owned) ~= "table" or not next(owned) then
            print("[AutoSell] owned egg kosong")
            return
        end

        local sold, skipped = 0, 0
        for _, rec in ipairs(owned) do
            if not rec.Uid then continue end
            local rarNum = getRarityNumber(rec)
            if rarNum > maxNum then skipped += 1; continue end

            -- 1. Equip egg via AskWearTool
            local ok2, toolName = pcall(function()
                return wearRemote:InvokeServer(rec.Uid)
            end)

            task.wait(0.2)

            -- 2. Cari tool di nil instances (egg masuk nil setelah equip)
            local eggName = rec.AssetCategory or rec.DisplayName
                or (rec.Rarity and rec._id) or tostring(rec.Uid)

            local tool = nil
            -- Cari di nil instances
            tool = getToolFromNil(eggName)
            -- Fallback: scan character
            if not tool then
                local char = LocalPlayer.Character
                if char then
                    tool = char:FindFirstChildOfClass("Tool")
                end
            end

            if tool then
                -- 3. Trigger sell via ToolTrigger
                pcall(function() triggerRemote:FireServer(tool) end)
                sold += 1
                print("[AutoSell] sold: " .. tostring(eggName))
            else
                warn("[AutoSell] tool not found for: " .. tostring(eggName))
            end
            task.wait(0.3)
        end
        print(string.format("[AutoSell] sold=%d skipped=%d", sold, skipped))
    end)
end

task.spawn(function()
    while true do
        task.wait(5)
        if State.sellEnabled then
            if not EggState then loadModules() end
            pcall(runAutoSell)
        end
    end
end)

-- ============================================================
-- AUTO SELL PET -- scan Backpack by name (PET_RARITY_MAP)
-- Butuh remote sell single pet dari rspy lo nanti
-- ============================================================
local function runAutoSellPet()
    if not State.sellEnabled then return end
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("Packages")
            and ReplicatedStorage.Packages:FindFirstChild("Networking")
        if not net then return end

        -- Sell All
        if State.sellAll then
            local remote = net:FindFirstChild("RE/PetSatchel/SellEveryPet")
            if remote then remote:FireServer() end
            return
        end

        local sellRemote = net:FindFirstChild("RE/PetSatchel/SellPet")
        local wearRemote = net:FindFirstChild("RF/EggWorld/AskWearTool")
        if not sellRemote then warn("[SellPet] SellPet remote not found"); return end

        local sold, skipped, unknown = 0, 0, 0

        for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if not tool:IsA("Tool") then continue end
            local itype = tool:GetAttribute("ItemType")
            if itype ~= "Asset" and itype ~= "Phone" then continue end

            local rarity = PET_RARITY_MAP[tool.Name]
            local rarNum = rarity and (RARITY_ORDER[rarity] or 0) or 0
            if rarNum == 0 then unknown += 1; continue end
            -- filter multi-select
            if next(State.sellPetMaxRarities) then
                if not State.sellPetMaxRarities[rarity] then skipped += 1; continue end
            end

            local isFav = tool:GetAttribute("IsFavorited") or tool:GetAttribute("Favorited")
            if isFav then skipped += 1; continue end

            local uid = tool:GetAttribute("Uid") or tool:GetAttribute("uid")
            if not uid then skipped += 1; continue end

            -- Equip dulu via AskWearTool
            if wearRemote then
                pcall(function() wearRemote:InvokeServer(uid) end)
                task.wait(0.2)
            end

            pcall(function() sellRemote:FireServer({uid}) end)
            sold += 1
            task.wait(0.1)
        end

        print(string.format("[SellPet] sold=%d skipped=%d unknown=%d", sold, skipped, unknown))
    end)
end

task.spawn(function()
    while true do
        task.wait(State.sellPetInterval or 5)
        if not State.sellEnabled then continue end
        pcall(runAutoSellPet)
    end
end)
-- ============================================================
task.spawn(function()
    while true do
        task.wait(State.batInterval)
        if State.batAura then
            local n = ReplicatedStorage:FindFirstChild("Packages")
                and ReplicatedStorage.Packages:FindFirstChild("Networking")
            local remote = n and n:FindFirstChild("RE/BatSwing/Trigger")
            if remote then
                local seed = ("%s:100:%s"):format(
                    tostring(LocalPlayer.UserId),
                    tostring(math.floor(Workspace:GetServerTimeNow() * 1000))
                )
                -- cari target terdekat
                local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local target = nil
                if myHRP then
                    local bestDist = math.huge
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer and p.Character then
                            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                            if hrp and (hrp.Position - myHRP.Position).Magnitude <= 16.5 then
                                local d = (hrp.Position - myHRP.Position).Magnitude
                                if d < bestDist then bestDist = d; target = p end
                            end
                        end
                    end
                end
                if target then
                    pcall(function() remote:FireServer(target, seed) end)
                end
            end
        end
    end
end)

-- ============================================================
-- MISC FEATURES
-- ============================================================
local _antiAfkConn = nil
local function setReduceMap(enabled)
    pcall(function()
        local lighting = game:GetService("Lighting")
        if enabled then
            -- Hanya kurangi efek visual, TIDAK hide object
            lighting.GlobalShadows = false
            lighting.FogEnd = 9999
            lighting.FogStart = 9998
            -- Matikan particle effects
            for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
                pcall(function()
                    if obj:IsA("ParticleEmitter") or obj:IsA("Trail")
                    or obj:IsA("Beam") or obj:IsA("SelectionBox") then
                        obj.Enabled = false
                    end
                    if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                        obj.Enabled = false
                    end
                end)
            end
        else
            lighting.GlobalShadows = true
            lighting.FogEnd = 100000
            lighting.FogStart = 0
        end
    end)
end

local function setAntiAfk(enabled)
    if _antiAfkConn then _antiAfkConn:Disconnect(); _antiAfkConn = nil end
    if not enabled then return end
    -- Pakai Player.Idled -- no VirtualInputManager, no BAC
    _antiAfkConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            game:GetService("VirtualUser"):Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            game:GetService("VirtualUser"):Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        end)
    end)
end

-- FPS + Ping Counter (ScreenGui)
local _statsGui = nil
local function updateStatsGui(show)
    if not show then
        if _statsGui then _statsGui:Destroy(); _statsGui = nil end
        return
    end
    if _statsGui then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "SAE_Stats"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 99998
    sg.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(120, 36)
    frame.Position = UDim2.new(1, -130, 0, 8)
    frame.BackgroundColor3 = Color3.fromRGB(15,15,20)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = sg
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(220,220,230)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = "FPS: -- | Ping: --"
    lbl.Parent = frame

    _statsGui = sg

    -- Update loop
    local lastTime = tick()
    local frameCount = 0
    RunService.RenderStepped:Connect(function()
        if not _statsGui or not _statsGui.Parent then return end
        frameCount += 1
        local now = tick()
        if now - lastTime >= 1 then
            local fps = math.floor(frameCount / (now - lastTime))
            frameCount = 0
            lastTime = now
            local ping = 0
            pcall(function()
                ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            lbl.Text = string.format("FPS: %d | Ping: %dms", fps, ping)
        end
    end)
end

-- ============================================================
-- FARM CYCLE
-- ============================================================
local function farmCycle()
    if State.busy or not State.running then return end
    State.busy = true
    local _busyStart = tick()

    pcall(function()
        if not loadModules() then return end
        local r = root(); local h2 = hum()
        if not r or not h2 then return end

        -- Busy timeout safety: reset kalau > 30 detik
        if tick() - _busyStart > 30 then
            State.busy = false; return
        end

        -- 1. Cari telur
        local rec, model = findBestEgg()
        if not rec or not model then
            State.lockedRecord = nil
            return
        end

        local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if not part then State.lockedRecord = nil; return end

        -- 2. Jalan ke telur (gak snap, jalan biasa)
        if not walkTo(part.Position, 15, false) then return end
        if not State.running then return end

        -- 3. Claim -- kena guardian: reset busy langsung, retry di cycle berikut
        r = root()
        if not r then State.busy = false; return end
        local dist = (r.Position - part.Position).Magnitude
        if dist > 8 then
            -- lockedRecord tetap biar retry egg yang sama
            State.busy = false
            return
        end

        local slotKey = nil
        pcall(function()
            if AreaEggSlotIdentity and rec.AreaId and rec.NestId then
                slotKey = AreaEggSlotIdentity.SlotKey(rec.AreaId, rec.NestId)
            end
        end)

        -- Claim -- retry 3x, cek egg masuk character tiap attempt
        local claimed = false
        for _ = 1, 3 do
            pcall(function() EggState.CarryFieldEgg(rec.Uid, slotKey) end)
            local prompt = model:FindFirstChild("CarryAreaEgg", true)
                or model:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then
                pcall(function()
                    prompt.Enabled = true
                    prompt.HoldDuration = 0
                    if typeof(fireproximityprompt) == "function" then
                        fireproximityprompt(prompt, 0)
                    end
                end)
            end
            -- Cek egg masuk character atau backpack
            local char = LocalPlayer.Character
            if char then
                for _, t in ipairs(char:GetChildren()) do
                    if t:IsA("Tool") and (t:GetAttribute("ItemType") == "AssetEgg"
                        or t:GetAttribute("ItemType") == "PetEgg"
                        or AREA_SET[t.Name]) then
                        claimed = true; break
                    end
                end
            end
            if not claimed then
                for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
                    if t:IsA("Tool") and (t:GetAttribute("ItemType") == "AssetEgg"
                        or t:GetAttribute("ItemType") == "PetEgg"
                        or AREA_SET[t.Name]) then
                        claimed = true; break
                    end
                end
            end
            if claimed then break end
        end
        State.lockedRecord = nil

        -- 4. Tunggu rubberband selesai sebelum balik
        -- Server kadang nge-push balik karakter setelah claim
        local rbTimeout = tick() + 2
        while tick() < rbTimeout do
            local r3 = root()
            if not r3 then break end
            local vel = r3.AssemblyLinearVelocity
            local hVel = Vector3.new(vel.X, 0, vel.Z).Magnitude
            -- Kalau velocity sudah rendah = rubberband selesai
            if hVel < 8 then break end
            task.wait(0.05)
        end

        -- 5. Jalan balik ke safe coords (no teleport)
        walkTo(START_POS, 15, false)
        if not State.running then return end

        State.stealCount += 1
    end)

    local h2 = hum()
    if h2 then h2.WalkSpeed = 16 end
    State.busy = false
end

-- ============================================================
-- ESP SYSTEM (VD Style)
-- ============================================================
local EspHighlights = {}
local EspBillboards = {}

local function clearESP(uid)
    if EspHighlights[uid] then
        pcall(function() EspHighlights[uid]:Destroy() end)
        EspHighlights[uid] = nil
    end
    if EspBillboards[uid] then
        pcall(function() EspBillboards[uid]:Destroy() end)
        EspBillboards[uid] = nil
    end
end

local function createESP(model, uid, rarityCol, dispName, rarityName, earning)
    -- Highlight
    if not EspHighlights[uid] or not EspHighlights[uid].Parent then
        local h = Instance.new("Highlight")
        h.Name                = "SAE_HL"
        h.FillColor           = rarityCol
        h.OutlineColor        = rarityCol
        h.FillTransparency    = 0.7
        h.OutlineTransparency = 0.2
        h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent              = model
        EspHighlights[uid]    = h
    else
        EspHighlights[uid].FillColor    = rarityCol
        EspHighlights[uid].OutlineColor = rarityCol
    end

    -- Billboard
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    local bb = EspBillboards[uid]
    if not bb or not bb.Parent then
        bb = Instance.new("BillboardGui")
        bb.Name        = "SAE_ESP"
        bb.AlwaysOnTop = true
        bb.Size        = UDim2.new(0, 200, 0, 25)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.Adornee     = part
        bb.Parent      = part

        local box = Instance.new("Frame")
        box.Name                   = "Box"
        box.AutomaticSize          = Enum.AutomaticSize.X
        box.Size                   = UDim2.new(0, 0, 0, 15)
        box.Position               = UDim2.new(0.5, 0, 0, 0)
        box.AnchorPoint            = Vector2.new(0.5, 0)
        box.BackgroundColor3       = Color3.fromRGB(15, 15, 15)
        box.BackgroundTransparency = 0
        box.BorderSizePixel        = 0
        box.ZIndex                 = 2
        box.Parent                 = bb
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)

        local grad = Instance.new("UIGradient")
        grad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0,    1),
            NumberSequenceKeypoint.new(0.15, 0.35),
            NumberSequenceKeypoint.new(0.85, 0.35),
            NumberSequenceKeypoint.new(1,    1),
        })
        grad.Parent = box

        local pad = Instance.new("UIPadding", box)
        pad.PaddingLeft  = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)

        local layout = Instance.new("UIListLayout", box)
        layout.FillDirection       = Enum.FillDirection.Horizontal
        layout.VerticalAlignment   = Enum.VerticalAlignment.Center
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.Padding             = UDim.new(0, 3)
        layout.SortOrder           = Enum.SortOrder.LayoutOrder

        local txt = Instance.new("TextLabel", box)
        txt.Name                   = "Text"
        txt.AutomaticSize          = Enum.AutomaticSize.X
        txt.Size                   = UDim2.new(0, 0, 1, 0)
        txt.BackgroundTransparency = 1
        txt.Font                   = Enum.Font.GothamMedium
        txt.TextSize               = 10
        txt.ZIndex                 = 3
        txt.LayoutOrder            = 1
        txt.RichText               = true
        txt.TextXAlignment         = Enum.TextXAlignment.Center
        txt.TextYAlignment         = Enum.TextYAlignment.Center

        local line = Instance.new("Frame")
        line.Name            = "Line"
        line.Size            = UDim2.new(0, 1, 0, 10)
        line.Position        = UDim2.new(0.5, 0, 0, 15)
        line.AnchorPoint     = Vector2.new(0.5, 0)
        line.BorderSizePixel = 0
        line.ZIndex          = 1
        line.Parent          = bb
        local lg = Instance.new("UIGradient")
        lg.Rotation    = 90
        lg.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        })
        lg.Parent = line

        EspBillboards[uid] = bb
    end

    -- Update content
    local hex = string.format("#%02X%02X%02X",
        math.floor(rarityCol.R * 255),
        math.floor(rarityCol.G * 255),
        math.floor(rarityCol.B * 255)
    )
    local box2 = bb:FindFirstChild("Box")
    if box2 then
        local line2 = bb:FindFirstChild("Line")
        if line2 then line2.BackgroundColor3 = rarityCol end
        local txt2 = box2:FindFirstChild("Text")
        if txt2 then
            txt2.Text = string.format(
                "<font color='#FFFFFF'>%s</font> <font color='%s'>%s</font> <font color='#B4FFB4'>$%s</font>",
                dispName, hex, rarityName, formatNumber(earning)
            )
        end
    end
end

local function updateESP()
    if not State.espEnabled then
        for uid in pairs(EspHighlights) do clearESP(uid) end
        for uid in pairs(EspBillboards) do clearESP(uid) end
        return
    end
    if not EggState then loadModules() end
    if not EggState then return end

    local ok, fieldEggs = pcall(function() return EggState.ReadFieldEggs() end)
    if not ok or not fieldEggs or not fieldEggs.Records then return end

    local active = {}
    for _, rec in ipairs(fieldEggs.Records) do
        local uid = rec.Uid
        if not uid then continue end
        active[uid] = true

        local model = Workspace:FindFirstChild("AreaEggSlotsClient", true)
            and Workspace.AreaEggSlotsClient:FindFirstChild(uid)
            or Workspace:FindFirstChild(uid, true)
        if not model then continue end

        local d        = getAssetData(rec)
        local col      = getRarityColor(rec)
        local name     = getRarityName(rec)
        local earning  = getEarningRate(rec)
        local dispName = d.DisplayName or rec.AssetCategory or uid

        pcall(createESP, model, uid, col, dispName, name, earning)
    end

    for uid in pairs(EspHighlights) do
        if not active[uid] then clearESP(uid) end
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        pcall(updateESP)
    end
end)





-- ============================================================
-- OBSIDIAN UI
-- ============================================================
local WisnuLib = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/WisnuX67/Wisnu-ui/main/source.lua"
))()
if not WisnuLib then warn("[SAE] Wisnu UI gagal load"); return end

local function Notify(title, text, dur)
    pcall(function()
        WisnuLib:SetNotification({ Content = title .. ": " .. text, Delay = dur or 3 })
    end)
end

local RARITIES = {
    "Common","Uncommon","Rare","Epic","Legendary","Mythic",
    "SuperRare","Exotic","Limited","Divine","Secret","Titan",
    "Cosmic","Celestial","Transcendent","Prismatic","Rainbow",
    "Eternal","Brainrot","Mythical","Exclusive"
}

local Window = WisnuLib:CreateWindow({
    Title       = "WISNU HUB",
    Description = "Steal An Egg v2.0",
    TabWidth    = 110,
    Keybind     = Enum.KeyCode.RightShift,
})

local Tabs = {
    Farm   = Window:CreateTab({ Name = "Farm" }),
    Store  = Window:CreateTab({ Name = "Store" }),
    Misc   = Window:CreateTab({ Name = "Misc" }),
    Config = Window:CreateTab({ Name = "Config" }),
}

local function Sec(tab, name) return tab:AddSection(name) end

-- FARM
local grpSteal = Sec(Tabs.Farm, "Auto Steal")
grpSteal:AddToggle({ Title = "Auto Steal", Default = false, Callback = function(v)
    State.running = v
    if v then
        loadModules(); doHumanoidBypass()
        Notify("SAE","Farm started!",2)
        task.spawn(function()
            while State.running do farmCycle(); task.wait(0.05) end
        end)
    else
        State.running = false; State.busy = false; State.lockedRecord = nil
        if _camConn then _camConn:Disconnect(); _camConn = nil end
        if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
        Notify("SAE","Farm stopped.",2)
        task.delay(0.3, function() pcall(function() LocalPlayer:LoadCharacter() end) end)
    end
end })
grpSteal:AddToggle({ Title = "Anti-Guard", Default = true, Callback = function(v) State.antiGuard = v end })
grpSteal:AddToggle({ Title = "Bat Aura", Default = false, Callback = function(v) State.batAura = v end })
grpSteal:AddToggle({ Title = "No Knockback", Default = false,
    Callback = function(v) State.noKnockback = v; if v then applyNoKnockback() end end })
grpSteal:AddSlider({ Title = "Walk Speed", Min = 16, Max = 500, Default = 120, Increment = 0,
    Callback = function(v) State.speed = v end })
grpSteal:AddDropdown({ Title = "Target Rarities", Options = RARITIES, Default = {}, Multi = true,
    Callback = function(v) State.targetRarities = {}; for k,s in pairs(v) do if s then State.targetRarities[k]=true end end end })
grpSteal:AddDropdown({ Title = "Target Mutations", Options = MUTATIONS, Default = {}, Multi = true,
    Callback = function(v) State.targetMutations = {}; for k,s in pairs(v) do if s then State.targetMutations[k]=true end end end })

local grpVisual = Sec(Tabs.Farm, "Visual")
grpVisual:AddToggle({ Title = "Egg ESP", Default = false,
    Callback = function(v) State.espEnabled = v; if not v then for uid in pairs(EspHighlights) do clearESP(uid) end end end })
grpVisual:AddToggle({ Title = "Float (visual)", Default = false,
    Callback = function(v) State.floatEnabled = v; updateFloat() end })
grpVisual:AddSlider({ Title = "Float Height", Min = 1, Max = 10, Default = 3, Increment = 1,
    Callback = function(v) State.floatHeight = v end })
grpVisual:AddToggle({ Title = "Animation", Default = true,
    Callback = function(v) State.animEnabled = v; updateAnim() end })
grpVisual:AddButton({ Title = "Upgrade Base", Callback = function() upgradeBase() end })
grpVisual:AddButton({ Title = "Upgrade Treadmill", Callback = function() upgradeTreadmill(1) end })

local grpPlace = Sec(Tabs.Farm, "Auto Place Egg")
grpPlace:AddToggle({ Title = "Enable", Default = false,
    Callback = function(v) State.placeEnabled = v; if v then loadModules() end end })
grpPlace:AddSlider({ Title = "Interval (s)", Min = 1, Max = 120, Default = 5, Increment = 1,
    Callback = function(v) State.placeInterval = v end })
grpPlace:AddDropdown({ Title = "Min Rarity", Options = RARITIES, Default = {}, Multi = true,
    Callback = function(v)
        local minNum = 999
        for k,s in pairs(v) do if s and RARITY_ORDER[k] then minNum = math.min(minNum, RARITY_ORDER[k]) end end
        State.placeMinRarity = minNum < 999 and (function() for k in pairs(RARITY_ORDER) do if RARITY_ORDER[k]==minNum then return k end end return "All" end)() or "All"
    end })
grpPlace:AddButton({ Title = "Place Now", Callback = function() loadModules(); pcall(runAutoPlace); Notify("Place","Triggered!",2) end })

local grpPlacePet = Sec(Tabs.Farm, "Auto Place Pet")
grpPlacePet:AddToggle({ Title = "Enable", Default = false,
    Callback = function(v) State.placePetEnabled = v; if v then loadModules() end end })
grpPlacePet:AddSlider({ Title = "Interval (s)", Min = 1, Max = 120, Default = 5, Increment = 1,
    Callback = function(v) State.placePetInterval = v end })
grpPlacePet:AddButton({ Title = "Place Pet Now", Callback = function() loadModules(); pcall(runAutoPlacePet); Notify("Place Pet","Triggered!",2) end })

local grpPlaceBest = Sec(Tabs.Farm, "Auto Place Best Pet")
grpPlaceBest:AddToggle({ Title = "Enable", Default = false,
    Callback = function(v) State.placeBestPetEnabled = v; if v then loadModules() end end })
grpPlaceBest:AddSlider({ Title = "Interval (s)", Min = 5, Max = 60, Default = 10, Increment = 1,
    Callback = function(v) State.placeBestPetInterval = v end })
grpPlaceBest:AddButton({ Title = "Place Best Now", Callback = function() loadModules(); pcall(runAutoPlaceBestPet); Notify("Place Best","Triggered!",2) end })

local grpHatch = Sec(Tabs.Farm, "Auto Hatch")
grpHatch:AddToggle({ Title = "Enable", Default = false,
    Callback = function(v) State.hatchEnabled = v; if v then loadModules() end end })
grpHatch:AddSlider({ Title = "Interval (s)", Min = 1, Max = 30, Default = 3, Increment = 1,
    Callback = function(v) State.hatchInterval = v end })
grpHatch:AddButton({ Title = "Hatch Now", Callback = function() loadModules(); pcall(runAutoHatch); Notify("Hatch","Triggered!",2) end })

local grpVal = Sec(Tabs.Farm, "Value Filter")
grpVal:AddInput({ Title = "Min Earning Rate", Default = "0",
    Callback = function(v) State.minEarningRate = tonumber(v) or 0 end })
grpVal:AddInput({ Title = "Min Weight (kg)", Default = "0",
    Callback = function(v) State.minModelWeight = tonumber(v) or 0 end })
grpVal:AddInput({ Title = "Max Weight (kg)", Default = "0",
    Callback = function(v) local n=tonumber(v) or 0; State.maxModelWeight = n==0 and 999999999 or n end })

-- STORE
local grpSell = Sec(Tabs.Store, "Auto Sell")
grpSell:AddToggle({ Title = "Enable Auto Sell", Default = false,
    Callback = function(v) State.sellEnabled = v; if v then loadModules() end end })
grpSell:AddToggle({ Title = "Sell Every Pet", Default = false,
    Callback = function(v) State.sellAll = v end })
grpSell:AddSlider({ Title = "Interval (s)", Min = 1, Max = 60, Default = 5, Increment = 1,
    Callback = function(v) State.sellInterval = v end })
grpSell:AddDropdown({ Title = "Sell Max Rarity", Options = RARITIES, Default = "Epic",
    Callback = function(v) State.sellMaxRarity = v end })
grpSell:AddButton({ Title = "Sell Now", Callback = function() loadModules(); pcall(runAutoSell); Notify("Sell","Triggered!",2) end })

local grpSellEgg = Sec(Tabs.Store, "Auto Sell Egg")
grpSellEgg:AddToggle({ Title = "Enable", Default = false,
    Callback = function(v) State.sellEggEnabled = v; if v then loadModules() end end })
grpSellEgg:AddSlider({ Title = "Interval (s)", Min = 5, Max = 60, Default = 10, Increment = 1,
    Callback = function(v) State.sellEggInterval = v end })
grpSellEgg:AddButton({ Title = "Sell Egg Now", Callback = function() loadModules(); pcall(runAutoSellEgg); Notify("Sell Egg","Triggered!",2) end })

local grpCollect = Sec(Tabs.Store, "Collect Money")
grpCollect:AddToggle({ Title = "Auto Collect", Default = false,
    Callback = function(v) State.collectEnabled = v end })
grpCollect:AddSlider({ Title = "Interval (s)", Min = 10, Max = 300, Default = 60, Increment = 1,
    Callback = function(v) State.collectInterval = v end })
grpCollect:AddButton({ Title = "Collect Now", Callback = function() pcall(runCollectMoney); Notify("Collect","Claimed!",2) end })

local grpFav = Sec(Tabs.Store, "Auto Favorite")
grpFav:AddToggle({ Title = "Auto Favorite Pet", Default = false,
    Callback = function(v) State.favPetEnabled = v end })
grpFav:AddToggle({ Title = "Auto Favorite Egg", Default = false,
    Callback = function(v) State.favEggEnabled = v end })
grpFav:AddDropdown({ Title = "Target Rarities", Options = RARITIES, Default = {}, Multi = true,
    Callback = function(v) State.favMinRarities = {}; for k,s in pairs(v) do if s then State.favMinRarities[k]=true end end end })
grpFav:AddButton({ Title = "Favorite Now", Callback = function() pcall(runAutoFavorite); Notify("Favorite","Done!",2) end })

-- MISC
local grpMisc = Sec(Tabs.Misc, "Visual")
grpMisc:AddToggle({ Title = "FPS & Ping Counter", Default = false,
    Callback = function(v) updateStatsGui(v) end })
grpMisc:AddToggle({ Title = "Reduce Map", Default = false,
    Callback = function(v) State.reducedMap = v; setReduceMap(v) end })
grpMisc:AddToggle({ Title = "Cycle Panel", Default = false,
    Callback = function(v) _cycleGui.Enabled = v end })

local grpMisc2 = Sec(Tabs.Misc, "Utility")
grpMisc2:AddToggle({ Title = "Anti AFK", Default = true,
    Callback = function(v) State.antiAfk = v; setAntiAfk(v) end })
grpMisc2:AddToggle({ Title = "Anti Staff", Default = true,
    Callback = function(v)
        if v then task.spawn(function()
            while v do
                for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                    if p ~= LocalPlayer then
                        local badge = p:GetAttribute("IsStaff") or p:GetAttribute("Staff")
                        if badge then State.running = false; Notify("Anti Staff","Staff: "..p.Name,5) end
                    end
                end
                task.wait(3)
            end
        end) end
    end })
grpMisc2:AddButton({ Title = "Rejoin", Callback = function()
    pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end })
grpMisc2:AddButton({ Title = "Server Hop", Callback = function()
    pcall(function()
        local HS = game:GetService("HttpService")
        local TPS = game:GetService("TeleportService")
        local result = HS:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
        local servers = {}
        for _, s in ipairs(result.data or {}) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers then table.insert(servers, s) end
        end
        if #servers > 0 then TPS:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1,#servers)].id, LocalPlayer)
        else Notify("Server Hop","No servers found",3) end
    end)
end })

local grpKeybind = Sec(Tabs.Misc, "Keybind")
grpKeybind:AddKeybind({ Title = "Toggle UI", Default = Enum.KeyCode.RightShift,
    Callback = function(key)
        -- toggle UI via keybind
    end })

-- CONFIG
Sec(Tabs.Config, "Config"):AddButton({ Title = "Save Config", Callback = function()
    Notify("Config","Saved!",2)
end })

Notify("Steal An Egg", "v2.0 loaded!", 3)

-- Auto-aktif saat load
task.spawn(function()
    task.wait(2)
    -- applyNoKnockback() -- dimatiin, BAC risk
    setAntiAfk(true)    -- anti afk
    -- anti staff loop
    task.spawn(function()
        while true do
            for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                if p ~= LocalPlayer then
                    local badge = p:GetAttribute("IsStaff") or p:GetAttribute("Staff")
                    if badge then
                        State.running = false
                        Notify("Anti Staff", "Staff: "..p.Name, 5)
                    end
                end
            end
            task.wait(3)
        end
    end)
end)
