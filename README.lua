- UA Killer Hub | YBA 
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local autoLoadFile = "UAKillerHub/YBA_AutoLoad.txt"
local configFile = "UAKillerHub/YBA_Config.json"
local shouldAutoLoad = false

-- =======================================================
-- АКТИВАЦІЯ ITEM MAGNITUDE BYPASS
-- =======================================================
if hookmetamethod and newcclosure and checkcaller and getcallingscript then
    local OldIndexItem;
    OldIndexItem = hookmetamethod(player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position or Vector3.zero, "__index", newcclosure(function(self, Key)
        if not checkcaller() and Key:lower() == 'magnitude' and getcallingscript().Name == "ItemSpawn" then
            return 0
        end
        return OldIndexItem(self, Key)
    end))
end

-- ====================================================
-- CRASH & WALKSPEED BYPASS
-- ====================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
pcall(function()
    local FunctionLibrary = require(ReplicatedStorage.Modules.FunctionLibrary)
    local OldPcall = FunctionLibrary.pcall

    FunctionLibrary.pcall = function(...)
        local args = {...}
        if type(args[1]) == 'function' and #getupvalues(args[1]) == 11 then
            return
        end
        return OldPcall(...)
    end
end)

-- Створення робочої папки
pcall(function()
    if makefolder and not isfolder("UAKillerHub") then
        makefolder("UAKillerHub")
    end
    if isfile and isfile(autoLoadFile) then
        shouldAutoLoad = (readfile(autoLoadFile) == "true")
    elseif writefile then
        writefile(autoLoadFile, "false")
    end
end)

-- ====================
-- ГЛОБАЛЬНІ НАЛАШТУВАННЯ
-- ====================
_G.AutoSell = false
_G.AutoEventCandy = false
_G.AutoBuy = false
_G.ItemFarm = false
_G.ItemESP = false
_G.FlySpeed = 150
_G.PickupDistance = 3.5
_G.AntiAFK = false
_G.StandaloneNoClip = false
_G.AutoRespawn = true

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
local JP_Value = 50

-- Словник елементів для фільтрації та зміни значень UI
local uiElementsRegistry = {}

-- ====================
-- ДОПОМІЖНІ ФУНКЦІЇ ФАРМУ
-- ====================
local function setFarmStatus(text)
    farmStatusText = text
end

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
    if not desc or not desc:IsA("ProximityPrompt") or not desc.Parent then
        return nil
    end

    local parent = desc.Parent
    local model = parent:IsA("Model") and parent or parent.Parent
    local itemName = ""

    if _G.SelectedItems[parent.Name] ~= nil then
        itemName = parent.Name
    elseif model and _G.SelectedItems[model.Name] ~= nil then
        itemName = model.Name
    elseif desc.ObjectText and _G.SelectedItems[desc.ObjectText] ~= nil then
        itemName = desc.ObjectText
    end

    if itemName == "" then
        return nil
    end

    local targetPart = parent:IsA("BasePart") and parent
        or parent:FindFirstChildWhichIsA("BasePart")
        or (model and model:FindFirstChildWhichIsA("BasePart"))

    if not targetPart or targetPart.Transparency >= 1 then
        return nil
    end
    if isCoordinateBanned(targetPart.Position) or isInvalidItemPart(targetPart) then
        return nil
    end
    if not desc.Enabled then
        return nil
    end

    return {
        prompt = desc,
        part = targetPart,
        parent = parent,
        name = itemName,
        position = targetPart.Position,
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

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local item = resolveItemFromPrompt(desc)
            if item and shouldFarmItem(item.name) then
                table.insert(itemCache, item)
            end
        end
    end

    return itemCache
end

local function getNearestItem(hrp)
    local nearest
    local shortest = math.huge

    for _, item in ipairs(refreshItemCache()) do
        if item.prompt:IsDescendantOf(workspace) and not isInvalidItemPart(item.parent) then
            local dist = (hrp.Position - item.position).Magnitude
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
    if not part or part.Transparency == 1 or isCoordinateBanned(part.Position) or isInvalidItemPart(part) then
        return
    end

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
    text.TextColor3 = Color3.fromRGB(139, 124, 246)
    text.TextSize = 13
    text.Font = Enum.Font.GothamBold
    text.TextStrokeTransparency = 0

    bgui.Parent = part
    espObjects[part] = bgui
end

local function clearESP()
    for part, gui in pairs(espObjects) do
        if gui then gui:Destroy() end
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
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
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
        flightState.cframeValue:Destroy()
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
                part.CanCollide = false
            end
        end
    end)
end

