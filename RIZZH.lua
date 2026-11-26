local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local Config = {
    Name = "RIZZH",
    Version = "1.2.1",
    Accent = Color3.fromRGB(255, 48, 72),
    AccentSoft = Color3.fromRGB(120, 25, 42),
    Background = Color3.fromRGB(10, 10, 13),
    Surface = Color3.fromRGB(17, 17, 22),
    Surface2 = Color3.fromRGB(25, 25, 32),
    Surface3 = Color3.fromRGB(34, 34, 43),
    Text = Color3.fromRGB(245, 245, 248),
    Muted = Color3.fromRGB(145, 145, 158),
    Good = Color3.fromRGB(90, 210, 145),
    Warning = Color3.fromRGB(245, 185, 75),
    FOV = 180,
    MaxDistance = 1500,
    HighlightEnabled = true,
    NamesEnabled = true,
    TracersEnabled = false,
    TeamCheck = false,
    MenuKey = Enum.KeyCode.RightShift,
    TargetKey = Enum.KeyCode.Q,
    VisibleOnly = true,
    ShowFOV = true,
    LockedTarget = nil,
    SelectedTab = "Home",
    Notifications = true,
    UnloadKey = Enum.KeyCode.End,
    SortMode = "Distance",
    NameFilter = "",
    PinnedTarget = nil,
    HealthTagsEnabled = true,
    SelectedColor = Color3.fromRGB(255, 205, 80),
    TargetFolderName = "TrainingTargets"
}

local State = {
    Running = true,
    Connections = {},
    Highlights = {},
    BillboardGuis = {},
    Tracers = {},
    CurrentTarget = nil,
    FOVCircle = nil,
    MenuOpen = true,
    Dragging = false,
    SliderDragging = nil,
    LastTargetUpdate = 0,
    TargetUpdateRate = 0.08,
    TargetList = {},
    Pages = {},
    Controls = {},
    Theme = "Crimson",
    SelectionCount = 0,
    SelectionHistory = {},
    SessionStart = os.clock(),
    RefreshCount = 0,
    HealthTags = {},
    LastHealth = {},
    LastDamage = 0,
    TargetListText = nil,
    StatsLabels = {}
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(State.Connections, connection)
    return connection
end

local function tween(object, duration, properties)
    local info = TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local animation = TweenService:Create(object, info, properties)
    animation:Play()
    return animation
end

local function create(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function round(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 8)
    }, parent)
end

local function outline(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or Config.Surface3,
        Transparency = transparency or 0,
        Thickness = thickness or 1
    }, parent)
end

local function padding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0)
    }, parent)
end

local function notify(message, duration)
    if not Config.Notifications then
        return
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = Config.Name,
            Text = tostring(message),
            Duration = duration or 3
        })
    end)
end

local function getTargetFolder()
    local folderName = Config.TargetFolderName or "TrainingTargets"
    local namedFolder = workspace:FindFirstChild(folderName, true)
    if namedFolder then
        return namedFolder
    end
    return workspace
end

local function isValidTarget(model)
    if not model or not model:IsA("Model") then
        return false
    end
    if not model:IsDescendantOf(workspace) then
        return false
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return false
    end
    if Players:GetPlayerFromCharacter(model) then
        return false
    end
    return true
end

local function getRoot(model)
    return model and model:FindFirstChild("HumanoidRootPart")
end

local function getScreenPosition(model)
    local root = getRoot(model)
    if not root then
        return nil, false
    end
    local position, visible = Camera:WorldToViewportPoint(root.Position)
    return Vector2.new(position.X, position.Y), visible and position.Z > 0
end

local function isOnScreen(model)
    local point, visible = getScreenPosition(model)
    if not point or not visible then
        return false
    end
    local viewport = Camera.ViewportSize
    return point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y
end

local function hasLineOfSight(model)
    local root = getRoot(model)
    if not root then
        return false
    end
    local origin = Camera.CFrame.Position
    local direction = root.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    params.IgnoreWater = true
    local result = workspace:Raycast(origin, direction, params)
    return not result or result.Instance:IsDescendantOf(model)
end

local function getDistance(model)
    local root = getRoot(model)
    local character = LocalPlayer.Character
    local localRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not localRoot then
        return math.huge
    end
    return (root.Position - localRoot.Position).Magnitude
end

local function rebuildTargetList()
    table.clear(State.TargetList)
    local folder = getTargetFolder()
    if not folder then
        return
    end
    for _, model in ipairs(folder:GetChildren()) do
        if isValidTarget(model) then
            table.insert(State.TargetList, model)
        end
    end
end

local function findNearestTarget()
    local center = Camera.ViewportSize / 2
    local bestModel = nil
    local bestDistance = Config.FOV
    for _, model in ipairs(State.TargetList) do
        if isValidTarget(model) then
            local point, visible = getScreenPosition(model)
            if point and visible and isOnScreen(model) then
                local screenDistance = (point - center).Magnitude
                local worldDistance = getDistance(model)
                if screenDistance <= bestDistance and worldDistance <= Config.MaxDistance then
                    if not Config.VisibleOnly or hasLineOfSight(model) then
                        bestDistance = screenDistance
                        bestModel = model
                    end
                end
            end
        end
    end
    return bestModel, bestDistance
end


local updateVisuals
local Training = {}

function Training.getHumanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid")
end

function Training.getTargetName(model)
    return model and model.Name or "Unknown"
end

function Training.getTargetHealth(model)
    local humanoid = Training.getHumanoid(model)
    return humanoid and humanoid.Health or 0
end

function Training.getTargetMaxHealth(model)
    local humanoid = Training.getHumanoid(model)
    return humanoid and humanoid.MaxHealth or 0
end

function Training.getTargetHealthPercent(model)
    local maximum = Training.getTargetMaxHealth(model)
    if maximum <= 0 then
        return 0
    end
    return math.clamp(Training.getTargetHealth(model) / maximum, 0, 1)
end

function Training.getTargetPosition(model)
    local root = getRoot(model)
    return root and root.Position or nil
end

function Training.getTargetVelocity(model)
    local root = getRoot(model)
    return root and root.AssemblyLinearVelocity or Vector3.zero
end

function Training.getTargetScreenDistance(model)
    local point, visible = getScreenPosition(model)
    if not point or not visible then
        return math.huge
    end
    return (point - Camera.ViewportSize / 2).Magnitude
end

function Training.isTargetAlive(model)
    local humanoid = Training.getHumanoid(model)
    return isValidTarget(model) and humanoid.Health > 0
end

function Training.isTargetVisible(model)
    return isValidTarget(model) and isOnScreen(model) and hasLineOfSight(model)
end

function Training.isTargetInRange(model)
    return isValidTarget(model) and getDistance(model) <= Config.MaxDistance
end

function Training.isTargetPinned(model)
    return State.PinnedTarget == model
end

function Training.setTarget(model)
    if not isValidTarget(model) then
        return false
    end
    State.CurrentTarget = model
    Config.LockedTarget = model
    State.SelectionCount += 1
    table.insert(State.SelectionHistory, 1, {
        Name = model.Name,
        Time = os.clock(),
        Distance = getDistance(model)
    })
    while #State.SelectionHistory > 12 do
        table.remove(State.SelectionHistory)
    end
    return true
end

function Training.clearTarget()
    State.CurrentTarget = nil
    Config.LockedTarget = nil
end

function Training.pinTarget(model)
    if isValidTarget(model) then
        State.PinnedTarget = model
        Config.PinnedTarget = model
        return true
    end
    return false
