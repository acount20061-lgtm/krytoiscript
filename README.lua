-- UA Killer Hub | YBA — покращена версія
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function findPressedPlayRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local remote = remotes:FindFirstChild("RemoteEvent") or remotes:FindFirstChildOfClass("RemoteEvent")
        if remote then return remote end
    end
    return ReplicatedStorage:FindFirstChild("RemoteEvent", true)
end

local function skipStartMenu()
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(132, 265, 0, true, game, 0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(132, 265, 0, false, game, 0)
    end)

    pcall(function()
        local remote = findPressedPlayRemote()
        if remote then
            remote:FireServer("PressedPlay")
        end
    end)
end

skipStartMenu()

if not player.Character then
    player.CharacterAdded:Wait()
end

repeat task.wait() until player.Character and player.Character:FindFirstChild("HumanoidRootPart")

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local autoLoadFile = "YBA_AutoLoad.txt"
local shouldAutoLoad = false

pcall(function()
    if makefolder and not isfolder("UAKillerHub") then
        makefolder("UAKillerHub")
    end
end)

pcall(function()
    if isfile and isfile(autoLoadFile) then
        shouldAutoLoad = (readfile(autoLoadFile) == "true")
    elseif writefile then
        writefile(autoLoadFile, "false")
    end
end)

local RayfieldSuccess, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not RayfieldSuccess then return end

-- ====================
-- ГЛОБАЛЬНІ НАЛАШТУВАННЯ
-- ====================
_G.AutoSell = false
_G.AutoBuy = false
_G.ItemFarm = false
_G.ItemESP = false
_G.FlySpeed = 150
_G.PickupDistance = 3.5
_G.AntiAFK = false
_G.StandaloneNoClip = false

_G.SelectedItems = {
    ["Ancient Scroll"] = false,
    ["Blue Candy"] = false,
    ["Caesar's Headband"] = false,
    ["Christmas Present"] = false,
    ["Clackers"] = false,
    ["Diamond"] = false,
    ["Dio's Diary"] = false,
    ["Gold Coin"] = false,
    ["Gold Umbrella"] = false,
    ["Green Candy"] = false,
    ["Lucky Arrow"] = false,
    ["Lucky Stone Mask"] = false,
    ["Mysterious Arrow"] = false,
    ["Pure Rokakaka"] = false,
    ["Quinton's Glove"] = false,
    ["Red Candy"] = false,
    ["Rib Cage of The Saint's Corpse"] = false,
    ["Rokakaka"] = false,
    ["Steel Ball"] = false,
    ["Stone Mask"] = false,
    ["Yellow Candy"] = false,
    ["Zepellin's Headband"] = false,
    ["Zeppeli's Hat"] = false,
}

_G.ItemsToSell = {
    ["Ancient Scroll"] = true,
    ["Caesar's Headband"] = true,
    ["Clackers"] = true,
    ["Diamond"] = true,
    ["Dio's Diary"] = true,
    ["Gold Coin"] = true,
    ["Gold Umbrella"] = true,
    ["Mysterious Arrow"] = true,
    ["Pure Rokakaka"] = true,
    ["Quinton's Glove"] = true,
    ["Rib Cage of The Saint's Corpse"] = true,
    ["Rokakaka"] = true,
    ["Steel Ball"] = true,
    ["Stone Mask"] = true,
    ["Zepellin's Headband"] = true,
    ["Zeppeli's Hat"] = true,
}

local bannedCoordinates = {}
local espObjects = {}
local itemCache = {}
local lastCacheRefresh = 0
local CACHE_REFRESH_INTERVAL = 1.25
local BAN_TTL = 45

local farmThreadActive = false
local farmStatusText = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection

-- ====================
-- ДОПОМІЖНІ ФУНКЦІЇ
-- ====================
local function setFarmStatus(text)
    farmStatusText = text
end

local function safeGetPartPosition(part)
    local ok, pos = pcall(function()
        return part.Position
    end)
    if ok then return pos end
    return nil
end

local function safeGetPartTransparency(part)
    local ok, transparency = pcall(function()
        return part.Transparency
    end)
    if ok then return transparency end
    return 1