local function moveToItemAndPickup(item)
    if not item or not item.part or not item.part:IsDescendantOf(workspace) then
        return false
    end
    if not item.prompt or not item.prompt:IsDescendantOf(workspace) then
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

    local targetCFrame = CFrame.new(item.part.Position + Vector3.new(0, 1.2, 0))
    local distance = (targetCFrame.Position - hrp.Position).Magnitude
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

        currentHrp.CFrame = cframeValue.Value
        zeroHrpVelocity(currentHrp)

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= currentHrp then
                part.CanCollide = false
            end
        end
    end)

    flightState = {
        cframeValue = cframeValue,
        tween = tween,
        heartbeatConn = heartbeatConn,
    }

    local function shouldContinue()
        return _G.ItemFarm
            and item.part:IsDescendantOf(workspace)
            and not isInvalidItemPart(item.part)
            and item.prompt:IsDescendantOf(workspace)
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
        if not hrp or not hrp.Parent then
            cleanupFlight()
            return false
        end
        RunService.Heartbeat:Wait()
    end

    if not shouldContinue() then
        cleanupFlight()
        return false
    end

    targetCFrame = CFrame.new(item.part.Position + Vector3.new(0, 1.2, 0))
    cframeValue.Value = targetCFrame

    local currentHrp = char:FindFirstChild("HumanoidRootPart")
    if currentHrp then
        currentHrp.CFrame = targetCFrame
        zeroHrpVelocity(currentHrp)
    end

    task.wait(0.03)

    if shouldContinue() then
        item.prompt.RequiresLineOfSight = false
        item.prompt.HoldDuration = 0
        if fireproximityprompt then
            fireproximityprompt(item.prompt, 0)
        end
    end

    local pickedUp = not item.prompt:IsDescendantOf(workspace) or isInvalidItemPart(item.parent)

    cleanupFlight()
    return pickedUp
end

local function tryRespawn()
    if not _G.AutoRespawn then return end
    local _, _, hum = getCharacter()
    if hum and hum.Health <= 0 then
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("Remotes")
            remote = remote and remote:FindFirstChild("LoadCharacter")
            if remote then remote:FireServer() end
        end)
    end
end

-- =======================================================
-- МАГАЗИН ТА ІВЕНТ (НАДІЙНИЙ АВТОПРОДАЖ І ЗДАЧА ЦУКЕРОК)
-- =======================================================
local DontSell = {
    ["Lucky Arrow"] = true,
    ["Christmas Present"] = true,
    ["Green Candy"] = true,
    ["Yellow Candy"] = true,
    ["Blue Candy"] = true,
    ["Red Candy"] = true,
    ["Lucky Stone Mask"] = true
}

local EventCandies = {
    ["Green Candy"] = true,
    ["Yellow Candy"] = true,
    ["Blue Candy"] = true,
    ["Red Candy"] = true,
}

local sellQueue = {}
local isBusy = false

local function getMerchant()
    local dialogue = ReplicatedStorage:FindFirstChild("Dialogue")
    return dialogue and dialogue:FindFirstChild("Merchant")
end

local function getEventNPC()
    local dialogue = ReplicatedStorage:FindFirstChild("Dialogue")
    return dialogue and dialogue:FindFirstChild("Halloween Event")
end

local function getDialogueGui()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    return playerGui:FindFirstChild("DialogueGui") 
        or playerGui:FindFirstChild("Dialogue") 
        or playerGui:FindFirstChild("DialogueBox")
end

-- Перевірка, чи предмет дійсно зник з інвентаря (проданий)
local function isItemSold(item)
    if not item then return true end
    if not item.Parent then return true end
    if not item:IsDescendantOf(game) then return true end
    local char = player.Character
    local backpack = player:FindFirstChild("Backpack")
    -- Якщо предмет ще є в руках або в бекпаку — він НЕ проданий
    if (backpack and item:IsDescendantOf(backpack)) or (char and item:IsDescendantOf(char)) then
        return false
    end
    return true
end