end

function Training.unpinTarget()
    State.PinnedTarget = nil
    Config.PinnedTarget = nil
end

function Training.getTargetIndex(model)
    for index, candidate in ipairs(State.TargetList) do
        if candidate == model then
            return index
        end
    end
    return nil
end

function Training.getTargetAtIndex(index)
    return State.TargetList[index]
end

function Training.sortTargetsByDistance()
    table.sort(State.TargetList, function(a, b)
        return getDistance(a) < getDistance(b)
    end)
end

function Training.sortTargetsByHealth()
    table.sort(State.TargetList, function(a, b)
        return Training.getTargetHealth(a) < Training.getTargetHealth(b)
    end)
end

function Training.filterTargetsByName(query)
    local matches = {}
    local lowered = string.lower(query or "")
    for _, model in ipairs(State.TargetList) do
        if string.find(string.lower(model.Name), lowered, 1, true) then
            table.insert(matches, model)
        end
    end
    return matches
end

function Training.countTargets()
    return #State.TargetList
end

function Training.countTargetsInRange()
    local count = 0
    for _, model in ipairs(State.TargetList) do
        if Training.isTargetInRange(model) then
            count += 1
        end
    end
    return count
end

function Training.countTargetsVisible()
    local count = 0
    for _, model in ipairs(State.TargetList) do
        if Training.isTargetVisible(model) then
            count += 1
        end
    end
    return count
end

function Training.getNearestWorldTarget()
    local best, bestDistance = nil, math.huge
    for _, model in ipairs(State.TargetList) do
        local distance = getDistance(model)
        if isValidTarget(model) and distance < bestDistance then
            best, bestDistance = model, distance
        end
    end
    return best, bestDistance
end

function Training.getFarthestWorldTarget()
    local best, bestDistance = nil, -math.huge
    for _, model in ipairs(State.TargetList) do
        local distance = getDistance(model)
        if isValidTarget(model) and distance > bestDistance then
            best, bestDistance = model, distance
        end
    end
    return best, bestDistance
end