end

local function safeIsPromptEnabled(prompt)
    local ok, enabled = pcall(function()
        return prompt.Enabled
    end)
    if ok then return enabled end
    return false
end

local function safeGetPromptObjectText(prompt)
    local ok, text = pcall(function()
        return prompt.ObjectText
    end)
    if ok then return text end
    return nil
end

local function safeUnlockPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    pcall(function()
        prompt.RequiresLineOfSight = false
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 50
        prompt.Enabled = true
    end)
end

local function UnlockPrompts()
    while true do
        pcall(function()
            for _, desc in ipairs(workspace:GetDescendants()) do
                if desc:IsA("ProximityPrompt") then
                    safeUnlockPrompt(desc)
                end
            end
        end)
        task.wait(0.5)
    end
end

task.spawn(UnlockPrompts)

local function isInvalidItemPart(obj)
    if not obj then return true end
    local current = obj
    while current and current ~= workspace do
        if current:IsA("Backpack") then
            return true
        end
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
            return true
        end
        current = current.Parent
    end
    return false
end

local function cleanupBannedCoordinates()
    local now = tick()
    for i = #bannedCoordinates, 1, -1 do
        if now - bannedCoordinates[i].time > BAN_TTL then
            table.remove(bannedCoordinates, i)
        end
    end
end

local function isCoordinateBanned(pos)
    cleanupBannedCoordinates()
    for _, entry in ipairs(bannedCoordinates) do
        if (pos - entry.pos).Magnitude < 3 then
            return true
        end
    end
    return false
end

local function banCoordinate(pos)
    table.insert(bannedCoordinates, { pos = pos, time = tick() })
end

local function resolveItemFromPrompt(desc)
    if not desc or not desc:IsA("ProximityPrompt") then
        return nil
    end

    local parentOk, parent = pcall(function()
        return desc.Parent
    end)
    if not parentOk or not parent then
        return nil
    end

    local model = parent:IsA("Model") and parent or parent.Parent
    local itemName = ""

    if _G.SelectedItems[parent.Name] ~= nil then
        itemName = parent.Name
    elseif model and _G.SelectedItems[model.Name] ~= nil then
        itemName = model.Name
    else
        local objectText = safeGetPromptObjectText(desc)
        if objectText and _G.SelectedItems[objectText] ~= nil then
            itemName = objectText
        end
    end

    if itemName == "" then
        return nil
    end

    local targetPart = parent:IsA("BasePart") and parent
        or parent:FindFirstChildWhichIsA("BasePart")
        or (model and model:FindFirstChildWhichIsA("BasePart"))

    if not targetPart then
        return nil
    end

    local transparency = safeGetPartTransparency(targetPart)
    if transparency >= 1 then
        return nil
    end

    local position = safeGetPartPosition(targetPart)
    if not position or isCoordinateBanned(position) or isInvalidItemPart(targetPart) then
        return nil
    end

    if not safeIsPromptEnabled(desc) then
        return nil
    end

    return {
        prompt = desc,
        part = targetPart,
        parent = parent,
        name = itemName,
        position = position,
    }
end

local function anyItemSelected()
    for _, selected in pairs(_G.SelectedItems) do
        if selected then return true end
    end
    return false
end

local function shouldFarmItem(itemName)
    if not anyItemSelected() then
        return true
    end
    return _G.SelectedItems[itemName] == true
end

local function refreshItemCache()
    local now = tick()
    if now - lastCacheRefresh < CACHE_REFRESH_INTERVAL then
        return itemCache
    end

    lastCacheRefresh = now
    table.clear(itemCache)

    pcall(function()
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                local item = resolveItemFromPrompt(desc)
                if item and shouldFarmItem(item.name) then
                    table.insert(itemCache, item)
                end
            end
        end
    end)

    return itemCache
end

local function getNearestItem(hrp)
    local nearest
    local shortest = math.huge

    local hrpPos = safeGetPartPosition(hrp)
    if not hrpPos then
        return nil, math.huge
    end

    for _, item in ipairs(refreshItemCache()) do
        local promptOk = pcall(function()
            return item.prompt:IsDescendantOf(workspace)
        end)
        if promptOk and not isInvalidItemPart(item.parent) then
            local position = safeGetPartPosition(item.part) or item.position
            local dist = (hrpPos - position).Magnitude
            if dist < shortest then
                shortest = dist
                nearest = item
            end
        end
    end

    return nearest, shortest