-- Натискання торгових кнопок у діалозі торговця
local function autoClickDialogueButtons()
    local dialogueGui = getDialogueGui()
    if not dialogueGui then return end

    for _, btn in ipairs(dialogueGui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then 
                txt = childText.Text 
            end
            local lower = txt:lower()
            if lower:find("sell this") or lower:find("i'd like to sell") or lower:find("deal") or lower:find("all") then
                pcall(function()
                    if firesignal then 
                        firesignal(btn.MouseButton1Click) 
                        firesignal(btn.Activated)
                    else 
                        btn.Activated:Fire() 
                    end
                end)
            end
        end
    end
end

-- Коректне закриття вікна торговця після завершення продажів
local function closeMerchantDialogue()
    local char = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")

    pcall(function()
        if remote then
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("DialogueEnd", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("EndDialogue", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Merchant" })
        end
    end)

    local dialogueGui = getDialogueGui()
    if dialogueGui then
        pcall(function()
            for _, btn in ipairs(dialogueGui:GetDescendants()) do
                if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
                    local txt = btn.Text or ""
                    local childText = btn:FindFirstChildOfClass("TextLabel")
                    if childText and childText.Text ~= "" then 
                        txt = childText.Text 
                    end
                    local lower = txt:lower()
                    if lower:find("nevermind") or lower:find("nothing") or lower:find("bye") or lower:find("leave") or lower:find("no") or lower:find("exit") or lower:find("close") or lower:find("goodbye") then
                        if firesignal then
                            firesignal(btn.MouseButton1Click)
                            firesignal(btn.Activated)
                        else
                            btn.Activated:Fire()
                        end
                    end
                end
            end
        end)

        task.wait(0.12)
        if dialogueGui:IsA("ScreenGui") and dialogueGui.Enabled then
            pcall(function() dialogueGui.Enabled = false end)
        end
    end
end

-- Продаж одного конкретного предмета з очікуванням підтвердження
local function sellSingleItem(item)
    if not item or isItemSold(item) or DontSell[item.Name] then 
        return true, "AlreadySold" 
    end

    local char, _, hum = getCharacter()
    local remote = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()

    if not hum or not remote or not merchant then
        return false, "MissingCharacterOrNPC"
    end

    -- 1. Екіпіруємо предмет
    hum:EquipTool(item)
    local equipTimeout = tick() + 0.8
    while tick() < equipTimeout and item.Parent ~= char do
        task.wait(0.04)
    end
    if item.Parent ~= char then
        return false, "EquipTimeout"
    end

    task.wait(0.12)

    -- 2. Запит початку діалогу
    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.12)
    autoClickDialogueButtons()

    -- 3. Обираємо варіант продажу
    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue1", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    -- 4. Підтверджуємо угоду ("Deal")
    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    -- 5. Чекаємо, доки сервер забере предмет з інвентаря
    local sellTimeout = tick() + 1.2
    while tick() < sellTimeout do
        if isItemSold(item) then break end
        autoClickDialogueButtons()
        task.wait(0.08)
    end

    -- 6. Завершуємо крок діалогу
    pcall(function()
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
        remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
        remote:FireServer("DialogueEnd", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
    end)
    task.wait(0.1)

    if isItemSold(item) then
        return true, "Success"
    else
        return false, "ItemStillExists"
    end
end

-- Продаж із обмеженою кількістю спроб (макс. 3)
local function sellSingleItemWithRetries(item, maxRetries)
    maxRetries = maxRetries or 3
    local lastError = "Unknown"

    for attempt = 1, maxRetries do
        if isItemSold(item) then return true, "Success" end

        local ok, errStage = sellSingleItem(item)
        if ok then
            return true, "Success"
        end

        lastError = errStage
        print(string.format("[UA Killer Hub | AutoSell] Спроба %d/%d для '%s' не вдалася: %s", attempt, maxRetries, item.Name, tostring(errStage)))
        task.wait(0.2)
    end

    return false, lastError
end

-- Перевірка та черга продажу
local function isItemInQueue(item)
    for _, qItem in ipairs(sellQueue) do
        if qItem == item then return true end
    end
    return false
end

local function queueItemForSale(item)
    if not item or not item:IsA("Tool") or DontSell[item.Name] then return end
    if isItemSold(item) then return end
    if isItemInQueue(item) then return end
    table.insert(sellQueue, item)
end

local function syncSellQueue()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            queueItemForSale(item)
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] then
                queueItemForSale(item)
            end
        end
    end
end

local function hasSellableItems()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] then return true end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] then return true end
        end
    end
    return false
end

local function setupBackpackListener(backpack)
    for _, item in ipairs(backpack:GetChildren()) do
        queueItemForSale(item)
    end
    backpack.ChildAdded:Connect(function(item)
        task.wait(0.2)
        if _G.AutoSell then
            queueItemForSale(item)
        end
    end)
end

player.ChildAdded:Connect(function(child)
    if child.Name == "Backpack" then setupBackpackListener(child) end
end)
if player:FindFirstChild("Backpack") then setupBackpackListener(player.Backpack) end

local function countTotalCandies()
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return 0 end
    
    local count = 0
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and EventCandies[item.Name] then
            count = count + 1
        end
    end
    return count
end