function Training.getRandomTrainingTarget()
    local valid = {}
    for _, model in ipairs(State.TargetList) do
        if isValidTarget(model) then
            table.insert(valid, model)
        end
    end
    if #valid == 0 then
        return nil
    end
    return valid[math.random(1, #valid)]
end

function Training.cycleTarget(direction)
    if #State.TargetList == 0 then
        return nil
    end
    local currentIndex = Training.getTargetIndex(State.CurrentTarget) or 0
    local nextIndex = currentIndex + (direction or 1)
    if nextIndex > #State.TargetList then
        nextIndex = 1
    elseif nextIndex < 1 then
        nextIndex = #State.TargetList
    end
    local candidate = Training.getTargetAtIndex(nextIndex)
    if candidate and Training.setTarget(candidate) then
        return candidate
    end
    return nil
end

function Training.getTargetSummary(model)
    if not isValidTarget(model) then
        return "No active target"
    end
    return string.format("%s  |  %.0f studs  |  %d%% HP",
        Training.getTargetName(model),
        getDistance(model),
        math.floor(Training.getTargetHealthPercent(model) * 100)
    )
end

function Training.refreshTrainingData()
    rebuildTargetList()
    if Config.SortMode == "Health" then
        Training.sortTargetsByHealth()
    else
        Training.sortTargetsByDistance()
    end
    if updateVisuals then
        updateVisuals()
    end
    State.RefreshCount += 1
    return #State.TargetList
end

function Training.resetTrainingStats()
    State.SelectionCount = 0
    State.SelectionHistory = {}
    State.SessionStart = os.clock()
    State.RefreshCount = 0
    State.LastDamage = 0
end

function Training.formatDistance(distance)
    if not distance or distance == math.huge then
        return "--"
    end
    return string.format("%.1f studs", distance)
end

function Training.formatHealth(model)
    if not isValidTarget(model) then
        return "--"
    end
    return string.format("%d / %d", math.floor(Training.getTargetHealth(model)), math.floor(Training.getTargetMaxHealth(model)))
end

function Training.getSessionDuration()
    return math.max(0, os.clock() - State.SessionStart)
end

function Training.getAliveTargetCount()
    local count = 0
    for _, model in ipairs(State.TargetList) do
        if Training.isTargetAlive(model) then
            count += 1
        end
    end
    return count
end

function Training.getTargetHealthState(model)
    local percent = Training.getTargetHealthPercent(model)
    if percent >= 0.7 then
        return "Healthy"
    elseif percent >= 0.3 then
        return "Worn"
    end
    return "Low"
end

function Training.getTargetVelocityMagnitude(model)
    return Training.getTargetVelocity(model).Magnitude
end

function Training.getTargetDirection(model)
    local position = Training.getTargetPosition(model)
    if not position then
        return nil
    end
    local origin = Camera.CFrame.Position
    local delta = position - origin
    return delta.Magnitude > 0 and delta.Unit or Vector3.zero
end

function Training.getTargetFacingDot(model)
    local root = getRoot(model)
    local direction = Training.getTargetDirection(model)
    if not root or not direction then
        return 0
    end
    return root.CFrame.LookVector:Dot(-direction)
end

function Training.getTargetDisplayColor(model)
    if Training.isTargetPinned(model) then
        return Config.SelectedColor
    end
    if model == State.CurrentTarget then
        return Config.Accent
    end
    return Config.Text
end

function Training.getTargetListNames()
    local names = {}
    for _, model in ipairs(State.TargetList) do
        table.insert(names, model.Name)
    end
    return names
end

function Training.getTargetHealthAverage()
    if #State.TargetList == 0 then
        return 0
    end
    local total = 0
    for _, model in ipairs(State.TargetList) do
        total += Training.getTargetHealthPercent(model)
    end
    return total / #State.TargetList
end

function Training.getSelectionHistoryText()
    if #State.SelectionHistory == 0 then
        return "No selections yet"
    end
    local entries = {}
    for index, entry in ipairs(State.SelectionHistory) do
        table.insert(entries, tostring(index) .. ". " .. entry.Name)
    end
    return table.concat(entries, "   •   ")
end

function Training.setSortMode(mode)
    if mode ~= "Distance" and mode ~= "Health" then
        return false
    end
    Config.SortMode = mode
    Training.refreshTrainingData()
    return true
end

function Training.clearPinnedTarget()
    Training.unpinTarget()
end

function Training.getPinnedTarget()
    if isValidTarget(State.PinnedTarget) then
        return State.PinnedTarget
    end
    Training.unpinTarget()
    return nil
end

function Training.getCurrentTarget()
    if isValidTarget(State.CurrentTarget) then
        return State.CurrentTarget
    end
    Training.clearTarget()
    return nil
end

function Training.selectNearestWorldTarget()
    local model = Training.getNearestWorldTarget()
    if model then
        Training.setTarget(model)
    end
    return model
end

function Training.selectRandomTarget()
    local model = Training.getRandomTrainingTarget()
    if model then
        Training.setTarget(model)
    end
    return model
end

function Training.selectNextTarget()
    return Training.cycleTarget(1)
end

function Training.selectPreviousTarget()
    return Training.cycleTarget(-1)
end

function Training.getTargetsWithinFOV()
    local matches = {}
    for _, model in ipairs(State.TargetList) do
        if Training.getTargetScreenDistance(model) <= Config.FOV then
            table.insert(matches, model)
        end
    end
    return matches
end

function Training.getTargetsOutsideFOV()
    local matches = {}
    for _, model in ipairs(State.TargetList) do
        if Training.getTargetScreenDistance(model) > Config.FOV then
            table.insert(matches, model)
        end
    end
    return matches
end

function Training.getTargetScreenState(model)
    return isOnScreen(model) and "On screen" or "Off screen"
end

function Training.getTargetVisibilityState(model)
    return hasLineOfSight(model) and "Clear" or "Blocked"
end

function Training.getTargetMovementState(model)
    return Training.getTargetVelocityMagnitude(model) > 1 and "Moving" or "Still"
end

function Training.getTargetRank(model)
    local index = Training.getTargetIndex(model)
    return index and ("#" .. tostring(index)) or "--"
end

function Training.getTargetQuickInfo(model)
    if not isValidTarget(model) then
        return "No target selected"
    end
    return string.format("%s | %s | %s | %s",
        Training.getTargetName(model),
        Training.formatDistance(getDistance(model)),
        Training.formatHealth(model),
        Training.getTargetHealthState(model)
    )
end

function Training.getTrainingSummary()
    return string.format("%d NPCs | %d alive | %d visible | %d in range",
        Training.countTargets(),
        Training.getAliveTargetCount(),
        Training.countTargetsVisible(),
        Training.countTargetsInRange()
    )
end

function Training.getTargetNameMatches(query)
    return Training.filterTargetsByName(query)
end

function Training.getTargetClosestToCenter()
    return findNearestTarget()
end

function Training.getTargetHealthRatio(model)
    return Training.getTargetHealthPercent(model)
end

function Training.getTargetWorldDistance(model)
    return getDistance(model)
end

function Training.getTargetScreenPoint(model)
    return getScreenPosition(model)
end

function Training.getTrainingFolderStatus()
    return getTargetFolder() ~= nil
end

function Training.getSessionMinutes()
    return math.floor(Training.getSessionDuration() / 60)
end

function Training.getSessionSeconds()
    return math.floor(Training.getSessionDuration() % 60)
end

function Training.getSessionClock()
    return string.format("%02d:%02d", Training.getSessionMinutes(), Training.getSessionSeconds())
end

function Training.getPinnedTargetName()
    local model = Training.getPinnedTarget()
    return model and model.Name or "None"
end

function Training.getSelectedTargetName()
    local model = Training.getCurrentTarget()
    return model and model.Name or "None"
end

function Training.getTargetHealthColor(model)
    local ratio = Training.getTargetHealthPercent(model)
    if ratio >= 0.7 then
        return Config.Good
    elseif ratio >= 0.3 then
        return Config.Warning
    end
    return Config.Accent
end

function Training.getTargetIsMoving(model)
    return Training.getTargetVelocityMagnitude(model) > 1
end

function Training.getTargetIsStationary(model)
    return not Training.getTargetIsMoving(model)
end

function Training.getTargetIsWithinFOV(model)
    return Training.getTargetScreenDistance(model) <= Config.FOV
end

function Training.getTargetIsWithinDistance(model, distance)
    return isValidTarget(model) and getDistance(model) <= (distance or Config.MaxDistance)
end

function Training.getTrainingTargetCount()
    return Training.countTargets()
end

function Training.getTrainingAliveCount()
    return Training.getAliveTargetCount()
end

function Training.getTrainingVisibleCount()
    return Training.countTargetsVisible()
end

function Training.getTrainingInRangeCount()
    return Training.countTargetsInRange()
end

function Training.getTrainingAverageHealth()
    return Training.getTargetHealthAverage()
end

function Training.getTrainingSelectionCount()
    return State.SelectionCount
end

function Training.getTrainingRefreshCount()
    return State.RefreshCount
end

function Training.getTrainingHistory()
    return State.SelectionHistory
end

function Training.getTrainingSortMode()
    return Config.SortMode
end

function Training.getTrainingNameFilter()
    return Config.NameFilter
end

function Training.setTrainingNameFilter(query)
    Config.NameFilter = tostring(query or "")
    return Training.filterTargetsByName(Config.NameFilter)
end

function Training.clearTrainingNameFilter()
    Config.NameFilter = ""
end

function Training.isTrainingReady()
    return Training.getTrainingFolderStatus() and Training.countTargets() > 0
end

function Training.getTargetByName(name)
    local wanted = string.lower(tostring(name or ""))
    for _, model in ipairs(State.TargetList) do
        if string.lower(model.Name) == wanted then
            return model
        end
    end
    return nil
end

function Training.selectTargetByName(name)
    local model = Training.getTargetByName(name)
    if model then
        Training.setTarget(model)
    end
    return model
end

function Training.getTargetSummaryLine(model)
    return Training.getTargetQuickInfo(model) .. " | " .. Training.getTargetScreenState(model)
end

function Training.getTargetStatusLine(model)
    return Training.getTargetName(model) .. " • " .. Training.getTargetVisibilityState(model) .. " • " .. Training.getTargetMovementState(model)
end

function Training.updateTargetStatsPanel()
    if not State.StatsLabels or not State.StatsLabels.Target then
        return
    end
    local current = Training.getCurrentTarget()
    State.StatsLabels.Target.Text = "Selected: " .. Training.getSelectedTargetName()
    State.StatsLabels.Pinned.Text = "Pinned: " .. Training.getPinnedTargetName()
    State.StatsLabels.Summary.Text = Training.getTrainingSummary()
    State.StatsLabels.Session.Text = "Session: " .. Training.getSessionClock()
    State.StatsLabels.Selections.Text = "Selections: " .. tostring(Training.getTrainingSelectionCount())
    State.StatsLabels.Average.Text = string.format("Average NPC health: %d%%", math.floor(Training.getTrainingAverageHealth() * 100))
    State.StatsLabels.Info.Text = current and Training.getTargetSummaryLine(current) or "Select a training NPC to view details"
end

function Training.recordTargetHealth(model)
    local currentHealth = Training.getTargetHealth(model)
    local previousHealth = State.LastHealth[model]
    if previousHealth and currentHealth < previousHealth then
        State.LastDamage = previousHealth - currentHealth
    end
    State.LastHealth[model] = currentHealth
end

function Training.clearTargetHealthHistory()
    table.clear(State.LastHealth)
    State.LastDamage = 0
end

function Training.getLastObservedDamage()
    return State.LastDamage
end

function Training.getTargetLastKnownHealth(model)
    return State.LastHealth[model] or Training.getTargetHealth(model)
end

function Training.getTrainingFolderName()
    local folder = getTargetFolder()
    return folder and folder.Name or "Missing"
end

function Training.getTargetCountText()
    return tostring(Training.countTargets()) .. " training NPCs"
end

function Training.getTargetFilterCount(query)
    return #Training.filterTargetsByName(query)
end

function Training.getTargetFOVCount()
    return #Training.getTargetsWithinFOV()
end

function Training.getTargetOutsideFOVCount()
    return #Training.getTargetsOutsideFOV()
end

function Training.getTargetWorldClosestName()
    local model = Training.getNearestWorldTarget()
    return model and model.Name or "None"
end

function Training.getTargetWorldFarthestName()
    local model = Training.getFarthestWorldTarget()
    return model and model.Name or "None"
end

function Training.getTargetScreenClosestName()
    local model = Training.getTargetClosestToCenter()
    return model and model.Name or "None"
end

function Training.getTargetPinnedStateText()
    return Training.getPinnedTarget() and "Pinned" or "Not pinned"
end

function Training.getTargetCurrentStateText()
    return Training.getCurrentTarget() and "Locked" or "Unlocked"
end

function Training.getTargetHealthPercentText(model)
    return tostring(math.floor(Training.getTargetHealthRatio(model) * 100)) .. "%"
end

function Training.getTargetSpeedText(model)
    return string.format("%.1f studs/s", Training.getTargetVelocityMagnitude(model))
end

function Training.getTargetFacingText(model)
    return string.format("Facing score: %.2f", Training.getTargetFacingDot(model))
end

function Training.getTargetFOVText(model)
    return string.format("%.0f px from center", Training.getTargetScreenDistance(model))
end

function Training.getTargetVisibilityText(model)
    return Training.getTargetVisibilityState(model)
end

function Training.getTargetIndexText(model)
    return Training.getTargetRank(model)
end

local function clearVisual(model)
    local highlight = State.Highlights[model]
    if highlight then
        highlight:Destroy()
        State.Highlights[model] = nil
    end
    local billboard = State.BillboardGuis[model]
    if billboard then
        billboard:Destroy()
        State.BillboardGuis[model] = nil
    end
end

local function clearAllVisuals()
    for model in pairs(State.Highlights) do
        clearVisual(model)
    end
    for model in pairs(State.BillboardGuis) do
        clearVisual(model)
    end
end

local function applyHighlight(model)
    if not Config.HighlightEnabled or not isValidTarget(model) then
        clearVisual(model)
        return
    end
    if State.Highlights[model] then
        return
    end
    local highlight = create("Highlight", {
        Name = "RIZZH_TrainingHighlight",
        Adornee = model,
        FillColor = Config.Accent,
        OutlineColor = Config.Text,
        FillTransparency = 0.82,
        OutlineTransparency = 0.08,
        DepthMode = Enum.HighlightDepthMode.Occluded
    }, model)
    State.Highlights[model] = highlight
end

local function applyNameTag(model)
    if not Config.NamesEnabled or not isValidTarget(model) then
        local existing = State.BillboardGuis[model]
        if existing then
            existing:Destroy()
            State.BillboardGuis[model] = nil
        end
        return
    end
    if State.BillboardGuis[model] then
        return
    end
    local root = getRoot(model)
    if not root then
        return
    end
    local billboard = create("BillboardGui", {
        Name = "RIZZH_NameTag",
        Adornee = root,
        Size = UDim2.fromOffset(150, 34),
        StudsOffset = Vector3.new(0, 2.8, 0),
        AlwaysOnTop = false,
        MaxDistance = Config.MaxDistance
    }, PlayerGui)
    local label = create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = model.Name,
        TextColor3 = Config.Text,
        TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 0.35,
        Font = Enum.Font.GothamBold,
        TextSize = 12
    }, billboard)
    State.BillboardGuis[model] = billboard