end

local function applyESP(part, name)
    if espObjects[part] then return end

    local position = safeGetPartPosition(part)
    local transparency = safeGetPartTransparency(part)
    if not part or transparency >= 1 or not position or isCoordinateBanned(position) or isInvalidItemPart(part) then
        return
    end

    pcall(function()
        local bgui = Instance.new("BillboardGui")
        bgui.Name = "YBA_Item_ESP"
        bgui.AlwaysOnTop = true
        bgui.Size = UDim2.new(0, 140, 0, 32)
        bgui.Adornee = part

        local text = Instance.new("TextLabel")
        text.Parent = bgui
        text.BackgroundTransparency = 1
        text.Size = UDim2.new(1, 0, 1, 0)
        text.Text = name
        text.TextColor3 = Color3.fromRGB(0, 255, 255)
        text.TextSize = 14
        text.Font = Enum.Font.GothamBold
        text.TextStrokeTransparency = 0

        bgui.Parent = part
        espObjects[part] = bgui
    end)
end

local function clearESP()
    for part, gui in pairs(espObjects) do
        pcall(function()
            if gui then gui:Destroy() end
        end)
        espObjects[part] = nil
    end
    table.clear(espObjects)
end

local function getCharacter()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function zeroHrpVelocity(hrp)
    if not hrp then return end
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function cleanupFlight()
    if not flightState then return end

    if flightState.tween then
        pcall(function()
            flightState.tween:Cancel()
        end)
    end
    if flightState.heartbeatConn then
        flightState.heartbeatConn:Disconnect()
    end
    if flightState.cframeValue then
        pcall(function()
            flightState.cframeValue:Destroy()
        end)
    end

    flightState = nil
end

local function stopFlight()
    cleanupFlight()

    if noclipConnection and not _G.StandaloneNoClip and not _G.ItemFarm then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end

local function ensureNoClip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if not _G.ItemFarm and not _G.StandaloneNoClip then return end
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= hrp then
                pcall(function()
                    part.CanCollide = false
                end)
            end
        end
    end)
end

local function firePromptReliably(prompt)
    safeUnlockPrompt(prompt)
    for i = 1, 4 do
        pcall(function()
            fireproximityprompt(prompt, 0)
        end)
        task.wait(0.05)
    end
end