local function clickEventCandyOption()
    local dialogueGui = getDialogueGui()
    if not dialogueGui then return false end

    for _, btn in ipairs(dialogueGui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then 
                txt = childText.Text 
            end
            
            local lowerTxt = txt:lower()
            if lowerTxt:find("turn in") or lowerTxt:find("candy") and not lowerTxt:find("what do i do") and not lowerTxt:find("could you please") then
                pcall(function()
                    if firesignal then 
                        firesignal(btn.MouseButton1Click) 
                        firesignal(btn.Activated)
                    else 
                        btn.Activated:Fire() 
                    end
                end)
                return true
            end
        end
    end
    return false
end

local function findJackDialogue()
    local dialogueGui = getDialogueGui()
    if not dialogueGui then return nil end

    local hasJack = false
    local hasPoints = false
    local continueElem = nil
    local pointsElem = nil
    local fallbackFrame = nil

    for _, desc in ipairs(dialogueGui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local txt = desc.Text or ""
            local lower = txt:lower()

            if lower:find("jack") or lower:find("cauldron specter") then
                hasJack = true
            end
            if lower:find("point") then
                hasPoints = true
                pointsElem = desc
            end
            if lower:find("click to continue") then
                continueElem = desc
            end
        end
        if desc:IsA("Frame") and desc.Visible and desc.AbsoluteSize.Y > 50 then
            fallbackFrame = desc
        end
    end

    local isGuiVisible = dialogueGui:IsA("ScreenGui") and dialogueGui.Enabled or dialogueGui.Visible
    if isGuiVisible and (hasJack or hasPoints) then
        return {
            gui = dialogueGui,
            hasJack = hasJack,
            hasPoints = hasPoints,
            continueElem = continueElem,
            pointsElem = pointsElem,
            fallbackFrame = fallbackFrame,
        }
    end

    return nil
end

local function clickContinueButton(targetElement)
    pcall(function()
        if not targetElement then return end

        if targetElement:IsA("GuiButton") then
            if firesignal then
                firesignal(targetElement.MouseButton1Click)
                firesignal(targetElement.Activated)
            else
                targetElement.Activated:Fire()
            end
        end

        if VirtualInputManager and targetElement:IsA("GuiObject") then
            local absPos = targetElement.AbsolutePosition
            local absSize = targetElement.AbsoluteSize
            local clickX = absPos.X + (absSize.X / 2)
            local clickY = absPos.Y + (absSize.Y / 2)

            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end
    end)
end

local function submitAllCandies()
    local char, _, hum = getCharacter()
    local remote = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()

    if not remote or not hum or not eventNPC then
        print("[UA Killer Hub | Event] Помилка: Персонаж або NPC не знайдені.")
        return false
    end

    local success = false
    pcall(function()
        print("[UA Killer Hub | Event] Взаємодія з Jack, The Cauldron Specter...")
        remote:FireServer("PromptTriggered", eventNPC)

        local optionFound = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy do
            if clickEventCandyOption() then
                optionFound = true
                print("[UA Killer Hub | Event] Опцію 'Turn in candy' успішно натиснуто.")
                break
            end
            task.wait(0.15)
        end

        if not optionFound then
            print("[UA Killer Hub | Event] Опцію здачі цукерок не знайдено (таймаут).")
            return
        end

        print("[UA Killer Hub | Event] Очікування повідомлення про очки...")
        local pointsFound = false
        local jackData = nil
        local waitPointsTimeout = tick() + 4.0

        while tick() < waitPointsTimeout and _G.AutoEventCandy do
            jackData = findJackDialogue()
            if jackData and jackData.hasPoints then
                pointsFound = true
                local msg = jackData.pointsElem and jackData.pointsElem.Text or "Очки отримано"
                print(string.format("[UA Killer Hub | Event] Знайдено діалог: '%s'", msg))
                break
            end
            task.wait(0.15)
        end

        if not pointsFound or not jackData then
            print("[UA Killer Hub | Event] Повідомлення про очки не з'явилося.")
            return
        end

        task.wait(0.3)

        local clickTarget = jackData.continueElem or jackData.pointsElem or jackData.fallbackFrame
        if clickTarget then
            print("[UA Killer Hub | Event] Закриваємо діалог через клік по елементу: " .. clickTarget.Name)
            clickContinueButton(clickTarget)

            local closeTimeout = tick() + 1.5
            local isClosed = false
            while tick() < closeTimeout do
                task.wait(0.15)
                local check = findJackDialogue()
                if not check then
                    isClosed = true
                    break
                end
            end

            if isClosed then
                print("[UA Killer Hub | Event] Діалог Jack успішно закрито!")
                success = true
            else
                print("[UA Killer Hub | Event] Повторна спроба закриття діалогу...")
                clickContinueButton(clickTarget)
                task.wait(0.2)
            end
        end
    end)

    return success
end

-- Головний потік автопродажу та здачі цукерок
task.spawn(function()
    while true do
        task.wait(0.3)
        if isBusy then continue end

        -- 1. АВТО-ЗДАЧА ЦУКЕРОК
        if _G.AutoEventCandy and countTotalCandies() >= 10 then
            isBusy = true
            closeMerchantDialogue() -- Усуваємо можливий конфлікт із відкритим торговцем

            while countTotalCandies() > 0 and _G.AutoEventCandy do
                submitAllCandies()
                task.wait(0.5)
            end

            isBusy = false
            continue
        end

        -- 2. АВТОПРОДАЖ ПРЕДМЕТІВ
        if _G.AutoSell and (#sellQueue > 0 or hasSellableItems()) then
            isBusy = true
            syncSellQueue()

            while _G.AutoSell and #sellQueue > 0 do
                local item = table.remove(sellQueue, 1)
                if item and not isItemSold(item) and not DontSell[item.Name] then
                    local success, errStage = sellSingleItemWithRetries(item, 3)
                    if success then
                        print(string.format("[UA Killer Hub | AutoSell] Успішно продано: '%s'", item.Name))
                    else
                        print(string.format("[UA Killer Hub | AutoSell] Не вдалося продати '%s'. Етап помилки: %s", item.Name, tostring(errStage)))
                    end
                    task.wait(0.15)
                end
            end

            -- Закриваємо вікно торговця після повного завершення черги
            closeMerchantDialogue()
            isBusy = false
        end
    end
end)

local function applyJumpPower()
    local _, _, hum = getCharacter()
    if hum then hum.JumpPower = JP_Value end
end

player.CharacterAdded:Connect(function(newChar)
    task.wait(0.5)
    applyJumpPower()
    newChar.ChildAdded:Connect(function(item)
        task.wait(0.2)
        if _G.AutoSell and item:IsA("Tool") and not DontSell[item.Name] then
            queueItemForSale(item)
        end
    end)
end)

if player.Character then
    player.Character.ChildAdded:Connect(function(item)
        task.wait(0.2)
        if _G.AutoSell and item:IsA("Tool") and not DontSell[item.Name] then
            queueItemForSale(item)
        end
    end)
end

task.spawn(function()
    while task.wait(0.2) do
        applyJumpPower()
    end
end)

-- ESP цикл
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

-- =======================================================
-- MONHUB СТИЛЬ: ВЛАСНА БІБЛІОТЕКА ІНТЕРФЕЙСУ
-- =======================================================
local OldGui = (gethui and gethui():FindFirstChild("UAKillerHub_GUI")) or CoreGui:FindFirstChild("UAKillerHub_GUI")
if OldGui then OldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UAKillerHub_GUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

if gethui then
    ScreenGui.Parent = gethui()
else
    pcall(function() ScreenGui.Parent = CoreGui end)
    if not ScreenGui.Parent then ScreenGui.Parent = player:WaitForChild("PlayerGui") end
end

-- Основне вікно (520x400)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 400)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(38, 42, 53)
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Контейнер сповіщень (Toasts)
local ToastContainer = Instance.new("Frame")
ToastContainer.Name = "ToastContainer"
ToastContainer.Size = UDim2.new(0, 240, 1, -20)
ToastContainer.Position = UDim2.new(1, -250, 0, 10)
ToastContainer.BackgroundTransparency = 1
ToastContainer.Parent = ScreenGui

local function showNotification(title, message, duration)
    duration = duration or 3
    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(1, 0, 0, 55)
    toast.BackgroundColor3 = Color3.fromRGB(27, 30, 38)
    toast.BackgroundTransparency = 1
    toast.BorderSizePixel = 0
    toast.Parent = ToastContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = toast

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(139, 124, 246)
    stroke.Thickness = 1
    stroke.Transparency = 1
    stroke.Parent = toast

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -16, 0, 20)
    titleLbl.Position = UDim2.new(0, 10, 0, 6)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = title
    titleLbl.TextColor3 = Color3.fromRGB(139, 124, 246)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.TextTransparency = 1
    titleLbl.Parent = toast

    local msgLbl = Instance.new("TextLabel")
    msgLbl.Size = UDim2.new(1, -16, 0, 22)
    msgLbl.Position = UDim2.new(0, 10, 0, 26)
    msgLbl.BackgroundTransparency = 1
    msgLbl.Text = message
    msgLbl.TextColor3 = Color3.fromRGB(200, 205, 215)
    msgLbl.Font = Enum.Font.Gotham
    msgLbl.TextSize = 11
    msgLbl.TextXAlignment = Enum.TextXAlignment.Left
    msgLbl.TextTransparency = 1
    msgLbl.Parent = toast

    TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
    TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0 }):Play()
    TweenService:Create(titleLbl, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    TweenService:Create(msgLbl, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()

    task.delay(duration, function()
        TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
        TweenService:Create(titleLbl, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        local tw = TweenService:Create(msgLbl, TweenInfo.new(0.25), { TextTransparency = 1 })
        tw:Play()
        tw.Completed:Wait()
        toast:Destroy()
    end)
end

-- Верхня панель (TitleBar)
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(19, 21, 26)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 10)
TitleBarCorner.Parent = TitleBar

local TitleLine = Instance.new("Frame")
TitleLine.Size = UDim2.new(1, 0, 0, 1)
TitleLine.Position = UDim2.new(0, 0, 1, -1)
TitleLine.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
TitleLine.BorderSizePixel = 0
TitleLine.Parent = TitleBar

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(0, 140, 1, 0)
TitleText.Position = UDim2.new(0, 14, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "UA Killer Hub"
TitleText.Font = Enum.Font.GothamBold
TitleText.TextSize = 14
TitleText.TextColor3 = Color3.fromRGB(240, 242, 245)
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = TitleBar

local Badge = Instance.new("TextLabel")
Badge.Size = UDim2.new(0, 36, 0, 18)
Badge.Position = UDim2.new(0, 126, 0.5, -9)
Badge.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
Badge.Text = "YBA"
Badge.Font = Enum.Font.GothamBold
Badge.TextSize = 10
Badge.TextColor3 = Color3.fromRGB(255, 255, 255)
Badge.Parent = TitleBar

local BadgeCorner = Instance.new("UICorner")
BadgeCorner.CornerRadius = UDim.new(0, 4)
BadgeCorner.Parent = Badge

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.TextColor3 = Color3.fromRGB(160, 165, 175)
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 26, 0, 26)
MinBtn.Position = UDim2.new(1, -66, 0.5, -13)
MinBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
MinBtn.Text = "—"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.TextColor3 = Color3.fromRGB(160, 165, 175)
MinBtn.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 520, 0, 42) }):Play()
    else
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 520, 0, 400) }):Play()
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    showNotification("UA Killer Hub", "Натисніть RightShift, щоб показати меню", 3.5)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ====================
-- САЙДБАР (БІЧНЕ МЕНЮ)
-- ====================
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 130, 1, -42)
Sidebar.Position = UDim2.new(0, 0, 0, 42)
Sidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarList = Instance.new("UIListLayout")
SidebarList.Padding = UDim.new(0, 6)
SidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarList.SortOrder = Enum.SortOrder.LayoutOrder
SidebarList.Parent = Sidebar