end

updateVisuals = function()
    local alive = {}
    for _, model in ipairs(State.TargetList) do
        alive[model] = true
        applyHighlight(model)
        applyNameTag(model)
    end
    local stale = {}
    for model in pairs(State.Highlights) do
        if not alive[model] then
            table.insert(stale, model)
        end
    end
    for model in pairs(State.BillboardGuis) do
        if not alive[model] then
            table.insert(stale, model)
        end
    end
    for _, model in ipairs(stale) do
        clearVisual(model)
    end
end

local setTarget = Training.setTarget
local clearTarget = Training.clearTarget
local refreshTrainingData = Training.refreshTrainingData
local getCurrentTarget = Training.getCurrentTarget
local formatDistance = Training.formatDistance

local gui = create("ScreenGui", {
    Name = "RIZZH",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, PlayerGui)

local rootFrame = create("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(650, 440),
    Position = UDim2.new(0.5, -325, 0.5, -220),
    BackgroundColor3 = Config.Background,
    BorderSizePixel = 0
}, gui)
round(rootFrame, 12)
outline(rootFrame, Config.AccentSoft, 0.12, 1)

local topBar = create("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = Config.Surface,
    BorderSizePixel = 0
}, rootFrame)
round(topBar, 12)

local topCover = create("Frame", {
    Position = UDim2.new(0, 0, 1, -12),
    Size = UDim2.new(1, 0, 0, 12),
    BackgroundColor3 = Config.Surface,
    BorderSizePixel = 0
}, topBar)

local brand = create("TextLabel", {
    Position = UDim2.fromOffset(20, 0),
    Size = UDim2.fromOffset(160, 54),
    BackgroundTransparency = 1,
    Text = "R I Z Z H",
    TextColor3 = Config.Accent,
    TextSize = 20,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Left
}, topBar)

local version = create("TextLabel", {
    Position = UDim2.fromOffset(174, 4),
    Size = UDim2.fromOffset(90, 48),
    BackgroundTransparency = 1,
    Text = "PRIVATE LAB  /  " .. Config.Version,
    TextColor3 = Config.Muted,
    TextSize = 9,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left
}, topBar)

local status = create("TextLabel", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -54, 0.5, 0),
    Size = UDim2.fromOffset(150, 24),
    BackgroundTransparency = 1,
    Text = "●  TRAINING MODE",
    TextColor3 = Config.Good,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Right
}, topBar)

local closeButton = create("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -15, 0.5, 0),
    Size = UDim2.fromOffset(26, 26),
    BackgroundColor3 = Color3.fromRGB(65, 24, 34),
    Text = "×",
    TextColor3 = Config.Text,
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    BorderSizePixel = 0
}, topBar)
round(closeButton, 7)

local sidebar = create("Frame", {
    Position = UDim2.fromOffset(14, 68),
    Size = UDim2.fromOffset(145, 356),
    BackgroundColor3 = Config.Surface,
    BorderSizePixel = 0
}, rootFrame)
round(sidebar, 9)

local pageContainer = create("Frame", {
    Position = UDim2.fromOffset(171, 68),
    Size = UDim2.fromOffset(465, 356),
    BackgroundColor3 = Config.Surface,
    BorderSizePixel = 0,
    ClipsDescendants = true
}, rootFrame)
round(pageContainer, 9)

local tabLayout = create("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder
}, sidebar)
padding(sidebar, 9, 9, 12, 9)

local tabNames = {"Home", "Training", "Visuals", "Targeting", "Extras", "Stats", "Tools", "Settings"}
local tabButtons = {}
local pageFrames = {}

local function makeText(parent, text, position, size, color, fontSize, font)
    return create("TextLabel", {
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = color or Config.Text,
        TextSize = fontSize or 13,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    }, parent)
end

local function makeSection(parent, text, y)
    makeText(parent, string.upper(text), UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 22), Config.Accent, 10, Enum.Font.GothamBold)
end

local function makeButton(parent, text, y, callback, width)
    local button = create("TextButton", {
        Position = UDim2.fromOffset(0, y),
        Size = UDim2.new(0, width or 205, 0, 34),
        BackgroundColor3 = Config.Surface2,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Config.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false
    }, parent)
    round(button, 7)
    connect(button.MouseEnter, function()
        tween(button, 0.12, {BackgroundColor3 = Config.Surface3})
    end)
    connect(button.MouseLeave, function()
        tween(button, 0.12, {BackgroundColor3 = Config.Surface2})
    end)
    connect(button.MouseButton1Click, callback)
    return button
end