local function moveToItemAndPickup(item)
    if not item or not item.part or not item.prompt then
        return false
    end

    local partExists = pcall(function()
        return item.part:IsDescendantOf(workspace)
    end)
    local promptExists = pcall(function()
        return item.prompt:IsDescendantOf(workspace)
    end)
    if not partExists or not promptExists then
        return false
    end
    if isInvalidItemPart(item.parent) then
        return false
    end

    local char, hrp = getCharacter()
    if not hrp then return false end

    cleanupFlight()

    local cframeValue = Instance.new("CFrameValue")
    cframeValue.Name = "YBA_VirtualCFrame"
    cframeValue.Value = hrp.CFrame
    cframeValue.Parent = player

    local itemPosition = safeGetPartPosition(item.part)
    if not itemPosition then
        cleanupFlight()
        return false
    end

    local targetCFrame = CFrame.new(itemPosition + Vector3.new(0, 1.2, 0))
    local hrpPos = safeGetPartPosition(hrp)
    if not hrpPos then
        cleanupFlight()
        return false
    end

    local distance = (targetCFrame.Position - hrpPos).Magnitude
    local tweenTime = math.max(distance / _G.FlySpeed, 0.05)

    local tween = TweenService:Create(
        cframeValue,
        TweenInfo.new(tweenTime, Enum.EasingStyle.Linear),
        { Value = targetCFrame }
    )

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent then return end
        local currentHrp = char:FindFirstChild("HumanoidRootPart")
        if not currentHrp or not cframeValue.Parent then return end

        pcall(function()
            currentHrp.CFrame = cframeValue.Value
        end)
        zeroHrpVelocity(currentHrp)

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= currentHrp then
                pcall(function()
                    part.CanCollide = false
                end)
            end
        end
    end)

    flightState = {
        cframeValue = cframeValue,
        tween = tween,
        heartbeatConn = heartbeatConn,
    }

    local function shouldContinue()
        local partOk = pcall(function()
            return item.part:IsDescendantOf(workspace) and not isInvalidItemPart(item.part)
        end)
        local promptOk = pcall(function()
            return item.prompt:IsDescendantOf(workspace)
        end)
        return _G.ItemFarm and partOk and promptOk
    end

    tween:Play()

    local finished = false
    tween.Completed:Once(function()
        finished = true
    end)

    while not finished do
        if not shouldContinue() then
            cleanupFlight()
            return false
        end
        local hrpAlive = pcall(function()
            return hrp and hrp.Parent
        end)
        if not hrpAlive then
            cleanupFlight()
            return false
        end
        RunService.Heartbeat:Wait()
    end

    if not shouldContinue() then
        cleanupFlight()
        return false
    end

    itemPosition = safeGetPartPosition(item.part)
    if not itemPosition then
        cleanupFlight()
        return false
    end

    targetCFrame = CFrame.new(itemPosition + Vector3.new(0, 1.2, 0))
    cframeValue.Value = targetCFrame

    local currentHrp = char:FindFirstChild("HumanoidRootPart")
    if currentHrp then
        pcall(function()
            currentHrp.Anchored = true
            currentHrp.CFrame = targetCFrame
        end)
        zeroHrpVelocity(currentHrp)
    end

    task.wait(0.35)

    if shouldContinue() and currentHrp then
        local hrpStillAlive = pcall(function()
            return currentHrp.Parent
        end)
        if hrpStillAlive then
            firePromptReliably(item.prompt)
            task.wait(0.15)
            pcall(function()
                currentHrp.Anchored = false
            end)
        end
    elseif currentHrp then
        pcall(function()
            currentHrp.Anchored = false
        end)
    end

    local pickedUp = false
    pcall(function()
        pickedUp = not item.prompt:IsDescendantOf(workspace) or isInvalidItemPart(item.parent)
    end)

    cleanupFlight()
    return pickedUp
end

local function setAntiAfkEnabled(enabled)
    _G.AntiAFK = enabled
    if antiAfkConnection then
        antiAfkConnection:Disconnect()
        antiAfkConnection = nil
    end
    if enabled then
        antiAfkConnection = player.Idled:Connect(function()
            game:GetService("VirtualUser"):ClickButton2(Vector2.new())
        end)
    end
end

-- ====================
-- UI
-- ====================
local Window = Rayfield:CreateWindow({
    Name = "UA Killer Hub | YBA",
    LoadingTitle = "Завантаження...",
    LoadingSubtitle = "by acount20061-lgtm | VIRTUAL CFRAME BYPASS",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "UAKillerHub",
        FileName = "YBA_Config",
    },
})

local MainTab = Window:CreateTab("Головна", 4483362458)
local FarmTab = Window:CreateTab("Автофарм", 4483362534)
local ShopTab = Window:CreateTab("Магазин", 4483362458)
local MiscTab = Window:CreateTab("Інше", 4483362458)

-- ====================
-- ГОЛОВНА
-- ====================
MainTab:CreateSection("Налаштування конфігу")

MainTab:CreateToggle({
    Name = "Автозавантаження конфігу при старті",
    CurrentValue = shouldAutoLoad,
    Callback = function(value)
        pcall(function()
            if writefile then writefile(autoLoadFile, tostring(value)) end
        end)
    end,
})

MainTab:CreateButton({
    Name = "Завантажити конфіг вручну",
    Callback = function()
        pcall(function() Rayfield:LoadConfiguration() end)
    end,
})

-- ====================
-- МАГАЗИН
-- ====================
local sellQueue = {}
local isSelling = false