local SidebarPad = Instance.new("UIPadding")
SidebarPad.PaddingTop = UDim.new(0, 12)
SidebarPad.PaddingLeft = UDim.new(0, 6)
SidebarPad.PaddingRight = UDim.new(0, 6)
SidebarPad.Parent = Sidebar

-- ====================
-- ОСНОВНА ПАНЕЛЬ КОНТЕНТУ
-- ====================
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -130, 1, -42)
ContentArea.Position = UDim2.new(0, 130, 0, 42)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local SearchFrame = Instance.new("Frame")
SearchFrame.Name = "SearchFrame"
SearchFrame.Size = UDim2.new(1, -24, 0, 32)
SearchFrame.Position = UDim2.new(0, 12, 0, 10)
SearchFrame.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
SearchFrame.BorderSizePixel = 0
SearchFrame.Parent = ContentArea

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 6)
SearchCorner.Parent = SearchFrame

local SearchIcon = Instance.new("TextLabel")
SearchIcon.Size = UDim2.new(0, 24, 1, 0)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Text = "🔍"
SearchIcon.Font = Enum.Font.Gotham
SearchIcon.TextSize = 11
SearchIcon.TextColor3 = Color3.fromRGB(150, 155, 165)
SearchIcon.Parent = SearchFrame

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(1, -30, 1, 0)
SearchBox.Position = UDim2.new(0, 28, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.PlaceholderText = "Пошук функцій..."
SearchBox.PlaceholderColor3 = Color3.fromRGB(110, 115, 130)
SearchBox.TextColor3 = Color3.fromRGB(240, 242, 245)
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 12
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = SearchFrame

local PagesFolder = Instance.new("Folder")
PagesFolder.Name = "Pages"
PagesFolder.Parent = ContentArea

local tabs = {}
local activeTab = nil

local function filterItems(query)
    query = query:lower()
    for _, item in ipairs(uiElementsRegistry) do
        if item.Page == activeTab then
            if query == "" or item.Name:lower():find(query, 1, true) then
                item.Frame.Visible = true
            else
                item.Frame.Visible = false
            end
        end
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    filterItems(SearchBox.Text)
end)