local function makeToggle(parent, labelText, y, initial, callback)
    makeText(parent, labelText, UDim2.fromOffset(0, y), UDim2.fromOffset(245, 30), Config.Text, 12, Enum.Font.GothamMedium)
    local toggle = create("TextButton", {
        Position = UDim2.new(1, -58, 0, y + 3),
        Size = UDim2.fromOffset(48, 24),
        BackgroundColor3 = initial and Config.Accent or Config.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false
    }, parent)
    round(toggle, 12)
    local knob = create("Frame", {
        Position = initial and UDim2.fromOffset(27, 3) or UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Config.Text,
        BorderSizePixel = 0
    }, toggle)
    round(knob, 9)
    local value = initial
    connect(toggle.MouseButton1Click, function()
        value = not value
        tween(toggle, 0.15, {BackgroundColor3 = value and Config.Accent or Config.Surface3})
        tween(knob, 0.15, {Position = value and UDim2.fromOffset(27, 3) or UDim2.fromOffset(3, 3)})
        callback(value)
    end)
    return {
        Get = function()
            return value
        end,
        Set = function(nextValue)
            value = nextValue
            toggle.BackgroundColor3 = value and Config.Accent or Config.Surface3
            knob.Position = value and UDim2.fromOffset(27, 3) or UDim2.fromOffset(3, 3)
            callback(value)
        end
    }
end

local function makeSlider(parent, labelText, y, minimum, maximum, initial, callback)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(0, y),
        Size = UDim2.new(1, -4, 0, 54),
        BackgroundTransparency = 1
    }, parent)
    local valueLabel = makeText(holder, labelText .. "  " .. tostring(initial), UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 22), Config.Text, 12, Enum.Font.GothamMedium)
    local bar = create("Frame", {
        Position = UDim2.fromOffset(0, 32),
        Size = UDim2.new(1, 0, 0, 7),
        BackgroundColor3 = Config.Surface3,
        BorderSizePixel = 0
    }, holder)
    round(bar, 5)
    local fill = create("Frame", {
        Size = UDim2.new((initial - minimum) / (maximum - minimum), 0, 1, 0),
        BackgroundColor3 = Config.Accent,
        BorderSizePixel = 0
    }, bar)
    round(fill, 5)
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new((initial - minimum) / (maximum - minimum), 0, 0.5, 0),
        Size = UDim2.fromOffset(13, 13),
        BackgroundColor3 = Config.Text,
        BorderSizePixel = 0
    }, bar)
    round(knob, 7)
    local value = initial
    local function setFromX(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        value = math.floor(minimum + (maximum - minimum) * alpha + 0.5)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = labelText .. "  " .. tostring(value)
        callback(value)
    end
    connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
            State.SliderDragging = {Set = setFromX}
        end
    end)
    return {
        Get = function()
            return value
        end,
        Set = function(nextValue)
            value = math.clamp(nextValue, minimum, maximum)
            local alpha = (value - minimum) / (maximum - minimum)
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            valueLabel.Text = labelText .. "  " .. tostring(value)
            callback(value)
        end
    }
end

local function makePage(name)
    local frame = create("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Config.Accent,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y
    }, pageContainer)
    padding(frame, 18, 18, 16, 18)
    pageFrames[name] = frame
    return frame
end

for index, name in ipairs(tabNames) do
    local button = create("TextButton", {
        Name = name .. "Tab",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Config.Surface2,
        BorderSizePixel = 0,
        Text = "   " .. name,
        TextColor3 = Config.Muted,
        TextSize = 12,
        Font = Enum.Font.GothamSemibold,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = index,
        AutoButtonColor = false
    }, sidebar)
    round(button, 7)
    tabButtons[name] = button
end

local home = makePage("Home")
makeSection(home, "Overview", 0)
makeText(home, "RIZZH PRIVATE TRAINING ENVIRONMENT", UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 28), Config.Text, 16, Enum.Font.GothamBold)
makeText(home, "A visual practice panel for NPCs in your own experience.", UDim2.fromOffset(0, 61), UDim2.new(1, 0, 0, 24), Config.Muted, 11)
makeSection(home, "Live status", 105)
local targetStatus = makeText(home, "Current target: none", UDim2.fromOffset(0, 132), UDim2.new(1, 0, 0, 24), Config.Text, 12)
local countStatus = makeText(home, "Training targets: 0", UDim2.fromOffset(0, 160), UDim2.new(1, 0, 0, 24), Config.Text, 12)
local distanceStatus = makeText(home, "Target distance: --", UDim2.fromOffset(0, 188), UDim2.new(1, 0, 0, 24), Config.Text, 12)
makeButton(home, "Refresh target list", 232, function()
    rebuildTargetList()
    updateVisuals()
    notify("Training target list refreshed")
end, 190)
makeText(home, "Targets: Workspace descendants named " .. Config.TargetFolderName .. " (or direct Workspace NPC models)", UDim2.fromOffset(0, 280), UDim2.new(1, 0, 0, 22), Config.Muted, 10)

local training = makePage("Training")
makeSection(training, "Target practice", 0)
makeText(training, "Select a nearby NPC for a visual training lock.", UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 22), Config.Muted, 11)
makeButton(training, "Find nearest NPC", 60, function()
    rebuildTargetList()
    local selected = findNearestTarget()
    if selected then
        setTarget(selected)
    else
        clearTarget()
    end
    notify(State.CurrentTarget and ("Selected " .. State.CurrentTarget.Name) or "No target in range")
end, 190)
makeButton(training, "Clear target lock", 103, function()
    clearTarget()
    notify("Target lock cleared")
end, 190)
makeToggle(training, "Require line of sight", 158, Config.VisibleOnly, function(value)
    Config.VisibleOnly = value
end)
makeSlider(training, "Target FOV", 205, 40, 500, Config.FOV, function(value)
    Config.FOV = value
end)
makeSlider(training, "Max distance", 270, 100, 3000, Config.MaxDistance, function(value)
    Config.MaxDistance = value
end)

local visuals = makePage("Visuals")
makeSection(visuals, "NPC visuals", 0)
makeToggle(visuals, "Highlight training NPCs", 34, Config.HighlightEnabled, function(value)
    Config.HighlightEnabled = value
    updateVisuals()
end)
makeToggle(visuals, "Show NPC name tags", 78, Config.NamesEnabled, function(value)
    Config.NamesEnabled = value
    updateVisuals()
end)
makeToggle(visuals, "Show FOV circle", 122, Config.ShowFOV, function(value)
    Config.ShowFOV = value
end)
makeToggle(visuals, "Track NPC health stats", 166, Config.HealthTagsEnabled, function(value)
    Config.HealthTagsEnabled = value
end)
makeText(visuals, "Highlights use occluded depth mode.", UDim2.fromOffset(0, 210), UDim2.new(1, 0, 0, 22), Config.Muted, 10)

local targeting = makePage("Targeting")
makeSection(targeting, "Selection settings", 0)
makeToggle(targeting, "Refresh target list automatically", 34, true, function(value)
    Config.AutoRefresh = value
end)
makeToggle(targeting, "Notifications", 78, Config.Notifications, function(value)
    Config.Notifications = value
end)
makeText(targeting, "Target selection only identifies NPCs in the training folder.", UDim2.fromOffset(0, 132), UDim2.new(1, 0, 0, 42), Config.Muted, 11)
makeText(targeting, "No automatic firing or player targeting is included.", UDim2.fromOffset(0, 180), UDim2.new(1, 0, 0, 42), Config.Warning, 11)

local updateFOVCircle
local setMenuVisible
local selectTab

local extras = makePage("Extras")
makeSection(extras, "Extra tools", 0)
makeText(extras, "More controls for your private NPC training setup.", UDim2.fromOffset(0, 24), UDim2.new(1, 0, 0, 22), Config.Muted, 11)

