local lp = game.Players.LocalPlayer
local vim = game:GetService("VirtualInputManager")

-- НАЛАШТУВАННЯ КООРДИНАТ КНОПКИ PLAY
local PLAY_X, PLAY_Y = 132, 265 

local coreGui = game:GetService("CoreGui")
if coreGui:FindFirstChild("YBA_Play_Only") then coreGui.YBA_Play_Only:Destroy() end

local sg = Instance.new("ScreenGui", coreGui)
sg.Name = "YBA_Play_Only"

-- Головне вікно логу
local log = Instance.new("TextLabel", sg)
log.Size = UDim2.new(0.6, 0, 0.08, 0)
log.Position = UDim2.new(0.2, 0, 0.05, 0)
log.BackgroundColor3 = Color3.new(0, 0, 0)
log.TextColor3 = Color3.new(0, 1, 1)
log.TextScaled = true
log.Text = "СИСТЕМА ГОТОВА"

-- Кнопка скасування (Хрестик)
local closeBtn = Instance.new("TextButton", log)
closeBtn.Size = UDim2.new(0.1, 0, 1, 0)
closeBtn.Position = UDim2.new(1, 5, 0, 0)
closeBtn.BackgroundColor3 = Color3.new(0.7, 0, 0)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.TextScaled = true
local corner = Instance.new("UICorner", closeBtn)

-- Логіка зупинки
local isRunning = true
closeBtn.MouseButton1Click:Connect(function()
    isRunning = false
    sg:Destroy()
    print("Автоматизація PLAY зупинена.")
end)

-- Функція кліку
local function clickPlay(x, y)
    if not isRunning then return end
    
    -- Симуляція кліку мишкою
    vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait(0.4) 
    vim:SendMouseButtonEvent(x, y, 0, false, game, 1)
    
    -- Симуляція тапу (про всяк випадок для мобільних/емуляторів)
    pcall(function()
        vim:SendTouchTapEvent(x, y)
    end)
    task.wait(0.5)
end

-- Головний потік
task.spawn(function()
    -- 1. Таймер відліку перед стартом (15 секунд)
    for i = 15, 1, -1 do
        if not isRunning then return end
        log.Text = "⏳ ЗАПУСК АВТО-PLAY ЧЕРЕЗ: " .. i
        task.wait(1)
    end
    
    if not isRunning then return end
    log.Text = "🚀 ТИСНУ PLAY..."
    
    -- 2. Спроби натиснути кнопку (5 разів з інтервалом)
    for i = 1, 1 do
        if not isRunning then break end
        
        -- Надсилаємо серверний сигнал про натискання
        pcall(function()
            if lp.Character and lp.Character:FindFirstChild("RemoteEvent") then
                lp.Character.RemoteEvent:FireServer("PressedPlay")
            end
        end)
        
        -- Клікаємо віртуальною мишкою за координатами
        clickPlay(PLAY_X, PLAY_Y)
        task.wait(2)
    end
    
    -- Завершення роботи скрипта
    if isRunning then
        log.Text = "✅ КНОПКУ НАДОВБЛЕНО! СКРИПТ ЗАВЕРШЕНО."
        task.wait(3)
        sg:Destroy()
    end
end)