local function switchTab(tabName)
    activeTab = tabName
    SearchBox.Text = ""
    for name, tabData in pairs(tabs) do
        if name == tabName then
            tabData.Page.Visible = true
            TweenService:Create(tabData.Button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(139, 124, 246),
                TextColor3 = Color3.fromRGB(255, 255, 255)
            }):Play()
        else
            tabData.Page.Visible = false
            TweenService:Create(tabData.Button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(23, 25, 32),
                TextColor3 = Color3.fromRGB(150, 155, 165)
            }):Play()
        end
    end
    filterItems("")
end

local function createTab(tabName, iconText)
    local btn = Instance.new("TextButton")
    btn.Name = tabName .. "_Tab"
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Color3.fromRGB(23, 25, 32)
    btn.Text = (iconText or "•") .. "  " .. tabName
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(150, 155, 165)
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = Sidebar

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.Parent = btn

    local page = Instance.new("ScrollingFrame")
    page.Name = tabName .. "_Page"
    page.Size = UDim2.new(1, -24, 1, -56)
    page.Position = UDim2.new(0, 12, 0, 48)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Color3.fromRGB(139, 124, 246)
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = PagesFolder

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 8)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = page

    local pagePad = Instance.new("UIPadding")
    pagePad.PaddingRight = UDim.new(0, 4)
    pagePad.PaddingBottom = UDim.new(0, 10)
    pagePad.Parent = page

    tabs[tabName] = { Button = btn, Page = page }

    btn.MouseButton1Click:Connect(function()
        switchTab(tabName)
    end)

    return page
end