local accentOptions = {
    Color3.fromRGB(255, 48, 72),
    Color3.fromRGB(80, 190, 255),
    Color3.fromRGB(180, 105, 255),
    Color3.fromRGB(255, 190, 70),
    Color3.fromRGB(90, 220, 155)
}
local accentIndex = 1

local function clearTargetSelection()
    clearTarget()
    notify("Target selection cleared")
end

local function cycleTarget(direction)
    refreshTrainingData()
    if #State.TargetList == 0 then
        notify("No training NPCs found")
        return
    end
    local currentIndex = 0
    for index, model in ipairs(State.TargetList) do
        if model == State.CurrentTarget then
            currentIndex = index
            break
        end
    end
    local nextIndex = ((currentIndex - 1 + direction) % #State.TargetList) + 1
    setTarget(State.TargetList[nextIndex])
end

local function selectClosestWorldTarget()
    refreshTrainingData()
    local best, bestDistance = nil, math.huge
    for _, model in ipairs(State.TargetList) do
        local distance = getDistance(model)
        if distance < bestDistance and distance <= Config.MaxDistance then
            best, bestDistance = model, distance
        end
    end
    setTarget(best)
end

local function selectHealthTarget(lowest)
    refreshTrainingData()
    local best, bestRatio = nil, lowest and math.huge or -math.huge
    for _, model in ipairs(State.TargetList) do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.MaxHealth > 0 then
            local ratio = humanoid.Health / humanoid.MaxHealth
            if (lowest and ratio < bestRatio) or (not lowest and ratio > bestRatio) then
                best, bestRatio = model, ratio
            end
        end
    end
    setTarget(best)
end

local function sortTargetsByDistance()
    refreshTrainingData()
    table.sort(State.TargetList, function(a, b)
        return getDistance(a) < getDistance(b)
    end)
    notify("NPC list sorted by distance")
end

local function sortTargetsByName()
    refreshTrainingData()
    table.sort(State.TargetList, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)
    notify("NPC list sorted by name")
end

local function showTargetDetails()
    local model = State.CurrentTarget
    if not isValidTarget(model) then
        notify("No valid target selected")
        return
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    notify(string.format("%s | HP %.0f/%.0f | %.1f studs", model.Name, humanoid.Health, humanoid.MaxHealth, getDistance(model)), 5)
end

local function showTargetCount()
    refreshTrainingData()
    notify("Training NPCs found: " .. tostring(#State.TargetList))
end

local function selectRandomTarget()
    refreshTrainingData()
    if #State.TargetList == 0 then
        notify("No training NPCs found")
        return
    end
    setTarget(State.TargetList[math.random(1, #State.TargetList)])
end

local function selectFirstTarget()
    refreshTrainingData()
    setTarget(State.TargetList[1])
end

local function selectLastTarget()
    refreshTrainingData()
    setTarget(State.TargetList[#State.TargetList])
end

local function selectFarthestTarget()
    refreshTrainingData()
    local best, bestDistance = nil, -math.huge
    for _, model in ipairs(State.TargetList) do
        local distance = getDistance(model)
        if distance > bestDistance and distance <= Config.MaxDistance then
            best, bestDistance = model, distance
        end
    end
    setTarget(best)
end

local function toggleHighlights()
    Config.HighlightEnabled = not Config.HighlightEnabled
    updateVisuals()
    notify("NPC highlights " .. (Config.HighlightEnabled and "enabled" or "disabled"))
end

local function toggleNameTags()
    Config.NamesEnabled = not Config.NamesEnabled
    updateVisuals()
    notify("NPC name tags " .. (Config.NamesEnabled and "enabled" or "disabled"))
end

local function toggleFOVCircle()
    Config.ShowFOV = not Config.ShowFOV
    updateFOVCircle()
    notify("FOV circle " .. (Config.ShowFOV and "enabled" or "disabled"))
end

local function toggleLineOfSight()
    Config.VisibleOnly = not Config.VisibleOnly
    notify("Line-of-sight check " .. (Config.VisibleOnly and "enabled" or "disabled"))
end

local function changeFOV(amount)
    Config.FOV = math.clamp(Config.FOV + amount, 40, 500)
    updateFOVCircle()
    notify("FOV radius: " .. tostring(Config.FOV))
end

local function changeMaxDistance(amount)
    Config.MaxDistance = math.clamp(Config.MaxDistance + amount, 100, 3000)
    notify("Max distance: " .. tostring(Config.MaxDistance))
end

local function resetFOV()
    Config.FOV = 180
    updateFOVCircle()
    notify("FOV reset to 180")
end

local function resetMaxDistance()
    Config.MaxDistance = 1500
    notify("Max distance reset to 1500")
end

local function cycleAccent()
    accentIndex = (accentIndex % #accentOptions) + 1
    Config.Accent = accentOptions[accentIndex]
    for _, highlight in pairs(State.Highlights) do
        if highlight then
            highlight.FillColor = Config.Accent
        end
    end
    for _, button in pairs(tabButtons) do
        button.TextColor3 = Config.Accent
    end
    notify("Accent color changed")
end

local function resetAccent()
    accentIndex = 1
    Config.Accent = accentOptions[accentIndex]
    for _, highlight in pairs(State.Highlights) do
        if highlight then
            highlight.FillColor = Config.Accent
        end
    end
    notify("Accent color reset")
end

local function clearTrainingVisuals()
    clearAllVisuals()
    notify("Training visuals cleared")
end

local function reapplyTrainingVisuals()
    refreshTrainingData()
    notify("Training visuals refreshed")
end

local function showLocalPosition()
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        notify("Character position unavailable")
        return
    end
    local p = rootPart.Position
    notify(string.format("Position: %.1f, %.1f, %.1f", p.X, p.Y, p.Z), 5)
end

local function setFOVPreset(value)
    Config.FOV = value
    updateFOVCircle()
    notify("FOV preset: " .. tostring(value))
end

local function setDistancePreset(value)
    Config.MaxDistance = value
    notify("Distance preset: " .. tostring(value))
end

local function toggleAutoRefresh()
    Config.AutoRefresh = not (Config.AutoRefresh ~= false)
    notify("Auto refresh " .. (Config.AutoRefresh and "enabled" or "disabled"))
end

local function toggleNotifications()
    Config.Notifications = not Config.Notifications
    if Config.Notifications then
        notify("Notifications enabled")
    end
end

local function refreshCurrentTarget()
    if State.CurrentTarget and isValidTarget(State.CurrentTarget) then
        showTargetDetails()
    else
        State.CurrentTarget = findNearestTarget()
        Config.LockedTarget = State.CurrentTarget
        showTargetDetails()
    end
end

local function selectNearestOnScreen()
    refreshTrainingData()
    local model = findNearestTarget()
    setTarget(model)
end

local function selectNextVisibleTarget()
    refreshTrainingData()
    local visibleTargets = {}
    for _, model in ipairs(State.TargetList) do
        if isOnScreen(model) and (not Config.VisibleOnly or hasLineOfSight(model)) then
            table.insert(visibleTargets, model)
        end
    end
    if #visibleTargets == 0 then
        notify("No visible NPCs")
        return
    end
    local index = table.find(visibleTargets, State.CurrentTarget) or 0
    setTarget(visibleTargets[(index % #visibleTargets) + 1])
end

local function selectNearestLowHealthTarget()
    selectHealthTarget(true)
end

local function selectHighestHealthTarget()
    selectHealthTarget(false)
end

local function hideMenu()
    setMenuVisible(false)
end

local function showMenu()
    setMenuVisible(true)
end

local function toggleMenu()
    setMenuVisible(not State.MenuOpen)
end

local function goHome()
    selectTab("Home")
end

local function goTraining()
    selectTab("Training")
end

local function goVisuals()
    selectTab("Visuals")
end

local function goSettings()
    selectTab("Settings")
end

local function updateTargetStatusNow()
    local model = State.CurrentTarget
    targetStatus.Text = "Current target: " .. (model and model.Name or "none")
    countStatus.Text = "Training targets: " .. tostring(#State.TargetList)
    distanceStatus.Text = "Target distance: " .. (model and string.format("%.1f studs", getDistance(model)) or "--")
end

makeButton(extras, "Cycle to next NPC", 58, function() cycleTarget(1) end, 190)
makeButton(extras, "Cycle to previous NPC", 98, function() cycleTarget(-1) end, 190)
makeButton(extras, "Select closest by world distance", 138, selectClosestWorldTarget, 220)
makeButton(extras, "Select lowest-health NPC", 178, selectNearestLowHealthTarget, 190)
makeButton(extras, "Select highest-health NPC", 218, selectHighestHealthTarget, 190)
makeButton(extras, "Select random NPC", 258, selectRandomTarget, 190)
makeButton(extras, "Select first NPC", 298, selectFirstTarget, 190)
makeButton(extras, "Select last NPC", 338, selectLastTarget, 190)
makeButton(extras, "Select farthest NPC", 378, selectFarthestTarget, 190)
makeButton(extras, "Select nearest on screen", 418, selectNearestOnScreen, 190)
makeButton(extras, "Select next visible NPC", 458, selectNextVisibleTarget, 190)
makeButton(extras, "Show selected NPC details", 498, showTargetDetails, 190)
makeButton(extras, "Refresh selected target status", 538, refreshCurrentTarget, 205)
makeButton(extras, "Clear target selection", 578, clearTargetSelection, 190)
makeButton(extras, "Refresh NPC list", 618, refreshTrainingData, 190)
makeButton(extras, "Count training NPCs", 658, showTargetCount, 190)
makeButton(extras, "Sort NPCs by distance", 698, sortTargetsByDistance, 190)
makeButton(extras, "Sort NPCs by name", 738, sortTargetsByName, 190)
makeButton(extras, "Toggle NPC highlights", 778, toggleHighlights, 190)
makeButton(extras, "Toggle NPC name tags", 818, toggleNameTags, 190)
makeButton(extras, "Toggle FOV circle", 858, toggleFOVCircle, 190)
makeButton(extras, "Toggle line-of-sight check", 898, toggleLineOfSight, 190)
makeButton(extras, "Increase FOV by 25", 938, function() changeFOV(25) end, 190)
makeButton(extras, "Decrease FOV by 25", 978, function() changeFOV(-25) end, 190)
makeButton(extras, "Reset FOV to default", 1018, resetFOV, 190)
makeButton(extras, "Increase max distance", 1058, function() changeMaxDistance(250) end, 190)
makeButton(extras, "Decrease max distance", 1098, function() changeMaxDistance(-250) end, 190)
makeButton(extras, "Reset max distance", 1138, resetMaxDistance, 190)
makeButton(extras, "Cycle accent color", 1178, cycleAccent, 190)
makeButton(extras, "Reset accent color", 1218, resetAccent, 190)
makeButton(extras, "Clear NPC visuals", 1258, clearTrainingVisuals, 190)
makeButton(extras, "Reapply NPC visuals", 1298, reapplyTrainingVisuals, 190)
makeButton(extras, "Show local position", 1338, showLocalPosition, 190)
makeButton(extras, "FOV preset: 100", 1378, function() setFOVPreset(100) end, 190)
makeButton(extras, "FOV preset: 180", 1418, function() setFOVPreset(180) end, 190)
makeButton(extras, "FOV preset: 300", 1458, function() setFOVPreset(300) end, 190)
makeButton(extras, "Distance preset: 500", 1498, function() setDistancePreset(500) end, 190)
makeButton(extras, "Distance preset: 1500", 1538, function() setDistancePreset(1500) end, 190)
makeButton(extras, "Distance preset: 3000", 1578, function() setDistancePreset(3000) end, 190)
makeButton(extras, "Toggle auto refresh", 1618, toggleAutoRefresh, 190)
makeButton(extras, "Toggle notifications", 1658, toggleNotifications, 190)
makeButton(extras, "Hide menu", 1698, hideMenu, 190)
makeButton(extras, "Show menu", 1738, showMenu, 190)
makeButton(extras, "Toggle menu", 1778, toggleMenu, 190)
makeButton(extras, "Go to Home tab", 1818, goHome, 190)
makeButton(extras, "Go to Training tab", 1858, goTraining, 190)
makeButton(extras, "Go to Visuals tab", 1898, goVisuals, 190)
makeButton(extras, "Go to Settings tab", 1938, goSettings, 190)
makeButton(extras, "Update status panel", 1978, updateTargetStatusNow, 190)


local stats = makePage("Stats")
makeSection(stats, "Session analytics", 0)
State.StatsLabels.Target = makeText(stats, "Selected: None", UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 22), Config.Text, 11)
State.StatsLabels.Pinned = makeText(stats, "Pinned: None", UDim2.fromOffset(0, 56), UDim2.new(1, 0, 0, 22), Config.Text, 11)
State.StatsLabels.Summary = makeText(stats, "0 NPCs | 0 alive | 0 visible | 0 in range", UDim2.fromOffset(0, 82), UDim2.new(1, 0, 0, 22), Config.Text, 11)
State.StatsLabels.Session = makeText(stats, "Session: 00:00", UDim2.fromOffset(0, 108), UDim2.new(1, 0, 0, 22), Config.Text, 11)
State.StatsLabels.Selections = makeText(stats, "Selections: 0", UDim2.fromOffset(0, 134), UDim2.new(1, 0, 0, 22), Config.Text, 11)
State.StatsLabels.Average = makeText(stats, "Average NPC health: 0%", UDim2.fromOffset(0, 160), UDim2.new(1, 0, 0, 22), Config.Text, 11)
State.StatsLabels.Info = makeText(stats, "Select a training NPC to view details", UDim2.fromOffset(0, 190), UDim2.new(1, 0, 0, 38), Config.Muted, 10)
makeButton(stats, "Reset session statistics", 242, function()
    Training.resetTrainingStats()
    Training.updateTargetStatsPanel()
    notify("Session statistics reset")
end, 205)

local tools = makePage("Tools")
makeSection(tools, "Target tools", 0)
makeButton(tools, "Select previous NPC", 32, function()
    local model = Training.selectPreviousTarget()
    notify(model and ("Selected " .. model.Name) or "No training NPCs")
end, 190)
makeButton(tools, "Select next NPC", 74, function()
    local model = Training.selectNextTarget()
    notify(model and ("Selected " .. model.Name) or "No training NPCs")
end, 190)
makeButton(tools, "Select random NPC", 116, function()
    local model = Training.selectRandomTarget()
    notify(model and ("Selected " .. model.Name) or "No training NPCs")
end, 190)
makeButton(tools, "Select nearest by world distance", 158, function()
    local model = Training.selectNearestWorldTarget()
    notify(model and ("Selected " .. model.Name) or "No training NPCs")
end, 220)
makeButton(tools, "Pin current NPC", 200, function()
    local model = getCurrentTarget()
    if Training.pinTarget(model) then
        notify("Pinned " .. model.Name)
    else
        notify("Select a valid NPC first")
    end
end, 190)
makeButton(tools, "Unpin NPC", 242, function()
    Training.clearPinnedTarget()
    notify("Pinned target cleared")
end, 190)
makeButton(tools, "Sort by distance", 284, function()
    Training.setSortMode("Distance")
    notify("Sorted by distance")
end, 190)
makeButton(tools, "Sort by health", 326, function()
    Training.setSortMode("Health")
    notify("Sorted by health")
end, 190)

local settings = makePage("Settings")
makeSection(settings, "Interface", 0)
makeText(settings, "Menu toggle: " .. Config.MenuKey.Name, UDim2.fromOffset(0, 32), UDim2.new(1, 0, 0, 24), Config.Text, 12)
makeText(settings, "Target select: " .. Config.TargetKey.Name, UDim2.fromOffset(0, 60), UDim2.new(1, 0, 0, 24), Config.Text, 12)
makeText(settings, "Unload: " .. Config.UnloadKey.Name, UDim2.fromOffset(0, 88), UDim2.new(1, 0, 0, 24), Config.Text, 12)
makeButton(settings, "Reset settings", 132, function()
    Config.FOV = 180
    Config.MaxDistance = 1500
    Config.HighlightEnabled = true
    Config.NamesEnabled = true
    Config.VisibleOnly = true
    Config.ShowFOV = true
    Config.Notifications = true
    rebuildTargetList()
    updateVisuals()
    notify("Settings reset. Reopen tabs to refresh control values.")
end, 190)
makeButton(settings, "Unload RIZZH", 176, function()
    State.Running = false
    clearAllVisuals()
    for _, connection in ipairs(State.Connections) do
        connection:Disconnect()
    end
    gui:Destroy()
end, 190)

selectTab = function(name)
    Config.SelectedTab = name
    for tabName, button in pairs(tabButtons) do
        local selected = tabName == name
        tween(button, 0.12, {
            BackgroundColor3 = selected and Color3.fromRGB(55, 23, 33) or Config.Surface2,
            TextColor3 = selected and Config.Text or Config.Muted
        })
    end
    for pageName, frame in pairs(pageFrames) do
        frame.Visible = pageName == name
    end
end

for name, button in pairs(tabButtons) do
    connect(button.MouseButton1Click, function()
        selectTab(name)
    end)
end

selectTab("Home")

local fovCircle = create("Frame", {
    Name = "FOVCircle",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(Config.FOV * 2, Config.FOV * 2),
    BackgroundTransparency = 1,
    Visible = Config.ShowFOV
}, gui)
round(fovCircle, 1000)
outline(fovCircle, Config.Accent, 0.25, 1.5)
State.FOVCircle = fovCircle

updateFOVCircle = function()
    if not State.FOVCircle then
        return
    end
    State.FOVCircle.Size = UDim2.fromOffset(Config.FOV * 2, Config.FOV * 2)
    State.FOVCircle.Visible = Config.ShowFOV and State.MenuOpen
end

setMenuVisible = function(visible)
    State.MenuOpen = visible
    rootFrame.Visible = visible
    updateFOVCircle()
end


local uiScale = create("UIScale", {
    Scale = 1
}, rootFrame)

local function updateUIScale()
    local viewport = Camera.ViewportSize
    local scaleX = (viewport.X - 24) / 650
    local scaleY = (viewport.Y - 24) / 440
    uiScale.Scale = math.clamp(math.min(scaleX, scaleY, 1), 0.48, 1)
end

local function makeMobileButton(text, position, callback)
    local button = create("TextButton", {
        Name = "Mobile" .. text,
        AnchorPoint = Vector2.new(1, 1),
        Position = position,
        Size = UDim2.fromOffset(76, 42),
        BackgroundColor3 = Color3.fromRGB(35, 20, 27),
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Config.Text,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
        Visible = UserInputService.TouchEnabled
    }, gui)
    round(button, 9)
    outline(button, Config.Accent, 0.25, 1)
    connect(button.Activated, callback)
    return button
end

local mobileMenuButton = makeMobileButton(
    "MENU",
    UDim2.new(1, -14, 1, -64),
    function()
        setMenuVisible(not State.MenuOpen)
    end
)

local mobileTargetButton = makeMobileButton(
    "TARGET",
    UDim2.new(1, -14, 1, -114),
    function()
        rebuildTargetList()
        State.CurrentTarget = findNearestTarget()
        Config.LockedTarget = State.CurrentTarget
        notify(State.CurrentTarget and ("Selected " .. State.CurrentTarget.Name) or "No training NPC found")
    end
)

connect(Camera:GetPropertyChangedSignal("ViewportSize"), updateUIScale)
updateUIScale()

local dragInput
local dragStart
local startPosition

connect(topBar.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.Dragging = true
        dragStart = input.Position
        startPosition = rootFrame.Position
        dragInput = input
    end
end)

connect(UserInputService.InputChanged, function(input)
    if State.Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        rootFrame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
    if State.SliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        State.SliderDragging.Set(input.Position.X)
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.Dragging = false
        State.SliderDragging = nil
    end
end)

connect(closeButton.MouseButton1Click, function()
    setMenuVisible(false)
end)

connect(UserInputService.InputBegan, function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == Config.MenuKey then
        setMenuVisible(not State.MenuOpen)
    elseif input.KeyCode == Config.TargetKey then
        rebuildTargetList()
        State.CurrentTarget = findNearestTarget()
        Config.LockedTarget = State.CurrentTarget
        notify(State.CurrentTarget and ("Selected " .. State.CurrentTarget.Name) or "No training NPC found")
    elseif input.KeyCode == Config.UnloadKey then
        State.Running = false
        clearAllVisuals()
        for _, connection in ipairs(State.Connections) do
            connection:Disconnect()
        end
        gui:Destroy()
    end
end)

connect(RunService.RenderStepped, function()
    if not State.Running then
        return
    end
    updateFOVCircle()
    local now = os.clock()
    if now - State.LastTargetUpdate >= State.TargetUpdateRate then
        State.LastTargetUpdate = now
        if Config.AutoRefresh ~= false then
            rebuildTargetList()
            updateVisuals()
        end
        if State.CurrentTarget and not isValidTarget(State.CurrentTarget) then
            State.CurrentTarget = nil
            Config.LockedTarget = nil
        end
        local current = getCurrentTarget()
        for _, model in ipairs(State.TargetList) do
            Training.recordTargetHealth(model)
        end
        targetStatus.Text = "Current target: " .. (current and current.Name or "none")
        countStatus.Text = "Training targets: " .. tostring(#State.TargetList)
        distanceStatus.Text = "Target distance: " .. (current and formatDistance(getDistance(current)) or "--")
        Training.updateTargetStatsPanel()
    end
end)

local folder = getTargetFolder()
if folder then
    connect(folder.ChildAdded, function()
        task.defer(function()
            rebuildTargetList()
            updateVisuals()
        end)
    end)
    connect(folder.ChildRemoved, function(child)
        clearVisual(child)
        if State.CurrentTarget == child then
            State.CurrentTarget = nil
            Config.LockedTarget = nil
        end
        task.defer(rebuildTargetList)
    end)
end

refreshTrainingData()
Training.updateTargetStatsPanel()
updateVisuals()
updateFOVCircle()
notify("RIZZH private training panel loaded", 4)