local function processSellQueue()
    if isSelling then return end
    isSelling = true

    while #sellQueue > 0 do
        if not _G.AutoSell then break end

        local item = table.remove(sellQueue, 1)
        local backpack = player:FindFirstChild("Backpack")
        if item and backpack and item.Parent == backpack and item:IsA("Tool") and _G.ItemsToSell[item.Name] == true then
            local char, _, hum = getCharacter()
            local remote = char and char:FindFirstChild("RemoteEvent")
            if remote and hum then
                hum:EquipTool(item)
                task.wait(0.45)
                remote:FireServer("EndDialogue", {
                    Option = "Option1",
                    Dialogue = "Dialogue5",
                    NPC = "Merchant",
                })
                task.wait(0.35)
            end
        end
    end

    isSelling = false
end

local function queueItemForSale(item)
    if not _G.AutoSell then return end
    if not item or not item:IsA("Tool") or _G.ItemsToSell[item.Name] ~= true then return end
    table.insert(sellQueue, item)
    task.spawn(processSellQueue)
end

local function setupBackpackListener(backpack)
    for _, item in ipairs(backpack:GetChildren()) do
        queueItemForSale(item)
    end
    backpack.ChildAdded:Connect(function(item)
        task.wait(0.35)
        queueItemForSale(item)
    end)
end

player.ChildAdded:Connect(function(child)
    if child.Name == "Backpack" then setupBackpackListener(child) end
end)
if player:FindFirstChild("Backpack") then setupBackpackListener(player.Backpack) end

ShopTab:CreateToggle({
    Name = "Автопродаж",
    CurrentValue = false,
    Flag = "AutoSell_Toggle",
    Callback = function(value)
        _G.AutoSell = value
        if value then
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                for _, item in ipairs(backpack:GetChildren()) do
                    queueItemForSale(item)
                end
            end
        else
            table.clear(sellQueue)
        end
    end,
})

ShopTab:CreateSection("Фільтр продажу")

ShopTab:CreateButton({
    Name = "Увімкнути все",
    Callback = function()
        for name in pairs(_G.ItemsToSell) do
            _G.ItemsToSell[name] = true
        end
    end,
})

ShopTab:CreateButton({
    Name = "Вимкнути все",
    Callback = function()
        for name in pairs(_G.ItemsToSell) do
            _G.ItemsToSell[name] = false
        end
    end,
})

local sortedSellItems = {}
for name in pairs(_G.ItemsToSell) do
    table.insert(sortedSellItems, name)
end
table.sort(sortedSellItems)

for _, itemName in ipairs(sortedSellItems) do
    ShopTab:CreateToggle({
        Name = itemName,
        CurrentValue = _G.ItemsToSell[itemName],
        Flag = "SellFilter_" .. itemName,
        Callback = function(value)
            _G.ItemsToSell[itemName] = value
        end,
    })
end

ShopTab:CreateToggle({
    Name = "Автокупівля (Lucky Arrow)",
    CurrentValue = false,
    Flag = "AutoBuy_Toggle",
    Callback = function(value)
        _G.AutoBuy = value
        if value then
            task.spawn(function()
                while _G.AutoBuy do
                    local char = player.Character
                    local remote = char and char:FindFirstChild("RemoteEvent")
                    if remote then
                        remote:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
                    end
                    task.wait(2.5 + math.random() * 1.5)
                end
            end)
        end
    end,
})

-- ====================
-- АВТОФАРМ
-- ====================
local statusLabel = FarmTab:CreateLabel("Статус: Очікування...")

task.spawn(function()
    while task.wait(0.35) do
        pcall(function()
            statusLabel:Set("Статус: " .. farmStatusText)
        end)
    end
end)

FarmTab:CreateSlider({
    Name = "Швидкість польоту",
    Range = { 50, 350 },
    Increment = 5,
    CurrentValue = 150,
    Flag = "FlySpeed_Slider",
    Callback = function(value) _G.FlySpeed = value end,
})

FarmTab:CreateSlider({
    Name = "Дистанція підбору",
    Range = { 2, 8 },
    Increment = 0.5,
    CurrentValue = 3.5,
    Flag = "PickupDistance_Slider",
    Callback = function(value) _G.PickupDistance = value end,
})