-- ====================
-- ФУНКЦІЇ СТВОРЕННЯ ЕЛЕМЕНТІВ UI
-- ====================
local function createSection(page, tabName, text)
    local sec = Instance.new("Frame")
    sec.Size = UDim2.new(1, 0, 0, 24)
    sec.BackgroundTransparency = 1
    sec.Parent = page

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text:upper()
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextColor3 = Color3.fromRGB(139, 124, 246)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = sec

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = sec })
    return sec
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local toggleState = defaultVal or false

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel = 0
    card.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -56, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = text
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(230, 233, 240)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local switch = Instance.new("TextButton")
    switch.Size = UDim2.new(0, 36, 0, 20)
    switch.Position = UDim2.new(1, -44, 0.5, -10)
    switch.BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58)
    switch.Text = ""
    switch.Parent = card

    local switchCorner = Instance.new("UICorner")
    switchCorner.CornerRadius = UDim.new(1, 0)
    switchCorner.Parent = switch

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = switch

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function setState(val, triggerCallback)
        toggleState = val
        local targetColor = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58)
        local targetPos = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)

        TweenService:Create(switch, TweenInfo.new(0.2), { BackgroundColor3 = targetColor }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), { Position = targetPos }):Play()

        if triggerCallback and callback then
            callback(toggleState)
        end
    end

    switch.MouseButton1Click:Connect(function()
        setState(not toggleState, true)
    end)

    local controlObj = {
        Name = text,
        Page = tabName,
        Frame = card,
        Set = function(self, val)
            setState(val, true)
        end,
        Get = function()
            return toggleState
        end
    }

    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createSlider(page, tabName, text, min, max, step, defaultVal, callback)
    local currentVal = defaultVal or min

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 48)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel = 0
    card.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -60, 0, 20)
    title.Position = UDim2.new(0, 12, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = text
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(230, 233, 240)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0, 46, 0, 20)
    valLabel.Position = UDim2.new(1, -54, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = tostring(currentVal)
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextSize = 11
    valLabel.TextColor3 = Color3.fromRGB(139, 124, 246)
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent = card

    local bar = Instance.new("TextButton")
    bar.Size = UDim2.new(1, -24, 0, 6)
    bar.Position = UDim2.new(0, 12, 0, 32)
    bar.BackgroundColor3 = Color3.fromRGB(42, 46, 58)
    bar.Text = ""
    bar.Parent = card

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(math.clamp((currentVal - min) / (max - min), 0, 1), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local draggingSlider = false

    local function updateFromPos(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local raw = min + ((max - min) * rel)
        local stepped = math.floor(raw / step + 0.5) * step
        if step < 1 then
            stepped = tonumber(string.format("%.1f", stepped))
        end
        currentVal = math.clamp(stepped, min, max)

        valLabel.Text = tostring(currentVal)
        fill.Size = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)

        if callback then
            callback(currentVal)
        end
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            updateFromPos(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromPos(input.Position.X)
        end
    end)

    local controlObj = {
        Name = text,
        Page = tabName,
        Frame = card,
        Set = function(self, val)
            currentVal = math.clamp(val, min, max)
            valLabel.Text = tostring(currentVal)
            fill.Size = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
            if callback then callback(currentVal) end
        end,
        Get = function() return currentVal end
    }

    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createButton(page, tabName, text, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel = 0
    card.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(240, 242, 245)
    btn.Parent = card

    btn.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(36, 40, 52) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        task.wait(0.08)
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
        if callback then callback() end
    end)

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return btn
end

local function createStatusLabel(page, tabName, initialText)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 34)
    card.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    card.BorderSizePixel = 0
    card.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(42, 46, 58)
    stroke.Thickness = 1
    stroke.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = initialText
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextColor3 = Color3.fromRGB(139, 124, 246)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    table.insert(uiElementsRegistry, { Name = "Статус", Page = tabName, Frame = card })

    return {
        Set = function(self, txt)
            lbl.Text = txt
        end
    }
end

-- ====================
-- СТВОРЕННЯ СТОРІНОК ТА ЕЛЕМЕНТІВ
-- ====================
local mainPage = createTab("Головна", "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин", "🛒")
local miscPage = createTab("Інше", "⚙")

local itemToggleControls = {}

-- 1. СТОРІНКА ГОЛОВНА
createSection(mainPage, "Головна", "Конфігурація")

createToggle(mainPage, "Головна", "Автозавантаження при старті", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    pcall(function()
        if writefile then writefile(autoLoadFile, tostring(value)) end
    end)
end)

local function saveCurrentConfig()
    pcall(function()
        local cfg = {
            SelectedItems = _G.SelectedItems,
            FlySpeed = _G.FlySpeed,
            PickupDistance = _G.PickupDistance,
            JumpPower = JP_Value,
            AutoRespawn = _G.AutoRespawn
        }
        if writefile then
            writefile(configFile, HttpService:JSONEncode(cfg))
            showNotification("Успіх", "Налаштування конфігу збережено!", 3)
        end
    end)
end

local function loadCurrentConfig()
    pcall(function()
        if isfile and isfile(configFile) then
            local data = HttpService:JSONDecode(readfile(configFile))
            if data.SelectedItems then
                _G.SelectedItems = data.SelectedItems
                for item, state in pairs(_G.SelectedItems) do
                    if itemToggleControls[item] then
                        itemToggleControls[item]:Set(state)
                    end
                end
            end
            if data.FlySpeed then _G.FlySpeed = data.FlySpeed end
            if data.PickupDistance then _G.PickupDistance = data.PickupDistance end
            if data.JumpPower then JP_Value = data.JumpPower end
            if data.AutoRespawn ~= nil then _G.AutoRespawn = data.AutoRespawn end
            showNotification("Конфіг", "Налаштування успішно завантажено!", 3)
        end
    end)
end

createButton(mainPage, "Головна", "Завантажити конфіг вручну", loadCurrentConfig)
createButton(mainPage, "Головна", "Зберегти поточний конфіг", saveCurrentConfig)

createSection(mainPage, "Головна", "Характеристики")

createSlider(mainPage, "Головна", "Висота стрибка (JumpPower)", 50, 200, 1, JP_Value, function(val)
    JP_Value = val
    applyJumpPower()
end)

-- 2. СТОРІНКА АВТОФАРМ
createSection(farmPage, "Автофарм", "Основні параметри")

local statusLabel = createStatusLabel(farmPage, "Автофарм", "Статус: Очікування...")

task.spawn(function()
    while task.wait(0.35) do
        pcall(function()
            statusLabel:Set("Статус: " .. farmStatusText)
        end)
    end
end)

createSlider(farmPage, "Автофарм", "Швидкість польоту", 50, 350, 5, _G.FlySpeed, function(val)
    _G.FlySpeed = val
end)

createSlider(farmPage, "Автофарм", "Дистанція підбору", 2, 8, 0.5, _G.PickupDistance, function(val)
    _G.PickupDistance = val
end)

createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    _G.ItemESP = val
end)