FarmTab:CreateToggle({
    Name = "Увімкнути ESP",
    CurrentValue = false,
    Flag = "ESP_Toggle",
    Callback = function(value) _G.ItemESP = value end,
})

FarmTab:CreateToggle({
    Name = "Увімкнути автофарм",
    CurrentValue = false,
    Flag = "ItemFarmToggle",
    Callback = function(value)
        _G.ItemFarm = value
        if not value then
            farmThreadActive = false
            setFarmStatus("Зупинено")
            stopFlight()
            return
        end

        if farmThreadActive then return end
        farmThreadActive = true

        task.spawn(function()
            setFarmStatus("Пошук предметів...")
            while _G.ItemFarm and farmThreadActive do
                local _, hrp = getCharacter()
                if not hrp then
                    setFarmStatus("Очікування персонажа...")
                    task.wait(0.5)
                    continue
                end

                local targetItem = getNearestItem(hrp)
                if not targetItem then
                    setFarmStatus("Предметів не знайдено")
                    task.wait(0.35)
                    continue
                end

                setFarmStatus("Лечу до: " .. targetItem.name)
                if moveToItemAndPickup(targetItem) then
                    banCoordinate(targetItem.position)
                    if espObjects[targetItem.part] then
                        pcall(function()
                            espObjects[targetItem.part]:Destroy()
                        end)
                        espObjects[targetItem.part] = nil
                    end
                    lastCacheRefresh = 0
                end

                task.wait(0.08)
            end

            farmThreadActive = false
            setFarmStatus("Зупинено")
            stopFlight()
        end)
    end,
})

FarmTab:CreateSection("Фільтр предметів")

FarmTab:CreateButton({
    Name = "Увімкнути всі предмети",
    Callback = function()
        for name in pairs(_G.SelectedItems) do
            _G.SelectedItems[name] = true
        end
        lastCacheRefresh = 0
    end,
})

FarmTab:CreateButton({
    Name = "Вимкнути всі предмети",
    Callback = function()
        for name in pairs(_G.SelectedItems) do
            _G.SelectedItems[name] = false
        end
        lastCacheRefresh = 0
    end,
})

local sortedItems = {}
for name in pairs(_G.SelectedItems) do
    table.insert(sortedItems, name)
end
table.sort(sortedItems)

for _, itemName in ipairs(sortedItems) do
    FarmTab:CreateToggle({
        Name = itemName,
        CurrentValue = false,
        Flag = "Filter_" .. itemName,
        Callback = function(value)
            _G.SelectedItems[itemName] = value
            lastCacheRefresh = 0
        end,
    })
end

-- ESP цикл (використовує кеш)
task.spawn(function()
    while true do
        task.wait(0.8)
        if _G.ItemESP then
            for _, item in ipairs(refreshItemCache()) do
                applyESP(item.part, item.name)
            end
        else
            clearESP()
        end
    end
end)

-- ====================
-- ІНШЕ
-- ====================
MiscTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "AntiAFK_Toggle",
    Callback = function(value)
        setAntiAfkEnabled(value)
    end,
})

MiscTab:CreateToggle({
    Name = "NoClip (окремо від фарму)",
    CurrentValue = false,
    Flag = "StandaloneNoClip_Toggle",
    Callback = function(value)
        _G.StandaloneNoClip = value
        if value then
            ensureNoClip()
        elseif not _G.ItemFarm and noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
    end,
})

MiscTab:CreateButton({
    Name = "Очистити заблоковані координати",
    Callback = function()
        table.clear(bannedCoordinates)
        lastCacheRefresh = 0
        Rayfield:Notify({
            Title = "UA Killer Hub",
            Content = "Чорний список координат очищено",
            Duration = 3,
        })
    end,
})

if shouldAutoLoad then
    pcall(function()
        local configPath = "UAKillerHub/YBA_Config.json"
        if (isfile and isfile(configPath)) or not isfile then
            Rayfield:LoadConfiguration()
        elseif writefile then
            writefile(autoLoadFile, "false")
        end
    end)
end

Rayfield:Notify({
    Title = "UA Killer Hub",
    Content = "Завантажено. ProximityPrompt bypass активний.",
    Duration = 4,
})