createToggle(farmPage, "Автофарм", "Увімкнути автофарм", _G.ItemFarm, function(value)
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
            tryRespawn()

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
                    espObjects[targetItem.part]:Destroy()
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
end)

createSection(farmPage, "Автофарм", "Фільтр предметів")

createButton(farmPage, "Автофарм", "Увімкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = true
        if itemToggleControls[name] then
            itemToggleControls[name]:Set(true)
        end
    end
    lastCacheRefresh = 0
end)

createButton(farmPage, "Автофарм", "Вимкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = false
        if itemToggleControls[name] then
            itemToggleControls[name]:Set(false)
        end
    end
    lastCacheRefresh = 0
end)

local sortedItems = {}
for name in pairs(_G.SelectedItems) do
    table.insert(sortedItems, name)
end
table.sort(sortedItems)

for _, itemName in ipairs(sortedItems) do
    local ctrl = createToggle(farmPage, "Автофарм", itemName, _G.SelectedItems[itemName], function(val)
        _G.SelectedItems[itemName] = val
        lastCacheRefresh = 0
    end)
    itemToggleControls[itemName] = ctrl
end

-- 3. СТОРІНКА МАГАЗИН
createSection(shopPage, "Магазин", "Торгівля та івенти")

createToggle(shopPage, "Магазин", "Автопродаж (крім Lucky Arrow)", _G.AutoSell, function(value)
    _G.AutoSell = value
    if value then
        syncSellQueue()
    else
        table.clear(sellQueue)
        closeMerchantDialogue()
    end
end)

createToggle(shopPage, "Магазин", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    _G.AutoEventCandy = value
end)

createToggle(shopPage, "Магазин", "Автокупівля (Lucky Arrow)", _G.AutoBuy, function(value)
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
end)

-- 4. СТОРІНКА ІНШЕ
createSection(miscPage, "Інше", "Додаткові функції")

createToggle(miscPage, "Інше", "Anti-AFK", _G.AntiAFK, function(value)
    _G.AntiAFK = value
    if antiAfkConnection then
        antiAfkConnection:Disconnect()
        antiAfkConnection = nil
    end
    if value then
        antiAfkConnection = player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

createToggle(miscPage, "Інше", "NoClip (окремо від фарму)", _G.StandaloneNoClip, function(value)
    _G.StandaloneNoClip = value
    if value then
        ensureNoClip()
    elseif not _G.ItemFarm and noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end)

createToggle(miscPage, "Інше", "Авто-респawn при смерті", _G.AutoRespawn, function(value)
    _G.AutoRespawn = value
end)

createButton(miscPage, "Інше", "Очистити заблоковані координати", function()
    table.clear(bannedCoordinates)
    lastCacheRefresh = 0
    showNotification("UA Killer Hub", "Чорний список координат очищено", 3)
end)

-- Ініціалізація та показ першої вкладки
switchTab("Головна")

task.spawn(function()
    if shouldAutoLoad then
        task.wait(1.5)
        loadCurrentConfig()
    end
end)

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
