--[[--
Propagate Parameters - v1.3
by Dominik Bargiel dominikbargiel97@gmail.com
-------------------------------------------------------------------------------
Copyright Notice:
-------------------------------------------------------------------------------
Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, subject to
the following conditions:

1. The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

Copyright © 2025
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
Description:
-------------------------------------------------------------------------------
A tool that captures parameter changes on the active node and propagates them 
to selected nodes.

Features:
- Simple window-based interface
- Captures parameter changes on press and applies on command
- Universal handling of all parameter types including FuID and enumeration values
- Handles table parameters with proper comparison
- Special handling for Loader/Saver tools and Point parameters
- Connection propagation - connects/disconnects inputs to the same sources
- Output connection propagation - connects outputs to the same targets
- Expression propagation support
- Keyframe and animation support
- Iterates all tool inputs for universal change detection
Usage:
- Select 2 or more nodes
- Press I to open the window
- Make parameter changes, connect/disconnect inputs/outputs, or modify expressions on the active node
- Click "Apply Changes" to propagate to all selected nodes
- Press ESC, I, or Ctrl+W to cancel/close
-------------------------------------------------------------------------------
Version History:
-------------------------------------------------------------------------------
v1.4 - 2026-06-24
    - Live Mode now remembers its last enabled/disabled state between sessions
    - Stores the preference in the user's platform config folder
v1.3 - 2026-03-21
    - Single-axis Point propagation: changing only X, Y, or Z on the source preserves
    the other axes on targets (static points, BezierSpline keyframes, and Path-clone path)
v1.2 - 2026-01-17
    - Added handling for internal animation connections (BezierSpline/Path). 
    This clones the internal Path per target and also writes point values on the parameter.
v1.1 - 2025-12-29
    - Fixed false positive "disconnected" detection for animated parameters
    - Fixed false positive value change detection for connected inputs
    - Filtered out internal "Clone" parameters (e.g., BlendClone) from change detection
    - Fixed duplicate connection change log messages
    - Fixed redundant "became animated" detection when connection change is already detected
    - Fixed keyframe deletion propagation - now properly disconnects BezierSpline animation
    - Fixed issue where connections were incorrectly detected as animations
    - Add more hotkeys for closing the window (Escape, I, Ctrl+W). "I" works without the window ins focus
    - Remove "Cancel" button
v1.0 - 2025-08-03
    - Better live mode handling
    - Better handling of keyframes
v0.8 - 2025-01-03
    - Added output and input connection propagation functionality
    - Can now propagate connections made to the active tool's output to all selected tools
    - Useful for connecting multiple nodes to the same target (e.g., MultiMerge)
    - Fixed keyframe linking issue: keyframes now remain independent between tools
    - Improved connection detection to prevent false positives from animated parameters
v0.7 - 2025-06-02
    - Added handling for Point parameters for keyframes
v0.6 - 2025-05-26
    - Added connection propagation functionality
    - Connections are now detected and propagated to selected nodes
    - Fixed issue where connections were incorrectly detected as animations
    - Improved change detection priority: connections > expressions > parameters
v0.5 - 2025-05-18
    - Added handling for expressions
    - Refactored code to improve readability and maintainability
v0.4 - 2025-05-04
    - Added handling for keyframes
v0.3 - 2025-05-01
    - Added Live mode
v0.2 - 2025-04-27
    - Improved table parameter handling (process simple tables, skip nested tables)
    - More consistent value comparison across parameter types
    - Fixed detection of changes when switching to/from default values
    - Added special handling for Loader tools and Clip parameters
    - Iterates all tool inputs for universal change detection
v0.1 - 2025-04-26
    - Initial release
--]]--

-- Constants
local TIMER_INTERVAL = 250  -- ms
local NOTIFICATION_DURATION = 1.5  -- seconds
local UI_WIDTH = 350
local UI_HEIGHT = 100
local INCLUDE_EXPRESSIONS = true  -- Control whether to include expressions in propagation
local INCLUDE_CONNECTIONS = true  -- Control whether to include connections in propagation
local INCLUDE_OUTPUT_CONNECTIONS = true  -- Control whether to include output connections in propagation
local ALLOW_KEYFRAME_OVERWRITE = true  -- Allow overwriting existing keyframes when propagating keyframes
local DEBUG_MODE = false  -- Enable detailed debug logging (set to false to disable)
local SETTINGS_DIR_NAME = "Propagate"
local SETTINGS_FILE_NAME = "Propagate_settings.ini"
local LEGACY_SETTINGS_FILE_NAME = "settings.ini"
local APPLY_BUTTON_ENABLED_STYLESHEET = [[
    QPushButton {
        background-color: rgb(60, 120, 60);
        color: rgb(200, 200, 200);
        border: 1px solid rgb(170, 170, 170);
        border-radius: 7px;
        font-size: 11px;
    }
    QPushButton:hover {
        background-color: rgb(80, 140, 80);
    }
    QPushButton:pressed {
        background-color: rgb(40, 100, 40);
    }
]]
local APPLY_BUTTON_DISABLED_STYLESHEET = [[
    QPushButton {
        background-color: rgb(55, 55, 55);
        color: rgb(120, 120, 120);
        border: 1px solid rgb(75, 75, 75);
        border-radius: 7px;
        font-size: 11px;
    }
]]

------------------------
-- Utility Functions
------------------------

-- Helper function to extract the actual comparable value from a parameter
local function extractActualValue(paramInput, time)
    local value = nil
    pcall(function()
        local val = paramInput[time]
        if type(val) == "table" then
            -- FuID/Enum often store the real value at index 1
            if val.__ctor == "FuID" or val.__ctor == "Enumeration" then
                value = val[1]
            else
                value = val -- Store the table itself for comparison
            end
        else
            value = val
        end
    end)
    return value
end

local function addPath(paths, path)
    if path and path ~= "" then
        for _, existingPath in ipairs(paths) do
            if existingPath == path then
                return
            end
        end
        table.insert(paths, path)
    end
end

local function getConfigBasePaths()
    local separator = package.config:sub(1, 1)
    local homePath = os.getenv("HOME")
    local paths = {}

    if separator == "\\" then
        addPath(paths, os.getenv("APPDATA"))

        local userProfile = os.getenv("USERPROFILE")
        if userProfile and userProfile ~= "" then
            addPath(paths, userProfile .. separator .. "AppData" .. separator .. "Roaming")
            addPath(paths, userProfile)
        end
    else
        local ostype = os.getenv("OSTYPE")
        local jitOS = jit and jit.os or nil
        local isMacOS = jitOS == "OSX" or jitOS == "Darwin" or
            (ostype and ostype:lower():find("darwin", 1, true))

        if not isMacOS and homePath and homePath:match("^/Users/") then
            isMacOS = true
        end

        if isMacOS then
            if homePath and homePath ~= "" then
                addPath(paths, homePath .. separator .. "Library" .. separator .. "Application Support")
                addPath(paths, homePath)
            end
        else
            addPath(paths, os.getenv("XDG_CONFIG_HOME"))
            if homePath and homePath ~= "" then
                addPath(paths, homePath .. separator .. ".config")
                addPath(paths, homePath)
            end
        end
    end

    addPath(paths, ".")
    return paths
end

local function getSettingsWritePaths()
    local separator = package.config:sub(1, 1)
    local paths = {}

    for _, basePath in ipairs(getConfigBasePaths()) do
        addPath(paths, basePath .. separator .. SETTINGS_FILE_NAME)
    end

    return paths
end

local function getSettingsReadPaths()
    local separator = package.config:sub(1, 1)
    local paths = getSettingsWritePaths()

    -- Read the original nested location too, but do not create it. Creating it
    -- with os.execute can flash a console window on Windows.
    for _, basePath in ipairs(getConfigBasePaths()) do
        addPath(paths, basePath .. separator .. SETTINGS_DIR_NAME .. separator .. LEGACY_SETTINGS_FILE_NAME)
    end

    return paths
end

local function readLiveModePreference(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local contents = file:read("*a") or ""
    file:close()

    if contents:match("live_mode%s*=%s*1") then
        return true
    end

    if contents:match("live_mode%s*=%s*0") then
        return false
    end

    return nil
end

local function loadLiveModePreference()
    for _, settingsPath in ipairs(getSettingsReadPaths()) do
        local value = readLiveModePreference(settingsPath)
        if value ~= nil then
            return value
        end
    end

    return false
end

local function saveLiveModePreference(enabled)
    for _, settingsPath in ipairs(getSettingsWritePaths()) do
        local file = io.open(settingsPath, "w")
        if file then
            file:write("live_mode=" .. (enabled and "1" or "0") .. "\n")
            file:close()
            return true
        end
    end

    if DEBUG_MODE then print("[Propagate] Failed to save settings") end
    return false
end

-- Helper function to compare tables deeply
local function areTablesEqual(t1, t2)
    if t1 == t2 then return true end
    if type(t1) ~= "table" or type(t2) ~= "table" then return false end
    
    local visited = {}
    for k, v in pairs(t1) do
        visited[k] = true
        if type(v) == "table" and type(t2[k]) == "table" then
            if not areTablesEqual(v, t2[k]) then return false end
        else
            if v ~= t2[k] then return false end
        end
    end
    
    for k, _ in pairs(t2) do
        if not visited[k] then return false end
    end
    
    return true
end

-- Helper function to compare keyframe tables
local function areKeyframesEqual(k1, k2, paramName)
    if k1 == k2 then return true end
    if type(k1) ~= "table" or type(k2) ~= "table" then return false end
    if #k1 ~= #k2 then return false end

    -- Check each keyframe time and value
    for i = 1, #k1 do
        local kf1 = k1[i]
        local kf2 = k2[i]
        
        -- Handle both old format (just times) and new format ({time=x, value=y})
        local time1 = type(kf1) == "table" and kf1.time or kf1
        local time2 = type(kf2) == "table" and kf2.time or kf2
        local value1 = type(kf1) == "table" and kf1.value or nil
        local value2 = type(kf2) == "table" and kf2.value or nil
        
        if time1 ~= time2 then return false end
        
        -- Compare values if both are present
        if value1 ~= nil and value2 ~= nil then
            if tostring(value1) ~= tostring(value2) then return false end
        end
    end

    return true
end

-- Point helpers: single-axis propagation for INPS_DataType "Point"
local function extractPointXYZ(val)
    if type(val) ~= "table" then return nil end
    local x, y, z = nil, nil, nil
    pcall(function() x = val.X end)
    pcall(function() y = val.Y end)
    pcall(function() z = val.Z end)
    if x == nil then pcall(function() x = val[1] end) end
    if y == nil then pcall(function() y = val[2] end) end
    if z == nil then pcall(function() z = val[3] end) end
    if x == nil or y == nil then return nil end
    return x, y, z
end

-- Returns { x=bool, y=bool, z=bool } or nil if values are not comparable point tables
local function diffPointAxes(prevVal, currVal)
    local px, py, pz = extractPointXYZ(prevVal)
    local cx, cy, cz = extractPointXYZ(currVal)
    if px == nil or py == nil or cx == nil or cy == nil then
        return nil
    end
    local axes = { x = (px ~= cx), y = (py ~= cy), z = false }
    if pz ~= nil or cz ~= nil then
        axes.z = (pz ~= cz)
    end
    return axes
end

-- Merge source point into target using axis flags; axes nil means use source as-is (caller should skip merge)
local function mergePointValues(targetVal, sourceVal, axes)
    if not axes then return sourceVal end
    local tx, ty, tz = extractPointXYZ(targetVal)
    local sx, sy, sz = extractPointXYZ(sourceVal)
    if sx == nil or sy == nil then return sourceVal end
    if tx == nil or ty == nil then
        if sz ~= nil then return { sx, sy, sz } end
        return { sx, sy }
    end
    local rx = axes.x and sx or tx
    local ry = axes.y and sy or ty
    local rz
    if axes.z then
        rz = sz
        if rz == nil then rz = tz end
    else
        rz = tz
        if rz == nil and sz ~= nil then rz = sz end
    end
    if rz ~= nil then return { rx, ry, rz } end
    return { rx, ry }
end

-- Normalized plain table for SetInput / tool[name] assignment (same rules as Path clone path)
local function normalizePointToTable(val)
    if val == nil then return nil end
    local x, y, z = extractPointXYZ(val)
    if x == nil or y == nil then return nil end
    if z ~= nil then return { x, y, z } end
    return { x, y }
end

-- Helper function to detect internal animation connections (not real tool links)
local function isInternalAnimationConnection(sourceTool, targetToolName, paramName, paramType)
    if not sourceTool then return false end
    local attrs = {}
    pcall(function() attrs = sourceTool:GetAttrs() or {} end)
    local sourceToolID = attrs.TOOLS_RegID or ""
    local sourceToolName = attrs.TOOLS_Name or ""
    
    -- BezierSpline is always an internal animation modifier
    if sourceToolID == "BezierSpline" then
        return true
    end
    
    -- Path is used for internal Point/Center animation; treat as internal modifier
    -- Some builds report non-Path RegIDs, so also fall back to name check.
    if sourceToolID == "Path" or sourceToolName:match("^Path%d*$") then
        return true
    end
    
    return false
end

------------------------
-- Parameter Module
------------------------
local ParameterManager = {}

-- Initialize parameter storage
function ParameterManager:init(activeTool, comp)
    self.parameterInfo = {}
    self.expressionInfo = {}  -- Store expression data
    self.connectionInfo = {}  -- Store connection data
    self.outputConnectionInfo = {}  -- Store output connection data
    self.changesSinceLastUpdate = {}
    self.expressionChangesSinceLastUpdate = {}  -- Track expression changes
    self.connectionChangesSinceLastUpdate = {}  -- Track connection changes
    self.outputConnectionChangesSinceLastUpdate = {}  -- Track output connection changes
    self.activeTool = activeTool
    self.comp = comp
    
    -- Cache initial values
    self:cacheInitialState()
    
    return self
end

-- Store initial values and info for all tool parameters
function ParameterManager:cacheInitialState()
    if DEBUG_MODE then print("[Propagate] Caching initial parameter states and types...") end
    local activeToolName = ""
    pcall(function() activeToolName = self.activeTool:GetAttrs().TOOLS_Name or "" end)
    local allInputs = self.activeTool:GetInputList() or {}
    for _, input in pairs(allInputs) do
        local name = input:GetAttrs().INPS_ID
        if name then
            local isOutput = (name == "Output")
            local initialValue = nil
            local initialKeyframes = nil
            local isAnimated = false
            local inputType = ""
            local isConnected = false
            local sourceOutput = nil
            local sourceTool = nil

            if not isOutput then
                initialValue = extractActualValue(input, self.comp.CurrentTime)
                pcall(function() inputType = input:GetAttrs().INPS_DataType or "" end)
                
                -- Check connection state
                local attrs = {}
                pcall(function() attrs = input:GetAttrs() or {} end)
                isConnected = attrs.INPB_Connected or false
                
                -- Handle connection info if enabled and parameter is connected
                if isConnected and INCLUDE_CONNECTIONS then
                    -- Get source information
                    pcall(function()
                        sourceOutput = input:GetConnectedOutput()
                        if sourceOutput then
                            sourceTool = sourceOutput:GetTool()
                        end
                    end)
                    
                    -- Validate real connections: Fusion can report parameters as "connected" when they're
                    -- just animated, so we need to verify this is actually a connection to another tool
                    -- This is the same validation done in findChangedConnections()
                    if sourceTool and sourceOutput then
                        local isRealConnection = false
                        
                        if sourceTool ~= self.activeTool then
                            local isInternal = isInternalAnimationConnection(sourceTool, activeToolName, name, inputType)
                            if not isInternal then
                                isRealConnection = true
                            end
                        end
                        
                        if isRealConnection then
                            if DEBUG_MODE then print("[Propagate] Found connection for " .. name .. " from " .. sourceTool:GetAttrs().TOOLS_Name) end
                            self.connectionInfo[name] = {
                                isConnected = true,
                                sourceTool = sourceTool,
                                sourceOutput = sourceOutput,
                                inputObj = input
                            }
                        else
                            -- Not a real connection (likely animated parameter), treat as disconnected
                            isConnected = false
                            sourceOutput = nil
                            sourceTool = nil
                            if DEBUG_MODE then print("[Propagate] Ignoring false connection for " .. name .. " (animated parameter)") end
                        end
                    else
                        -- No valid source found, treat as disconnected
                        isConnected = false
                    end
                end
                
                -- Check for initial keyframes only if not connected
                if not isConnected then
                    pcall(function()
                        local keys = input:GetKeyFrames()
                        if keys and #keys > 0 then
                            -- Filter out invalid keyframes and fetch values only for initial setup
                            local realKeys = {}
                            for _, time in ipairs(keys) do
                                if math.abs(time) < 999999999 then
                                    local value = nil
                                    pcall(function() value = input[time] end)
                                    table.insert(realKeys, {time = time, value = value})
                                end
                            end
                            initialKeyframes = realKeys
                            isAnimated = (#realKeys > 0)
                        end
                    end)
                end
                
                -- Check for expressions if enabled
                if INCLUDE_EXPRESSIONS then
                    local initialExpression = nil
                    pcall(function()
                        -- GetExpression() returns the expression text or nil if none
                        initialExpression = input:GetExpression()
                    end)
                    
                    if initialExpression then
                        if DEBUG_MODE then print("[Propagate] Found expression for " .. name .. ": " .. initialExpression) end
                        self.expressionInfo[name] = {
                            expression = initialExpression,
                            inputObj = input
                        }
                    end
                end
            end

            self.parameterInfo[name] = {
                last = initialValue,         -- Last known extracted value (if not animated)
                lastKeyframes = initialKeyframes, -- Last known keyframes (if animated)
                isAnimated = isAnimated,     -- Is the parameter currently animated?
                isConnected = isConnected,   -- Is the parameter currently connected?
                type = inputType,            -- Cached data type
                inputObj = input,            -- Cached input object (on active tool)
                isOutput = isOutput          -- Flag for Output pseudo-input
            }
        end
    end
    
    -- Cache initial output connections if enabled
    if INCLUDE_OUTPUT_CONNECTIONS then
        self:cacheInitialOutputConnections()
    end
    
    if DEBUG_MODE then print("[Propagate] Caching complete.") end
end

-- Cache initial output connections
function ParameterManager:cacheInitialOutputConnections()
    local mainOutput = self.activeTool.Output
    if not mainOutput then
        return
    end
    
    -- Get all outputs of the active tool
    local outputList = self.activeTool:GetOutputList() or {}
    
    for _, output in pairs(outputList) do
        local outputName = output:GetAttrs().OUTS_ID or "Output"
        
        -- Get connected inputs for this output
        local connectedInputs = {}
        pcall(function()
            local inputList = output:GetConnectedInputs() or {}
            for _, input in pairs(inputList) do
                local targetTool = input:GetTool()
                local inputName = input:GetAttrs().INPS_ID
                if targetTool and inputName then
                    table.insert(connectedInputs, {
                        targetTool = targetTool,
                        targetInput = input,
                        inputName = inputName
                    })
                    print("[Propagate] Found output connection: " .. outputName .. " -> " .. 
                          targetTool:GetAttrs().TOOLS_Name .. "." .. inputName)
                end
            end
        end)
        
        if #connectedInputs > 0 then
            self.outputConnectionInfo[outputName] = {
                outputObj = output,
                connectedInputs = connectedInputs
            }
        end
    end
end

-- Find changed connections by comparing current and cached connection state
function ParameterManager:findChangedConnections(isLive)
    -- Clear the reusable changes table for connections
    for k in pairs(self.connectionChangesSinceLastUpdate) do 
        self.connectionChangesSinceLastUpdate[k] = nil 
    end
    
    if not INCLUDE_CONNECTIONS then
        return self.connectionChangesSinceLastUpdate
    end
    
    isLive = isLive or false
    local activeToolName = ""
    pcall(function() activeToolName = self.activeTool:GetAttrs().TOOLS_Name or "" end)
    
    -- Check each parameter for connection changes
    for name, info in pairs(self.parameterInfo) do
        if not info.isOutput and info.inputObj then
            local input = info.inputObj
            local wasConnected = info.isConnected
            
            -- Get current connection state
            local attrs = {}
            pcall(function() attrs = input:GetAttrs() or {} end)
            local isCurrentlyConnected = attrs.INPB_Connected or false
            
            local currentSourceTool = nil
            local currentSourceOutput = nil
            
            if isCurrentlyConnected then
                pcall(function()
                    currentSourceOutput = input:GetConnectedOutput()
                    if currentSourceOutput then
                        currentSourceTool = currentSourceOutput:GetTool()
                    end
                end)
            end
            
            -- Validate real connections: Fusion can report parameters as "connected" when they're
            -- just animated, so we need to verify this is actually a connection to another tool
            if isCurrentlyConnected and currentSourceTool then
                local currentTool = input:GetTool()
                local isRealConnection = false
                
                if currentTool and currentSourceTool ~= currentTool then
                    local isInternal = isInternalAnimationConnection(currentSourceTool, activeToolName, name, info.type)
                    if not isInternal then
                        isRealConnection = true
                    end
                end
                
                -- If not a real connection, treat as disconnected
                if not isRealConnection then
                    isCurrentlyConnected = false
                    currentSourceTool = nil
                    currentSourceOutput = nil
                end
            end
            
            -- Check if connection state changed
            local connectionChanged = false
            local changeType = ""
            
            if isCurrentlyConnected and not wasConnected then
                -- Became connected
                connectionChanged = true
                changeType = " (became connected)"
            elseif not isCurrentlyConnected and wasConnected then
                -- Became disconnected
                connectionChanged = true
                changeType = " (became disconnected)"
            elseif isCurrentlyConnected and wasConnected then
                -- Check if source changed
                local previousConnectionInfo = self.connectionInfo[name]
                if previousConnectionInfo and currentSourceTool then
                    local previousSourceTool = previousConnectionInfo.sourceTool
                    if previousSourceTool ~= currentSourceTool then
                        connectionChanged = true
                        changeType = " (connection source changed)"
                    end
                end
            end
            
            if connectionChanged then
                if not isLive then
                    print("[Propagate] Detected connection change in " .. name .. changeType)
                    if isCurrentlyConnected and currentSourceTool then
                        print("[Propagate] - Connected to: " .. currentSourceTool:GetAttrs().TOOLS_Name)
                    elseif not isCurrentlyConnected then
                        print("[Propagate] - Disconnected")
                    end
                end
                
                -- Add to changes table
                self.connectionChangesSinceLastUpdate[name] = {
                    isConnected = isCurrentlyConnected,
                    sourceTool = currentSourceTool,
                    sourceOutput = currentSourceOutput,
                    inputObj = input
                }
            end
        end
    end
    
    return self.connectionChangesSinceLastUpdate
end

-- Find changed output connections by comparing current and cached output connection state
function ParameterManager:findChangedOutputConnections(isLive)
    -- Clear the reusable changes table for output connections
    for k in pairs(self.outputConnectionChangesSinceLastUpdate) do 
        self.outputConnectionChangesSinceLastUpdate[k] = nil 
    end
    
    if not INCLUDE_OUTPUT_CONNECTIONS then
        return self.outputConnectionChangesSinceLastUpdate
    end
    
    isLive = isLive or false
    
    -- Get all outputs of the active tool
    local outputList = self.activeTool:GetOutputList() or {}
    
    for _, output in pairs(outputList) do
        local outputName = output:GetAttrs().OUTS_ID or "Output"
        
        -- Get current connected inputs for this output
        local currentConnectedInputs = {}
        pcall(function()
            local inputList = output:GetConnectedInputs() or {}
            for _, input in pairs(inputList) do
                local targetTool = input:GetTool()
                local inputName = input:GetAttrs().INPS_ID
                if targetTool and inputName then
                    table.insert(currentConnectedInputs, {
                        targetTool = targetTool,
                        targetInput = input,
                        inputName = inputName
                    })
                end
            end
        end)
        
        -- Compare with previous state
        local previousInfo = self.outputConnectionInfo[outputName]
        local previousConnectedInputs = previousInfo and previousInfo.connectedInputs or {}
        
        -- Check if connections changed
        local connectionsChanged = false
        
        -- Check if number of connections changed
        if #currentConnectedInputs ~= #previousConnectedInputs then
            connectionsChanged = true
        else
            -- Check if any specific connections changed
            for i, currentConn in ipairs(currentConnectedInputs) do
                local found = false
                for j, prevConn in ipairs(previousConnectedInputs) do
                    if currentConn.targetTool == prevConn.targetTool and 
                       currentConn.inputName == prevConn.inputName then
                        found = true
                        break
                    end
                end
                if not found then
                    connectionsChanged = true
                    break
                end
            end
        end
        
        if connectionsChanged then
            if not isLive then
                print("[Propagate] Detected output connection change for " .. outputName)
                print("[Propagate] - Previous connections: " .. #previousConnectedInputs)
                print("[Propagate] - Current connections: " .. #currentConnectedInputs)
                for _, conn in ipairs(currentConnectedInputs) do
                    print("[Propagate] - Connected to: " .. conn.targetTool:GetAttrs().TOOLS_Name .. "." .. conn.inputName)
                end
            end
            
            -- Add to changes table
            self.outputConnectionChangesSinceLastUpdate[outputName] = {
                outputObj = output,
                connectedInputs = currentConnectedInputs
            }
        end
    end
    
    return self.outputConnectionChangesSinceLastUpdate
end

-- Find changed parameters by comparing current and the cached last state
function ParameterManager:findChangedParameters(isLive)
    -- Clear the reusable changes table
    for k in pairs(self.changesSinceLastUpdate) do self.changesSinceLastUpdate[k] = nil end

    local currentTime = self.comp.CurrentTime
    isLive = isLive or false -- Default to not live

    -- First check for expression changes to know which parameters to skip
    local expressionChanges = {}
    if INCLUDE_EXPRESSIONS then
        expressionChanges = self:findChangedExpressions(isLive)
    end
    
    -- Use already-detected connection changes (from prior findChangedConnections call)
    -- to avoid duplicate logging and redundant detection
    local connectionChanges = self.connectionChangesSinceLastUpdate or {}

    -- Iterate through the cached parameter info
    for name, info in pairs(self.parameterInfo) do
        -- Skip the Output pseudo-parameter or others we don't handle
        -- Skip parameters that have expression changes
        -- Skip connected parameters (unless their connection state changed) to avoid false positive detection
        -- Skip "Clone" parameters (e.g., BlendClone, SizeClone) - these are internal mirrors of actual parameters
        -- Skip parameters that already have a connection change detected (to avoid redundant "became animated" detection)
        local skipDueToConnection = info.isConnected and not connectionChanges[name]
        local hasConnectionChange = connectionChanges[name] ~= nil
        local isCloneParameter = string.sub(name, -5) == "Clone"
        if not info.isOutput and info.inputObj and not expressionChanges[name] and not skipDueToConnection and not isCloneParameter and not hasConnectionChange then
            local input = info.inputObj -- Use cached input object
            local previousValue = info.last
            local previousKeyframes = info.lastKeyframes -- Get previous keyframes
            local wasAnimated = info.isAnimated       -- Get previous animation state

            -- Get the current value using the same extraction logic
            local currentValue = extractActualValue(input, currentTime)
            -- Get current keyframes
            local currentKeyframes = nil
            local keyframeSuccess = pcall(function() 
                local keys = input:GetKeyFrames()
                if keys then
                    currentKeyframes = keys
                end
            end)
            
            if DEBUG_MODE and not keyframeSuccess then
                print("[DEBUG] Parameter " .. name .. " - GetKeyFrames() failed")
            end
            
            -- Filter out invalid keyframes: Fusion creates extreme time values (-1000000000, 1000000000)
            -- for connected parameters which aren't real animation keyframes
            local realKeyframes = {}
            if currentKeyframes and #currentKeyframes > 0 then
                for _, time in ipairs(currentKeyframes) do
                    if math.abs(time) < 999999999 then
                        table.insert(realKeyframes, time)
                    end
                end
            end
            
            -- Ensure we always have a boolean value
            local isCurrentlyAnimated = (#realKeyframes > 0)
            

            
            -- Use real keyframes for change detection and storage
            if isCurrentlyAnimated then
                currentKeyframes = realKeyframes
            end

            -- Determine if the parameter has changed compared to the last known state
            local changed = false
            local actualCurrentValueToStore = nil -- Will hold either single value or keyframes table

            if isCurrentlyAnimated then
                -- Currently animated: Compare against previous source state
                if wasAnimated then
                    -- Get current keyframes with values for comparison
                    local currentKeyframesWithValues = {}
                    for _, time in ipairs(currentKeyframes) do
                        local value = nil
                        pcall(function() value = input[time] end)
                        table.insert(currentKeyframesWithValues, {time = time, value = value})
                    end
                    
                    -- Compare against stored source baseline (not applied state)
                    changed = not areKeyframesEqual(currentKeyframesWithValues, previousKeyframes, name)
                    if changed then
                        currentKeyframes = currentKeyframesWithValues
                        if DEBUG_MODE then print("[DEBUG] Parameter " .. name .. " keyframes changed from source") end
                    else
                        if DEBUG_MODE then print("[DEBUG] Parameter " .. name .. " keyframes unchanged - no propagation needed") end
                    end
                else
                    changed = true -- Became animated
                    if DEBUG_MODE then print("[DEBUG] Parameter " .. name .. " became animated") end
                end
                
                if changed then
                    -- Fetch values only when we know there's a change
                    if type(currentKeyframes[1]) ~= "table" then
                        -- Convert times to time+value format
                        local keyframesWithValues = {}
                        for _, time in ipairs(currentKeyframes) do
                            local value = nil
                            pcall(function() value = input[time] end)
                            table.insert(keyframesWithValues, {time = time, value = value})
                        end
                        currentKeyframes = keyframesWithValues
                    end
                    
                    -- Create independent copy
                    actualCurrentValueToStore = {}
                    for i, kf in ipairs(currentKeyframes) do
                        actualCurrentValueToStore[i] = {time = kf.time, value = kf.value}
                    end
                end
            else
                -- Currently not animated: Check if it was animated before or if the static value changed
                if wasAnimated then
                    changed = true -- Became static
                else
                    -- Compare static values
                    if type(previousValue) ~= "table" or type(currentValue) ~= "table" then
                        changed = tostring(currentValue) ~= tostring(previousValue)
                    else
                        changed = not areTablesEqual(currentValue, previousValue)
                    end
                end
                if changed then
                    -- Get the current static value
                    local success = pcall(function() 
                        actualCurrentValueToStore = input[currentTime] 
                    end)
                    if not success then
                        pcall(function() 
                            actualCurrentValueToStore = currentValue 
                        end)
                    end
                end
            end

            if changed then
                -- Log parameter changes (only when not in live mode)
                if not isLive then
                    local changeType = ""
                    if isCurrentlyAnimated and not wasAnimated then changeType = " (became animated)"
                    elseif not isCurrentlyAnimated and wasAnimated then changeType = " (became static)"
                    elseif isCurrentlyAnimated then changeType = " (animation changed)"
                    else changeType = " (value changed)" end

                                    if DEBUG_MODE then 
                    print("[Propagate] Detected change in " .. name .. changeType)
                    if isCurrentlyAnimated then
                        print("[Propagate] - Current Keyframes: " .. #actualCurrentValueToStore .. " keys")
                    else
                        print("[Propagate] - Previous: " .. tostring(previousValue))
                        print("[Propagate] - Current:  " .. tostring(currentValue))
                    end
                end
                end

                if DEBUG_MODE then
                    print("[DEBUG] Creating change data for " .. name .. " - isAnimated: " .. tostring(isCurrentlyAnimated) .. ", value type: " .. type(actualCurrentValueToStore))
                end

                -- Point: record per-axis changes for single-axis propagation
                local pointAxesStatic = nil
                if info.type == "Point" and actualCurrentValueToStore ~= nil then
                    if isCurrentlyAnimated then
                        local prevByTime = {}
                        if type(previousKeyframes) == "table" then
                            for _, pkf in ipairs(previousKeyframes) do
                                local tm = type(pkf) == "table" and pkf.time or nil
                                local vl = type(pkf) == "table" and pkf.value or nil
                                if type(tm) == "number" then
                                    prevByTime[tm] = vl
                                end
                            end
                        end
                        for _, pkf in ipairs(actualCurrentValueToStore) do
                            if type(pkf) == "table" and type(pkf.time) == "number" then
                                local pv = prevByTime[pkf.time]
                                if pv ~= nil and pkf.value ~= nil then
                                    pkf.axes = diffPointAxes(pv, pkf.value)
                                else
                                    pkf.axes = nil
                                end
                            end
                        end
                    else
                        pointAxesStatic = diffPointAxes(previousValue, actualCurrentValueToStore)
                    end
                end

                -- Add to reusable changes table
                self.changesSinceLastUpdate[name] = {
                    value = actualCurrentValueToStore, -- Full parameter value or keyframe table
                    extracted = currentValue,          -- Simplified extracted value (for potential non-animated use)
                    type = info.type,                  -- Pass the cached type
                    isAnimated = isCurrentlyAnimated,  -- Store animation state
                    pointAxes = pointAxesStatic        -- Static Point only: which axes changed (nil = full point)
                }
                
                if DEBUG_MODE then
                    print("[DEBUG] Stored change data - isAnimated: " .. tostring(self.changesSinceLastUpdate[name].isAnimated))
                end
            end
        end
    end

    return self.changesSinceLastUpdate
end

-- Find changed expressions by comparing current and cached expression state
function ParameterManager:findChangedExpressions(isLive)
    -- Clear the reusable changes table for expressions
    for k in pairs(self.expressionChangesSinceLastUpdate) do 
        self.expressionChangesSinceLastUpdate[k] = nil 
    end
    
    if not INCLUDE_EXPRESSIONS then
        return self.expressionChangesSinceLastUpdate
    end
    
    isLive = isLive or false
    
    -- Check each input that had an expression initially
    for name, info in pairs(self.expressionInfo) do
        local inputObj = info.inputObj
        local previousExpr = info.expression
        
        -- Get current expression
        local currentExpr = nil
        pcall(function()
            currentExpr = inputObj:GetExpression()
        end)
        
        -- Check if expression changed
        if currentExpr ~= previousExpr then
            if not isLive then
                print("[Propagate] Detected expression change for " .. name)
                if previousExpr then
                    print("[Propagate] - Previous: " .. previousExpr)
                else
                    print("[Propagate] - Previous: <none>")
                end
                
                if currentExpr then
                    print("[Propagate] - Current: " .. currentExpr)
                else
                    print("[Propagate] - Current: <none>")
                end
            end
            
            -- Add to changes table
            self.expressionChangesSinceLastUpdate[name] = {
                expression = currentExpr,
                inputObj = inputObj
            }
        end
    end
    
    -- Check all parameters that don't have expressions in expressionInfo
    for name, info in pairs(self.parameterInfo) do
        -- Skip if it's an output or already in expressionInfo or already detected
        if info.isOutput or 
           self.expressionInfo[name] or 
           self.expressionChangesSinceLastUpdate[name] then
            goto continue
        end
        
        local inputObj = info.inputObj
        if not inputObj then goto continue end
        
        -- Check if this input now has an expression
        local currentExpr = nil
        pcall(function()
            currentExpr = inputObj:GetExpression()
        end)
        
        if currentExpr then
            if not isLive then
                print("[Propagate] Detected new expression added to " .. name .. ": " .. currentExpr)
            end
            
            -- Add to changes table
            self.expressionChangesSinceLastUpdate[name] = {
                expression = currentExpr,
                inputObj = inputObj
            }
        end
        
        ::continue::
    end
    
    return self.expressionChangesSinceLastUpdate
end

-- Update the stored parameter state after propagation
function ParameterManager:updateStoredState(changes, expressionChanges, connectionChanges, outputConnectionChanges)
    if DEBUG_MODE then print("[DEBUG] Updating stored state after propagation") end
    -- Update parameter changes to reflect CURRENT SOURCE STATE (not applied state)
    for name, changeData in pairs(changes) do
        -- Ensure parameterInfo entry exists before updating
        if self.parameterInfo[name] then
            local input = self.parameterInfo[name].inputObj
            local currentTime = self.comp.CurrentTime
            
            -- Get the CURRENT SOURCE STATE to store as baseline for next comparison
            local currentKeyframes = nil
            pcall(function() 
                local keys = input:GetKeyFrames()
                if keys then currentKeyframes = keys end
            end)
            
            -- Filter out invalid keyframes 
            local realKeyframes = {}
            if currentKeyframes and #currentKeyframes > 0 then
                for _, time in ipairs(currentKeyframes) do
                    if math.abs(time) < 999999999 then
                        table.insert(realKeyframes, time)
                    end
                end
            end
            
            local isCurrentlyAnimated = (#realKeyframes > 0)
            
            if isCurrentlyAnimated then
                -- Store the current source keyframes with values for exact comparison
                local sourceKeyframesWithValues = {}
                for _, time in ipairs(realKeyframes) do
                    local value = nil
                    pcall(function() value = input[time] end)
                    table.insert(sourceKeyframesWithValues, {time = time, value = value})
                end
                
                self.parameterInfo[name].isAnimated = true
                self.parameterInfo[name].lastKeyframes = sourceKeyframesWithValues
                self.parameterInfo[name].last = nil
                if DEBUG_MODE then print("[DEBUG] Updated baseline for " .. name .. " with " .. #sourceKeyframesWithValues .. " keyframes") end
            else
                -- Store current static value from source
                local currentValue = extractActualValue(input, currentTime)
                self.parameterInfo[name].isAnimated = false
                self.parameterInfo[name].last = currentValue
                self.parameterInfo[name].lastKeyframes = nil
                if DEBUG_MODE then print("[DEBUG] Updated baseline for " .. name .. " with static value: " .. tostring(currentValue)) end
            end
        else
            if DEBUG_MODE then print("[DEBUG] WARNING: parameterInfo entry not found for " .. name) end
        end
    end
    
    -- Update expression changes
    if expressionChanges then
        for name, changeData in pairs(expressionChanges) do
            -- Update or create expression info based on whether expression exists
            if changeData.expression then
                -- Has expression - add or update in expressionInfo
                self.expressionInfo[name] = {
                    expression = changeData.expression,
                    inputObj = changeData.inputObj
                }
            else
                -- Expression was removed - remove from expressionInfo
                self.expressionInfo[name] = nil
            end
        end
    end
    
    -- Update connection changes
    if connectionChanges then
        for name, changeData in pairs(connectionChanges) do
            -- Update parameterInfo connection state
            if self.parameterInfo[name] then
                self.parameterInfo[name].isConnected = changeData.isConnected
            end
            
            -- Update or create connection info based on whether connection exists
            if changeData.isConnected and changeData.sourceTool then
                -- Has connection - add or update in connectionInfo
                self.connectionInfo[name] = {
                    isConnected = true,
                    sourceTool = changeData.sourceTool,
                    sourceOutput = changeData.sourceOutput,
                    inputObj = changeData.inputObj
                }
            else
                -- Connection was removed - remove from connectionInfo
                self.connectionInfo[name] = nil
            end
        end
    end
    
    -- Update output connection changes
    if outputConnectionChanges then
        for outputName, changeData in pairs(outputConnectionChanges) do
            -- Update output connection info
            if #changeData.connectedInputs > 0 then
                self.outputConnectionInfo[outputName] = {
                    outputObj = changeData.outputObj,
                    connectedInputs = changeData.connectedInputs
                }
            else
                -- No connections - remove from outputConnectionInfo
                self.outputConnectionInfo[outputName] = nil
            end
        end
    end
end

------------------------
-- Propagation Module
------------------------
local PropagationManager = {}

function PropagationManager:init(activeTool, targetTools, comp)
    self.activeTool = activeTool
    self.targetTools = targetTools
    self.comp = comp
    return self
end

-- Define function to propagate changes
function PropagationManager:propagateChanges(isLive, changes, expressionChanges, connectionChanges, outputConnectionChanges)
    isLive = isLive or false -- Default to not live

    -- Count changes and expression changes
    local changeCount = 0
    for _ in pairs(changes) do changeCount = changeCount + 1 end
    
    local exprChangeCount = 0
    if expressionChanges then
        for _ in pairs(expressionChanges) do exprChangeCount = exprChangeCount + 1 end
    end
    
    local connChangeCount = 0
    if connectionChanges then
        for _ in pairs(connectionChanges) do connChangeCount = connChangeCount + 1 end
    end
    
    local outputConnChangeCount = 0
    if outputConnectionChanges then
        for _ in pairs(outputConnectionChanges) do outputConnChangeCount = outputConnChangeCount + 1 end
    end
    
    local totalChangeCount = changeCount + exprChangeCount + connChangeCount + outputConnChangeCount
    
    if totalChangeCount == 0 then
        if not isLive then
            print("[Propagate] No changes detected to propagate")
        end
        return false, 0
    end
    
    -- Show progress
    if not isLive then
        print("[Propagate] Propagating " .. totalChangeCount .. " changes to " .. #self.targetTools .. " tools")
    end
    
    -- Start undo block only if NOT in live mode
    local undoStarted = false
    if not isLive then
        self.comp:StartUndo("Propagate Parameters")
        undoStarted = true
    end
    
    -- Track successful parameter changes
    local totalSuccess = 0
    
    -- Apply to each target tool
    for _, tool in ipairs(self.targetTools) do
        local toolName = tool:GetAttrs().TOOLS_Name
        local toolID = tool:GetAttrs().TOOLS_RegID
        if DEBUG_MODE and not isLive then print("[Propagate] Processing: " .. toolName) end
        
        -- Apply connection changes FIRST (especially disconnections)
        -- This ensures disconnections happen before setting parameter values
        if connectionChanges and INCLUDE_CONNECTIONS then
            for name, changeData in pairs(connectionChanges) do
                totalSuccess = totalSuccess + self:applyConnectionToTool(tool, name, changeData, isLive)
            end
        end
        
        -- Apply each changed parameter AFTER connections
        for name, changeData in pairs(changes) do
            -- Create independent copy of changeData for each tool to avoid shared references
            local independentChangeData = {}
            for key, value in pairs(changeData) do
                if key == "value" and type(value) == "table" and changeData.isAnimated then
                    -- Create independent keyframe array for each tool
                    independentChangeData[key] = {}
                    for i, kf in ipairs(value) do
                        -- Handle both old format (just times) and new format ({time=x, value=y})
                        if type(kf) == "table" and kf.time then
                            -- New format: deep copy the keyframe object
                            independentChangeData[key][i] = {time = kf.time, value = kf.value}
                        else
                            -- Old format: just copy the time value
                            independentChangeData[key][i] = kf
                        end
                    end
                else
                    independentChangeData[key] = value
                end
            end
            
            totalSuccess = totalSuccess + self:applyParameterToTool(tool, name, independentChangeData, isLive)
        end
        
        -- Apply expression changes
        if expressionChanges and INCLUDE_EXPRESSIONS then
            for name, changeData in pairs(expressionChanges) do
                totalSuccess = totalSuccess + self:applyExpressionToTool(tool, name, changeData, isLive)
            end
        end
        
        -- Apply output connection changes
        if outputConnectionChanges and INCLUDE_OUTPUT_CONNECTIONS then
            for outputName, changeData in pairs(outputConnectionChanges) do
                totalSuccess = totalSuccess + self:applyOutputConnectionToTool(tool, outputName, changeData, isLive)
            end
        end
    end
    
    -- End undo block only if it was started
    if undoStarted then
        self.comp:EndUndo()
    end
    
    -- Update status
    if not isLive then
        -- Simple success summary
    if totalSuccess > 0 then
        print("✓ Applied " .. totalSuccess .. " changes to " .. #self.targetTools .. " tools")
    else
        print("No changes applied")
    end
    end
    
    return totalSuccess > 0, totalSuccess -- Return success state and count
end

-- Apply a single parameter change to a tool
function PropagationManager:applyParameterToTool(tool, name, changeData, isLive)
    local toolName = tool:GetAttrs().TOOLS_Name
    local toolID = tool:GetAttrs().TOOLS_RegID
    local inputType = changeData.type or ""
    
    if DEBUG_MODE then
        print("[DEBUG] Applying parameter " .. name .. " to " .. toolName .. " (animated: " .. tostring(changeData.isAnimated) .. ", type: " .. tostring(changeData.type) .. ")")
    end
    
            -- Try to get this input on the target tool
            local success, input = pcall(function() return tool[name] end)
            
    if not success or not input then
        if not isLive then print("[Propagate] ERROR: Input " .. name .. " not found on " .. toolName) end
        if DEBUG_MODE then print("[DEBUG] Input not found for " .. name .. " on " .. toolName) end
        return 0
    end
    
    -- Get input attributes
    local attrs = {}
    pcall(function() attrs = input:GetAttrs() or {} end)
    local isConnected = attrs.INPB_Connected or false
    
    -- Check if this is a real tool connection vs just animated/keyframed
    local hasRealConnection = false
    if isConnected then
        if DEBUG_MODE then print("[DEBUG] Parameter " .. name .. " on " .. toolName .. " reports as connected, investigating...") end
        
        -- Try to get the connected output to see if it's a real tool connection
        local connectedOutput = nil
        local outputSuccess = pcall(function() connectedOutput = input:GetConnectedOutput() end)
        
        if DEBUG_MODE then 
            print("[DEBUG] GetConnectedOutput success: " .. tostring(outputSuccess) .. ", output: " .. tostring(connectedOutput))
        end
        
        if connectedOutput then
            local sourceTool = nil
            local toolSuccess = pcall(function() sourceTool = connectedOutput:GetTool() end)
            
            if sourceTool then
                local sourceToolName = "unknown"
                local sourceToolID = "unknown"
                pcall(function() 
                    local attrs = sourceTool:GetAttrs()
                    sourceToolName = attrs.TOOLS_Name or "unknown"
                    sourceToolID = attrs.TOOLS_RegID or "unknown"
                end)
                
                if DEBUG_MODE then 
                    print("[DEBUG] GetTool success: " .. tostring(toolSuccess) .. ", tool: " .. tostring(sourceTool))
                    print("[DEBUG] Source tool name: " .. sourceToolName)
                    print("[DEBUG] Source tool ID: " .. sourceToolID)
                end
                
                -- Treat internal animation modifiers (BezierSpline/Path) as non-real connections
                local isInternal = isInternalAnimationConnection(sourceTool, toolName, name, inputType)
                
                -- Only consider it a real connection if it's not an internal animation modifier
                -- OR if keyframe overwriting is disabled
                hasRealConnection = not isInternal or not ALLOW_KEYFRAME_OVERWRITE
                
                if DEBUG_MODE then
                    print("[DEBUG] Allow keyframe overwrite: " .. tostring(ALLOW_KEYFRAME_OVERWRITE))
                end
            else
                hasRealConnection = false
                if DEBUG_MODE then 
                    print("[DEBUG] GetTool success: " .. tostring(toolSuccess) .. ", tool: " .. tostring(sourceTool))
                end
            end
        end
        
        if DEBUG_MODE then print("[DEBUG] Final hasRealConnection result: " .. tostring(hasRealConnection)) end
    end
    
    -- Skip if it's a real connection to another tool
    if hasRealConnection then
        if not isLive then print("[Propagate] SKIP: " .. toolName .. "." .. name .. " (connected to tool)") end
        if DEBUG_MODE then print("[DEBUG] Skipping parameter connected to another tool: " .. name .. " on " .. toolName) end
        return 0
    end
    
    -- For animated parameters (keyframes/expressions), check if we should allow overwriting
    if isConnected and not ALLOW_KEYFRAME_OVERWRITE then
        if not isLive then print("[Propagate] SKIP: " .. toolName .. "." .. name .. " (animated)") end
        if DEBUG_MODE then print("[DEBUG] Skipping animated parameter " .. name .. " on " .. toolName .. " (overwrite disabled)") end
        return 0
    end

    -- If this is an internal animation connection (Path/BezierSpline), disconnect before applying keyframes
    if isConnected and changeData.isAnimated then
        local connectedOutput = nil
        pcall(function() connectedOutput = input:GetConnectedOutput() end)
        if connectedOutput then
            local sourceTool = nil
            pcall(function() sourceTool = connectedOutput:GetTool() end)
            if sourceTool then
                local isInternal = isInternalAnimationConnection(sourceTool, toolName, name, inputType)
                if isInternal then
                    pcall(function() input:ConnectTo(nil) end)
                    if DEBUG_MODE then print("[DEBUG] Disconnected internal animation from " .. toolName .. "." .. name) end
                end
            end
        end
    end
    
    -- If we're propagating keyframes to an already animated parameter, log it
    if isConnected and changeData.isAnimated and ALLOW_KEYFRAME_OVERWRITE then
        if not isLive then print("[Propagate] OVERWRITE: " .. toolName .. "." .. name .. " (replacing existing keyframes)") end
        if DEBUG_MODE then print("[DEBUG] Overwriting existing keyframes on " .. name .. " at " .. toolName) end
    end
    
                local setSuccess = false
                local value = changeData.value
                local extractedValue = changeData.extracted
    local isAnimated = changeData.isAnimated
    
    if DEBUG_MODE then
        print("[DEBUG] Parameter values - value: " .. tostring(value) .. ", extracted: " .. tostring(extractedValue) .. ", type: " .. tostring(inputType))
    end
    
    -- For animated Point inputs, prefer cloning internal Path modifiers (keeps keyframes visible)
    if isAnimated and inputType == "Point" then
        local cloned = self:cloneInternalPointAnimation(tool, name, changeData)
        if cloned then
            if DEBUG_MODE then print("[DEBUG] Cloned internal Path for " .. toolName .. "." .. name) end
            return 1
        end
    end

    -- Handle different parameter types
    if isAnimated then
        if DEBUG_MODE then print("[DEBUG] Applying as animated parameter") end
        setSuccess = self:applyAnimatedParameter(tool, name, changeData, isLive)
    else
        if DEBUG_MODE then print("[DEBUG] Applying as static parameter") end
        
        -- If set to static value and target has animation, remove the animation first
        -- isConnected here means the target parameter is animated (connected to BezierSpline)
        if isConnected then
            if DEBUG_MODE then print("[DEBUG] Target parameter has animation, attempting to remove...") end
            pcall(function()
                -- Get the input object
                local targetInput = tool[name]
                if targetInput then
                    -- Disconnect from BezierSpline to remove animation
                    -- This is the proper way to remove animation in Fusion
                    targetInput:ConnectTo(nil)
                    if DEBUG_MODE then print("[DEBUG] Disconnected animation from " .. toolName .. "." .. name) end
                end
            end)
        end
        -- Handle different static parameter types
        if inputType == "Clip" and (toolID == "Loader" or toolID == "Saver") then
            if DEBUG_MODE then print("[DEBUG] Using Clip parameter handler") end
            setSuccess = self:applyClipParameter(tool, toolID, name, value, isLive)
        elseif inputType == "FuID" or inputType == "Enumeration" or inputType == "ComboControl" then
            if DEBUG_MODE then print("[DEBUG] Using Enum parameter handler") end
            setSuccess = self:applyEnumParameter(tool, name, value, extractedValue, isLive)
        elseif inputType == "Point" then
            if DEBUG_MODE then print("[DEBUG] Using Point parameter handler") end
            setSuccess = self:applyPointParameter(tool, name, value, isLive, changeData.pointAxes)
        elseif inputType == "Color" or inputType == "ColorRGBA" then
            if DEBUG_MODE then print("[DEBUG] Using Color parameter handler") end
            setSuccess = self:applyColorParameter(tool, name, input, value, isLive)
        else
            if DEBUG_MODE then print("[DEBUG] Using Generic parameter handler") end
            setSuccess = self:applyGenericParameter(tool, name, value, isLive)
        end
    end
    
    if DEBUG_MODE then print("[DEBUG] Parameter application result: " .. tostring(setSuccess)) end
    
    if setSuccess then
                    if DEBUG_MODE and not isLive then print("[Propagate] OK: " .. toolName .. "." .. name) end
        return 1
    else
        if DEBUG_MODE and not isLive then print("[Propagate] FAILED: " .. toolName .. "." .. name) end
        return 0
    end
end

-- Clone internal Path modifier from source tool to target Point input
function PropagationManager:cloneInternalPointAnimation(tool, name, changeData)
    changeData = changeData or {}
    local sourceInput = nil
    pcall(function() sourceInput = self.activeTool[name] end)
    if not sourceInput then return false end

    -- Snapshot target point at source key times (before we replace with cloned Path)
    local targetInputForSnap = nil
    pcall(function() targetInputForSnap = tool[name] end)
    local axesByTime = {}
    if changeData.value and type(changeData.value) == "table" then
        for _, kf in ipairs(changeData.value) do
            if type(kf) == "table" and type(kf.time) == "number" then
                axesByTime[kf.time] = kf.axes
            end
        end
    end
    local targetSnapshot = {}
    local pointKeysForSnap = nil
    pcall(function() pointKeysForSnap = sourceInput:GetKeyFrames() end)
    if pointKeysForSnap and targetInputForSnap then
        for _, tm in ipairs(pointKeysForSnap) do
            if math.abs(tm) < 999999999 then
                pcall(function() targetSnapshot[tm] = targetInputForSnap[tm] end)
            end
        end
    end

    local sourceOutput = nil
    pcall(function() sourceOutput = sourceInput:GetConnectedOutput() end)
    if not sourceOutput then return false end

    local sourceTool = nil
    pcall(function() sourceTool = sourceOutput:GetTool() end)
    if not sourceTool then return false end

    local activeToolName = ""
    pcall(function() activeToolName = self.activeTool:GetAttrs().TOOLS_Name or "" end)
    if not isInternalAnimationConnection(sourceTool, activeToolName, name, "Point") then
        return false
    end

    local newPath = nil
    pcall(function() newPath = self.comp:Path({}) end)
    if not newPath then return false end

    -- Copy settings from source Path to new Path
    local settings = nil
    pcall(function() settings = self.comp:CopySettings(sourceTool) end)
    if settings then
        -- Remap tool name in settings to the new Path name
        local sourceName = ""
        local newName = ""
        pcall(function() sourceName = sourceTool:GetAttrs().TOOLS_Name or "" end)
        pcall(function() newName = newPath:GetAttrs().TOOLS_Name or "" end)
        if settings.Tools and sourceName ~= "" and newName ~= "" and settings.Tools[sourceName] and not settings.Tools[newName] then
            settings.Tools[newName] = settings.Tools[sourceName]
            settings.Tools[sourceName] = nil
        end

        local pasted = false
        pcall(function()
            if newPath.LoadSettings then
                newPath:LoadSettings(settings)
                pasted = true
            end
        end)
        if not pasted then
            pcall(function()
                if self.comp.PasteSettings then
                    self.comp:PasteSettings(newPath, settings)
                    pasted = true
                end
            end)
        end
        if not pasted then
            pcall(function()
                if newPath.PasteSettings then
                    newPath:PasteSettings(settings)
                    pasted = true
                end
            end)
        end
        if DEBUG_MODE and not pasted then
            print("[DEBUG] Failed to paste Path settings for " .. name)
        end
    end

    -- Copy keyframes/values from source Path inputs, or fall back to point value keys
    local sourceInputs = {}
    pcall(function() sourceInputs = sourceTool:GetInputList() or {} end)
    local copiedAny = false
    for _, srcInput in pairs(sourceInputs) do
        local inputName = nil
        pcall(function() inputName = srcInput:GetAttrs().INPS_ID end)
        if inputName then
            local targetInput = nil
            pcall(function() targetInput = newPath[inputName] end)
            if targetInput then
                local keys = nil
                pcall(function() keys = srcInput:GetKeyFrames() end)
                if keys and #keys > 0 then
                    for _, time in ipairs(keys) do
                        if math.abs(time) < 999999999 then
                            local val = nil
                            pcall(function() val = srcInput[time] end)
                            if val ~= nil then
                                pcall(function() newPath[inputName][time] = val end)
                                copiedAny = true
                            end
                        end
                    end
                else
                    local currentVal = nil
                    pcall(function() currentVal = srcInput[self.comp.CurrentTime] end)
                    if currentVal ~= nil then
                        pcall(function() newPath[inputName] = currentVal end)
                    end
                end
            end
        end
    end

    if not copiedAny then
        -- Use source point keyframes directly if Path inputs didn't expose them
        local pointKeys = nil
        pcall(function() pointKeys = sourceInput:GetKeyFrames() end)
        if pointKeys and #pointKeys > 0 then
            for _, time in ipairs(pointKeys) do
                if math.abs(time) < 999999999 then
                    local val = nil
                    pcall(function() val = sourceInput[time] end)
                    if val ~= nil then
                        pcall(function() newPath[time] = val end)
                    end
                end
            end
        end
    end

    -- Connect target input to the cloned Path
    local targetInput = nil
    pcall(function() targetInput = tool[name] end)
    if not targetInput then return false end

    local connected = false
    pcall(function()
        if newPath.Output then
            targetInput:ConnectTo(newPath.Output)
        else
            targetInput:ConnectTo(newPath)
        end
        connected = true
    end)
    if not connected then
        pcall(function() tool[name] = newPath end)
        connected = true
    end

    -- Also write point values directly to the parameter at keyframe times
    local pointKeys = nil
    pcall(function() pointKeys = sourceInput:GetKeyFrames() end)
    if pointKeys and #pointKeys > 0 then
        for _, time in ipairs(pointKeys) do
            if math.abs(time) < 999999999 then
                local val = nil
                pcall(function() val = sourceInput[time] end)
                local normalized = normalizePointToTable(val)
                local axes = axesByTime[time]
                if normalized and axes and targetSnapshot[time] ~= nil then
                    normalized = mergePointValues(targetSnapshot[time], normalized, axes)
                end
                if normalized then
                    pcall(function() tool:SetInput(name, normalized, time) end)
                end
            end
        end
    end

    return connected
end

-- Apply an expression change to a tool
function PropagationManager:applyExpressionToTool(tool, name, changeData, isLive)
    local toolName = tool:GetAttrs().TOOLS_Name
    
    -- Try to get the input on the target tool
    local success, input = pcall(function() return tool[name] end)
    
    if not success or not input then
        if not isLive then print("[Propagate] ERROR: Input " .. name .. " not found on " .. toolName) end
        return 0
    end
    
    -- Get input attributes to check if connected
                local attrs = {}
                pcall(function() attrs = input:GetAttrs() or {} end)
                local isConnected = attrs.INPB_Connected or false
    
    -- Check if this is a real tool connection vs just animated/keyframed
    local hasRealConnection = false
    if isConnected then
        -- Try to get the connected output to see if it's a real tool connection
        local connectedOutput = nil
        pcall(function() connectedOutput = input:GetConnectedOutput() end)
        
        if connectedOutput then
            local sourceTool = nil
            pcall(function() sourceTool = connectedOutput:GetTool() end)
            
            if sourceTool then
                local sourceToolName = "unknown"
                local sourceToolID = "unknown"
                pcall(function() 
                    local attrs = sourceTool:GetAttrs()
                    sourceToolName = attrs.TOOLS_Name or "unknown"
                    sourceToolID = attrs.TOOLS_RegID or "unknown"
                end)
                
                -- Check if this is an internal animation spline (BezierSpline with name pattern ToolName+ParameterName)
                local isInternalAnimationSpline = false
                if sourceToolID == "BezierSpline" then
                    -- Internal animation splines typically have names like "Transform1_1Size1" for the Size parameter of Transform1_1
                    -- Pattern: ToolName + ParameterName + optional numerical suffix
                    local expectedBaseName = toolName .. name
                    
                    -- Check if source tool name starts with expected base name
                    local startsWithExpected = sourceToolName:sub(1, #expectedBaseName) == expectedBaseName
                    
                    -- If it starts with expected name, check if the remainder is just a numerical suffix or empty
                    if startsWithExpected then
                        local remainder = sourceToolName:sub(#expectedBaseName + 1)
                        -- Empty remainder (exact match) or numerical suffix (like "1", "2", etc.)
                        isInternalAnimationSpline = (remainder == "" or remainder:match("^%d+$"))
                    end
                    
                    if DEBUG_MODE then
                        print("[DEBUG] [Expression] BezierSpline detected - Expected base: " .. expectedBaseName .. ", Actual: " .. sourceToolName)
                        print("[DEBUG] [Expression] Starts with expected: " .. tostring(startsWithExpected))
                        if startsWithExpected then
                            local remainder = sourceToolName:sub(#expectedBaseName + 1)
                            print("[DEBUG] [Expression] Remainder: '" .. remainder .. "'")
                            print("[DEBUG] [Expression] Is numerical suffix: " .. tostring(remainder == "" or remainder:match("^%d+$")))
                        end
                        print("[DEBUG] [Expression] Is internal animation spline: " .. tostring(isInternalAnimationSpline))
                    end
                end
                
                -- Only consider it a real connection if it's not an internal animation spline
                -- OR if keyframe overwriting is disabled
                hasRealConnection = not isInternalAnimationSpline or not ALLOW_KEYFRAME_OVERWRITE
            else
                hasRealConnection = false
            end
        end
    end
    
    -- Skip if it's a real connection to another tool
    if hasRealConnection then
        if not isLive then print("[Propagate] SKIP: " .. toolName .. "." .. name .. " (connected to tool)") end
        return 0
    end
    
    -- Apply the expression
    local expression = changeData.expression
    local setSuccess = false
    
    pcall(function()
        -- If expression is nil, it removes the expression
        input:SetExpression(expression)
        setSuccess = true
    end)
    
    if setSuccess then
        if not isLive then
            if expression then
                print("[Propagate] OK: Set expression on " .. toolName .. "." .. name)
            else
                print("[Propagate] OK: Removed expression from " .. toolName .. "." .. name)
            end
        end
        return 1
    else
        if not isLive then print("[Propagate] FAILED: Expression on " .. toolName .. "." .. name) end
        return 0
    end
end

-- Apply a connection change to a tool
function PropagationManager:applyConnectionToTool(tool, name, changeData, isLive)
    local toolName = tool:GetAttrs().TOOLS_Name
    
    -- Try to get the input on the target tool
    local success, input = pcall(function() return tool[name] end)
    
    if not success or not input then
        if not isLive then print("[Propagate] ERROR: Input " .. name .. " not found on " .. toolName) end
        return 0
    end
    
    local setSuccess = false
    
    if changeData.isConnected and changeData.sourceOutput then
        -- Connect to the same source
        pcall(function()
            input:ConnectTo(changeData.sourceOutput)
            setSuccess = true
        end)
        
        if setSuccess then
            if not isLive then 
                local sourceName = changeData.sourceTool:GetAttrs().TOOLS_Name
                print("[Propagate] OK: Connected " .. toolName .. "." .. name .. " to " .. sourceName)
            end
            return 1
        else
            if not isLive then print("[Propagate] FAILED: Connection on " .. toolName .. "." .. name) end
            return 0
        end
    else
        -- Disconnect
        pcall(function()
            input:ConnectTo(nil)
            setSuccess = true
        end)
        
        if setSuccess then
            if not isLive then print("[Propagate] OK: Disconnected " .. toolName .. "." .. name) end
            return 1
        else
            if not isLive then print("[Propagate] FAILED: Disconnection on " .. toolName .. "." .. name) end
            return 0
        end
    end
end

-- Apply animated parameter
function PropagationManager:applyAnimatedParameter(tool, name, changeData, isLive)
    local value = changeData and changeData.value
    if type(value) ~= "table" or #value == 0 then
        if not isLive then print("[Propagate] WARNING: Invalid keyframe data") end
        return false
    end
    
    if not isLive then print("[Propagate] Applying " .. #value .. " keyframes to " .. tool:GetAttrs().TOOLS_Name .. "." .. name) end

    -- Point + partial axes: snapshot target values before replacing with BezierSpline
    local targetSnapshot = {}
    if changeData.type == "Point" then
        local oldInput = nil
        pcall(function() oldInput = tool[name] end)
        if oldInput then
            for _, kf in ipairs(value) do
                if type(kf) == "table" and kf.axes and type(kf.time) == "number" then
                    local v = nil
                    pcall(function() v = oldInput[kf.time] end)
                    targetSnapshot[kf.time] = v
                end
            end
        end
    end
    
    -- Create the spline
    local spline = self.comp:BezierSpline({})
    
    -- Assign the spline to the parameter
    tool[name] = spline
                            
    -- Track if we successfully applied any keyframes
    local keyframesApplied = false
                            
    -- Apply each keyframe - keyframes now contain {time=x, value=y} objects
    for _, kf in ipairs(value) do  
        -- Handle both old format (just times) and new format ({time=x, value=y})
        local time = type(kf) == "table" and kf.time or kf
        local val = type(kf) == "table" and kf.value or nil
        
        -- If we don't have the value stored, get it from the source parameter
        if val == nil then
            local sourceParam = nil
            pcall(function() sourceParam = self.activeTool[name] end)
            if sourceParam then
                pcall(function() val = sourceParam[time] end)
            end
        end

        if changeData.type == "Point" and type(kf) == "table" and kf.axes then
            local snap = targetSnapshot[time]
            if snap ~= nil and val ~= nil then
                val = mergePointValues(snap, val, kf.axes)
            end
        end
            
        if type(time) == "number" and val ~= nil then
            -- Set the keyframe and track success
            local success = pcall(function() tool[name][time] = val end)
            if success then keyframesApplied = true end
        end
    end
                            
    -- Only mark as success if we actually applied at least one keyframe
    return keyframesApplied
end

-- Apply clip parameter
function PropagationManager:applyClipParameter(tool, toolID, name, value, isLive)
    local success = false
                                
    pcall(function()
        local currentTime = self.comp.CurrentTime
                                
        -- For Loaders, preserve timing values during clip change
        if toolID == "Loader" then
            -- Store timing values
            local globalIn = tool.GlobalIn[currentTime]
            local globalOut = tool.GlobalOut[currentTime]
            local trimIn = tool.ClipTimeStart[currentTime]
            local trimOut = tool.ClipTimeEnd[currentTime]
            local holdFirst = tool.HoldFirstFrame[currentTime]
            local holdLast = tool.HoldLastFrame[currentTime]
            local toolDepth = nil
            pcall(function() toolDepth = tool.Depth[currentTime] end)
            
            -- Update clip path
            if type(value) == "string" then
                -- Always apply the path, even if nothing is on disk yet. Lua cannot
                -- reliably tell: PathMaps ($SHOW, Comp:) are opaque to io.open, and the
                -- clip string names one specific frame that need not be the first one.
                -- A missing file is the artist's problem to see in the Loader, not a
                -- reason to silently skip the propagation.
                tool[name][currentTime] = value

                -- Restore timing values
                tool.GlobalOut[currentTime] = globalOut
                tool.GlobalIn[currentTime] = globalIn
                tool.ClipTimeStart[currentTime] = trimIn
                tool.ClipTimeEnd[currentTime] = trimOut
                tool.HoldFirstFrame[currentTime] = holdFirst
                tool.HoldLastFrame[currentTime] = holdLast

                if toolDepth then
                    tool.Depth[currentTime] = toolDepth
                end

                success = true
            else
                tool[name] = value
                success = true
            end
        else
            -- For non-Loader tools, set clip directly
            tool[name] = value
            success = true
        end
    end)
    
    return success
end

-- Apply enumeration parameter
function PropagationManager:applyEnumParameter(tool, name, value, extractedValue, isLive)
                                local success = false
                                
    pcall(function()
                                -- Try setting the full value
                                pcall(function()
                                    tool[name] = value
                                    success = true
                                end)
                                
                                -- Try setting the extracted value
                                if not success and extractedValue ~= nil then
                                    pcall(function()
                                        tool[name] = extractedValue
                                        success = true
                                    end)
                                end
                                
                                -- Try setting at current time
                                if not success then
                                    pcall(function()
                tool[name][self.comp.CurrentTime] = value
                                        success = true
                                    end)
                                end
    end)
    
    return success
end

-- Apply point parameter (pointAxes: which axes changed on source; nil = replace whole point)
function PropagationManager:applyPointParameter(tool, name, value, isLive, pointAxes)
    local success = false
    local comp = self.comp

    pcall(function()
        -- Single-axis: merge source into target's current value at comp time
        if pointAxes and type(value) == "table" then
            local tgt = nil
            pcall(function() tgt = tool[name][comp.CurrentTime] end)
            if tgt ~= nil then
                local merged = mergePointValues(tgt, value, pointAxes)
                if merged ~= nil then
                    tool[name] = merged
                    success = true
                    return
                end
            end
        end

        if type(value) == "table" then
            -- Try array style [1,2,3]
            if value[1] ~= nil then
                tool[name] = { value[1], value[2], value[3] or 0 }
                success = true
            -- Try named properties {X=0, Y=0, Z=0}
            elseif value.X ~= nil then
                local newPoint = { value.X, value.Y, value.Z or 0 }
                tool[name] = newPoint
                success = true
            else
                tool[name] = value
                success = true
            end

            -- Try component-wise as fallback
            if not success then
                if value[1] ~= nil then
                    tool[name][1] = value[1]
                    tool[name][2] = value[2]
                    if value[3] ~= nil then tool[name][3] = value[3] end
                    success = true
                elseif value.X ~= nil then
                    tool[name].X = value.X
                    tool[name].Y = value.Y
                    if value.Z ~= nil then tool[name].Z = value.Z end
                    success = true
                end
            end
        else
            tool[name] = value
            success = true
        end
    end)

    return success
end

-- Apply color parameter
function PropagationManager:applyColorParameter(tool, name, input, value, isLive)
    local success = false
    
                            pcall(function()
                                if type(value) == "table" then
                                    input.R = value.R or value[1]
                                    input.G = value.G or value[2]
                                    input.B = value.B or value[3]
                                    if value.A ~= nil or value[4] ~= nil then
                                        input.A = value.A or value[4] or 1
                                    end
                                else
                                    tool[name] = value
                                end
        success = true
    end)
    
    return success
end

-- Apply generic parameter
function PropagationManager:applyGenericParameter(tool, name, value, isLive)
    local success = false
    
    if DEBUG_MODE then
        print("[DEBUG] applyGenericParameter - name: " .. name .. ", value: " .. tostring(value) .. ", type: " .. type(value))
    end
    
    -- Try direct assignment
                            pcall(function()
                                tool[name] = value
        success = true
                            end)
    
    if DEBUG_MODE then print("[DEBUG] Direct assignment result: " .. tostring(success)) end
                            
                            -- Try at current time if direct assignment failed
    if not success then
                                pcall(function()
            tool[name][self.comp.CurrentTime] = value
            success = true
                                end)
        if DEBUG_MODE then print("[DEBUG] Current time assignment result: " .. tostring(success)) end
                        end
                        
    -- Try disconnecting and setting
    if not success then
                            pcall(function()
            local input = tool[name]
                                if type(input.SetSource) == "function" then
                                    input:SetSource(nil) -- Disconnect if connected
                tool[name] = value   -- Try again after disconnecting
                success = true
                                end
                            end)
        if DEBUG_MODE then print("[DEBUG] Disconnect and set result: " .. tostring(success)) end
                        end
    
    if DEBUG_MODE then print("[DEBUG] applyGenericParameter final result: " .. tostring(success)) end
                        
    return success
end

-- Apply an output connection change to a tool
function PropagationManager:applyOutputConnectionToTool(tool, outputName, changeData, isLive)
    local toolName = tool:GetAttrs().TOOLS_Name
    
    -- Skip the active tool - it already has the connection we want to propagate
    if tool == self.activeTool then
        if not isLive then 
            print("[Propagate] SKIP: " .. toolName .. " is the active tool (already connected)")
        end
        return 0
    end
    
    -- Get the output on the target tool
    local targetOutput = tool.Output
    if not targetOutput then
        if not isLive then print("[Propagate] ERROR: Output not found on " .. toolName) end
        return 0
    end
    
    -- Get the index of this tool in the target tools list
    local toolIndex = nil
    for i, targetTool in ipairs(self.targetTools) do
        if targetTool == tool then
            toolIndex = i
            break
        end
    end
    
    if not toolIndex then
        if not isLive then print("[Propagate] ERROR: Tool not found in target list") end
        return 0
    end
    
    local totalSuccess = 0
    
    -- Apply each connection from the change data
    for _, connInfo in ipairs(changeData.connectedInputs) do
        local targetTool = connInfo.targetTool
        local originalInputName = connInfo.inputName
        
        -- Find all connection-type inputs on the target tool
        local connectionInputs = {}
        local inputList = targetTool:GetInputList() or {}
        
        for _, input in pairs(inputList) do
            local inputName = input:GetAttrs().INPS_ID
            local inputAttrs = input:GetAttrs() or {}
            local dataType = inputAttrs.INPS_DataType or ""
            
            -- Only include inputs that accept tool connections
            if dataType == "Image" or dataType == "Scene" or dataType == "Mesh" or 
               dataType == "Particles" or dataType == "DataType3D" or dataType == "MtlGraph3D" then
                table.insert(connectionInputs, {
                    name = inputName,
                    input = input,
                    isConnected = inputAttrs.INPB_Connected or false
                })
            end
        end
        
        -- Sort by name for consistent ordering
        table.sort(connectionInputs, function(a, b) return a.name < b.name end)
        
        -- Find the right input for this tool
        local targetInput = nil
        local finalInputName = originalInputName
        
        if #connectionInputs > 0 then
            -- Find the index of the original input to use as starting point
            local originalInputIndex = 1
            for i, inputInfo in ipairs(connectionInputs) do
                if inputInfo.name == originalInputName then
                    originalInputIndex = i
                    break
                end
            end
            
            -- Calculate which input this tool should use, starting from the next available input after the original
            local inputIndex = ((originalInputIndex + toolIndex - 1) % #connectionInputs) + 1
            local selectedInput = connectionInputs[inputIndex]
            
            targetInput = selectedInput.input
            finalInputName = selectedInput.name
            
            if selectedInput.isConnected and not isLive then
                print("[Propagate] WARNING: Replacing connection on " .. targetTool:GetAttrs().TOOLS_Name .. "." .. finalInputName)
            end
        else
            -- Fallback to original input name
            pcall(function() targetInput = targetTool[originalInputName] end)
        end
        
        if targetInput then
            local success = false
            pcall(function()
                targetInput:ConnectTo(targetOutput)
                success = true
            end)
            
            if success then
                if not isLive then 
                    print("[Propagate] OK: Connected " .. toolName .. "." .. outputName .. 
                          " to " .. targetTool:GetAttrs().TOOLS_Name .. "." .. finalInputName)
                end
                totalSuccess = totalSuccess + 1
            else
                if not isLive then 
                    print("[Propagate] FAILED: Connection from " .. toolName .. "." .. outputName .. 
                          " to " .. targetTool:GetAttrs().TOOLS_Name .. "." .. finalInputName)
                end
            end
        else
            if not isLive then 
                print("[Propagate] ERROR: No suitable input found on " .. targetTool:GetAttrs().TOOLS_Name)
            end
        end
    end
    
    return totalSuccess
end

------------------------
-- UI Module
------------------------
local UI = {}

function UI:init(comp, activeTool, targetTools, mousex, mousey)
    self.comp = comp
    self.activeTool = activeTool
    self.activeToolName = activeTool:GetAttrs().TOOLS_Name
    self.targetTools = targetTools
    self.mousex = mousex
    self.mousey = mousey
    
    -- Create parameter manager
    self.paramManager = ParameterManager:init(activeTool, comp)
    
    -- Create propagation manager
    self.propManager = PropagationManager:init(activeTool, targetTools, comp)
    
    -- UI state
    self.preferredLiveModeActive = loadLiveModePreference()
    self.isLiveModeActive = false
    
    -- Create UI
    self:createUI()
    
    return self
end

-- Create the UI window and components
function UI:createUI()
    local ui = fu.UIManager
    self.ui = ui
    local disp = bmd.UIDispatcher(ui)
    self.disp = disp
    
    -- Create the window
    local win = disp:AddWindow({
        ID = 'PropagateWin',
        TargetID = "PropagateWin",
        WindowTitle = 'Propagate',
        Geometry = {100, 100, UI_WIDTH, UI_HEIGHT},
        WindowFlags = {
            WindowStaysOnTopHint = true,
            Tool = true,
        },
        Events = {
            Close = true,
            FocusIn = true,
            KeyPress = true,
            KeyRelease = true,
        },
        
        ui:VGroup{
            ID = 'root',
            Margins = {0, 0, 0, 0},
            Spacing = 0,
            
            -- Info text - Active label and Live checkbox on one line
            ui:HGroup{
                Spacing = 2,
                
                ui:Label{
                    ID = "activeLabel",
                    Text = "Active: " .. self.activeToolName,
                    MaximumSize = {250, 25},
                    Padding = {5, 5, 5, 5},
                    StyleSheet = [[
                        QLabel {
                            font-size: 11px;
                            color: rgb(200, 200, 200);
                            border: 1px solid rgb(230, 75, 61);
                            border-radius: 4px;
                        }
                    ]],
                },
                
                ui:HGap(25, 1.0),

                ui:Button{
                    ID = "liveToggle",
                    Text = "Live Mode",
                    Checkable = true,
                    Checked = self.preferredLiveModeActive,
                    MinimumSize = {105, 22},
                    MaximumSize = {105, 22},
                    Alignment = { AlignRight = true, AlignVCenter = true },
                    StyleSheet = [[
                        QPushButton {
                            font-size: 10px;
                            color: rgb(180, 180, 180);
                            background-color: rgb(50, 50, 50);
                            border: 1px solid rgb(80, 80, 80);
                            border-radius: 7px;
                            padding: 2px 8px;
                        }
                        QPushButton:hover {
                            background-color: rgb(60, 60, 60);
                            border: 1px solid rgb(100, 100, 100);
                        }
                        QPushButton:checked {
                            color: rgb(255, 255, 255);
                            background-color: rgb(60, 120, 60);
                            border: 1px solid rgb(80, 150, 80);
                        }
                        QPushButton:checked:hover {
                            background-color: rgb(70, 140, 70);
                            border: 1px solid rgb(100, 170, 100);
                        }
                    ]],
                },

            },

            -- Selected count label below
            ui:Label{
                ID = "selectedLabel",
                Text = "Selected: " .. (#self.targetTools + 1),
                MaximumSize = {100, 25},
                Padding = {5, 5, 5, 5},
                StyleSheet = [[
                    QLabel {
                        font-size: 11px;
                        color: rgb(200, 200, 200);
                        border: 1px solid rgba(0, 0, 0, 0);
                        border-radius: 4px;
                    }
                ]],
            },
            
            -- Status and buttons on same line
            ui:HGroup{
                -- Status will update while propagating
                ui:Label{
                    ID = "statusLabel",
                    Text = self.preferredLiveModeActive and "Live propagating..." or "Ready to capture changes...",
                    MinimumSize = {140, 22},
                    MaximumSize = {200, 22},
                    StyleSheet = [[
                        QLabel {
                            font-size: 9px;
                            color: rgb(200, 200, 200);
                                                    border: 1px solid rgba(0, 0, 0, 0);
                        border-radius: 4px;
                        }
                    ]],
                },

                ui:HGap(0, 1.0),

                ui:Button{
                    ID = "applyButton",
                    Text = "Apply",
                    Enabled = not self.preferredLiveModeActive,
                    MinimumSize = {50, 22},
                    MaximumSize = {50, 22},
                    StyleSheet = self.preferredLiveModeActive and
                        APPLY_BUTTON_DISABLED_STYLESHEET or
                        APPLY_BUTTON_ENABLED_STYLESHEET,
                },
                
--[[                 ui:Button{
                    ID = "cancelButton",
                    Text = "Cancel",
                    MinimumSize = {50, 22},
                    MaximumSize = {50, 22},
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgb(80, 80, 80);
                            color: rgb(200, 200, 200);
                            border: 1px solid rgb(170, 170, 170);
                            border-radius: 7px;
                            font-size: 11px;
                        }
                        QPushButton:hover {
                            background-color: rgb(100, 100, 100);
                        }
                        QPushButton:pressed {
                            background-color: rgb(60, 60, 60);
                        }
                    ]]--,
                --}, 
                --]]
            },
        },
    })
    
    self.win = win
    
    -- Get window items
    self.itm = win:GetItems()
    
    -- Timer for Live mode
    self.liveTimer = ui:Timer {
        ID = 'LiveTimer',
        Interval = TIMER_INTERVAL,
        SingleShot = false
    }
    
    -- Force recalculation of window layout to fit all elements
    win:RecalcLayout()
    
    -- Position window near mouse cursor if coordinates are available
    if self.mousex and self.mousey then
        win:Move({self.mousex - (UI_WIDTH/2), self.mousey - (UI_HEIGHT/2)})
    else
        -- Fallback to fixed position
        win:Move({200, 200})
    end
    
    -- Set up event handlers
    self:setupEventHandlers()
    
    if self.preferredLiveModeActive then
        self:setLiveModeActive(true, false)
    end

    -- Make sure window gets focus
    win:Show()
    
    -- Add ActionListener configuration to handle shortcuts
    self.configID = 'PropagateWin_Config'
    app:AddConfig(self.configID, {
        Target {
            ID = 'PropagateWin',
        },
        Hotkeys {
            Target = 'PropagateWin',
            Defaults = true,
            ESCAPE = 'Execute{cmd = [[app.UIManager:QueueEvent(obj, "Close", {})]]}',
            CONTROL_W = 'Execute{cmd = [[app.UIManager:QueueEvent(obj, "Close", {})]]}',
            I = 'Execute{cmd = [[app.UIManager:QueueEvent(obj, "Close", {})]]}',
        },
    })
end

function UI:setApplyButtonEnabled(enabled)
    enabled = enabled and true or false

    if not self.itm or not self.itm.applyButton then
        return
    end

    self.itm.applyButton.Enabled = enabled

    pcall(function()
        if self.itm.applyButton.SetEnabled then
            self.itm.applyButton:SetEnabled(enabled)
        end
    end)

    pcall(function()
        if self.itm.applyButton.SetAttrs then
            self.itm.applyButton:SetAttrs({ Enabled = enabled })
        end
    end)

    self.itm.applyButton.StyleSheet = enabled and
        APPLY_BUTTON_ENABLED_STYLESHEET or
        APPLY_BUTTON_DISABLED_STYLESHEET
end

function UI:setLiveModeActive(enabled, shouldSave)
    enabled = enabled and true or false

    if shouldSave ~= false then
        saveLiveModePreference(enabled)
    end

    if self.isLiveModeActive == enabled then
        return
    end

    self.isLiveModeActive = enabled
    self.itm.liveToggle.Checked = enabled

    if self.isLiveModeActive then
        if DEBUG_MODE then print("[Propagate] Live mode ENABLED") end
        if DEBUG_MODE then print("[Propagate] Starting Live Undo block") end
        self.comp:StartUndo("Propagate Live")
        self.liveTimer:Start()
        self.itm.statusLabel.Text = "Live propagating..."
        self:setApplyButtonEnabled(false)
    else
        if DEBUG_MODE then print("[Propagate] Live mode DISABLED") end
        if DEBUG_MODE then print("[Propagate] Ending Live Undo block") end
        self.comp:EndUndo()
        self.liveTimer:Stop()
        self.itm.statusLabel.Text = "Ready to capture changes..."
        self:setApplyButtonEnabled(true)
    end
end

-- Set up UI event handlers
function UI:setupEventHandlers()
    local win = self.win
    local itm = self.itm
    local disp = self.disp

-- Button handlers
function win.On.applyButton.Clicked(ev)
    if self.isLiveModeActive then
        return
    end

    if DEBUG_MODE then print("[Propagate] Apply button clicked") end
        self:applyChanges()
    bmd.wait(0.5)
    disp:ExitLoop()
end

function win.On.cancelButton.Clicked(ev)
        self.liveTimer:Stop() -- Stop timer on cancel
    -- End live undo block if it was active
        if self.isLiveModeActive then
        if DEBUG_MODE then print("[Propagate] Ending Live Undo block on Cancel") end
            self.comp:EndUndo()
    end
    disp:ExitLoop()
end

-- Live Toggle handler
function win.On.liveToggle.Clicked(ev)
        self:setLiveModeActive(itm.liveToggle.Checked, true)
end

-- Timer Timeout handler
function disp.On.Timeout(ev)
        if ev.who == 'LiveTimer' and self.isLiveModeActive then
            if DEBUG_MODE then print("[DEBUG] Live timer tick - checking for changes") end
            
            -- First find output connection changes
            local outputConnectionChanges = self.paramManager:findChangedOutputConnections(true)
            
            -- Then find connection changes
            local connectionChanges = self.paramManager:findChangedConnections(true)
            
            -- Then find expression changes
            local expressionChanges = self.paramManager:findChangedExpressions(true)
            
            -- Then find parameter changes, which will automatically skip parameters with expression or connection changes
            local changes = self.paramManager:findChangedParameters(true)

        local changeCount = 0
        for _ in pairs(changes) do changeCount = changeCount + 1 end

            local exprChangeCount = 0
            for _ in pairs(expressionChanges) do exprChangeCount = exprChangeCount + 1 end
            
            local connChangeCount = 0
            for _ in pairs(connectionChanges) do connChangeCount = connChangeCount + 1 end
            
            local outputConnChangeCount = 0
            for _ in pairs(outputConnectionChanges) do outputConnChangeCount = outputConnChangeCount + 1 end
            
            local totalChangeCount = changeCount + exprChangeCount + connChangeCount + outputConnChangeCount
            
            if DEBUG_MODE then 
                print("[DEBUG] Live timer found changes - Params: " .. changeCount .. ", Expr: " .. exprChangeCount .. ", Conn: " .. connChangeCount .. ", OutConn: " .. outputConnChangeCount)
                if changeCount > 0 then
                    for name, changeData in pairs(changes) do
                        print("[DEBUG] - Parameter change: " .. name .. " (animated: " .. tostring(changeData.isAnimated) .. ")")
                    end
                end
            end
            
            if totalChangeCount > 0 then
            -- Call propagateChanges with isLive = true and the found changes
                local success, appliedCount = self.propManager:propagateChanges(true, changes, expressionChanges, connectionChanges, outputConnectionChanges)
                if DEBUG_MODE then print("[DEBUG] Live propagation result - Success: " .. tostring(success) .. ", Applied: " .. (appliedCount or "nil")) end
            if success then
                    -- Update parameter manager's stored state
                    self.paramManager:updateStoredState(changes, expressionChanges, connectionChanges, outputConnectionChanges)
                    if DEBUG_MODE then print("[DEBUG] Live timer updated stored state") end
            end
        else
            if DEBUG_MODE then print("[DEBUG] Live timer - no changes found") end
        end
    end
end

-- Window close handler
function win.On.PropagateWin.Close(ev)
        self.liveTimer:Stop() -- Stop timer on close
    -- End live undo block if it was active
        if self.isLiveModeActive then
                    if DEBUG_MODE then print("[Propagate] Ending Live Undo block on Close") end
            self.comp:EndUndo()
    end
    disp:ExitLoop()
end

    -- Add Key handler
win.On.PropagateWin.KeyPress = function(ev)
    if ev.Key == 16777216 then -- ESC key
            self.liveTimer:Stop() -- Stop timer on ESC
        -- End live undo block if it was active
            if self.isLiveModeActive then
            if DEBUG_MODE then print("[Propagate] Ending Live Undo block on ESC") end
                self.comp:EndUndo()
        end
        disp:ExitLoop()
        return true
    elseif (ev.Key == 16777220 or -- Main Enter key
           ev.Key == 16777221) and 
           not self.isLiveModeActive then -- Numpad Enter key
        if DEBUG_MODE then print("[Propagate] Enter key detected for Manual Apply!") end
        -- Call the manual apply function
            self:applyChanges()
        return true
    end

    return false
    end
end

-- Apply changes manually
function UI:applyChanges()
    -- Clean, simplified output for manual apply
    
    -- First find output connection changes
    local outputConnectionChanges = self.paramManager:findChangedOutputConnections(false)
    
    -- Then find connection changes
    local connectionChanges = self.paramManager:findChangedConnections(false)
    
    -- Then find expression changes
    local expressionChanges = self.paramManager:findChangedExpressions(false)
    
    -- Then find parameter changes, which will automatically skip parameters with expression or connection changes
    local changes = self.paramManager:findChangedParameters(false)
    
    local changeCount = 0
    for _ in pairs(changes) do changeCount = changeCount + 1 end
    
    local exprChangeCount = 0
    for _ in pairs(expressionChanges) do exprChangeCount = exprChangeCount + 1 end
    
    local connChangeCount = 0
    for _ in pairs(connectionChanges) do connChangeCount = connChangeCount + 1 end
    
    local outputConnChangeCount = 0
    for _ in pairs(outputConnectionChanges) do outputConnChangeCount = outputConnChangeCount + 1 end
    
    local totalChangeCount = changeCount + exprChangeCount + connChangeCount + outputConnChangeCount
    
    if totalChangeCount > 0 then
        local success, appliedCount = self.propManager:propagateChanges(false, changes, expressionChanges, connectionChanges, outputConnectionChanges)
        if success then
            if DEBUG_MODE then print("[Propagate] Updating last propagated state for " .. appliedCount .. " changes.") end
            -- Update the cached state in parameter manager
            self.paramManager:updateStoredState(changes, expressionChanges, connectionChanges, outputConnectionChanges)
            bmd.wait(0.02) -- Shorter wait for manual apply feedback
        end
    else
        self.itm.statusLabel.Text = "No new changes detected"
        -- No verbose message needed for this common case
    end
end

-- Run the UI
function UI:run()
    self.disp:RunLoop()

-- Clean up
    app:RemoveConfig(self.configID)
    collectgarbage()
end

------------------------
-- Notification Function
------------------------
local function showNotification(message, duration, mousex, mousey)
    duration = duration or 0.5 -- Default 500ms
    
    local ui = fu.UIManager
    local disp = bmd.UIDispatcher(ui)
    local width, height = 170, 60
    
    local win = disp:AddWindow({
        ID = 'PropagateNotificationWin',
        TargetID = "PropagateNotificationWin",
        Geometry = {0, 0, width, height},
        WindowFlags = {
            WindowStaysOnTopHint = true,
        },
        
        ui:VGroup{
            ID = 'root',
            Margins = {0, 0, 0, 0},
            Spacing = 0,
            
            ui:Label{
                ID = "notificationLabel",
                Text = message,
                Alignment = {
                    AlignHCenter = true,
                    AlignVCenter = true,
                },
                StyleSheet = [[
                    QLabel {
                        font-size: 11px;
                        color: rgb(200, 200, 200);
                        background-color: rgba(60, 60, 60, 20);
                        border: 1px solid rgb(100, 100, 100);
                        border-radius: 7px;
                        border-style: solid;
                        padding: 0px;
                    }
                ]],
            },
        },
    })
    
    -- Position window near mouse cursor
    if mousex and mousey then
        win:Move({mousex - (width/2), mousey - (height/2) - 40})
    else
        win:Move({200, 200})
    end
    
    -- Enable window transparency
    win:SetAttribute('WA_TranslucentBackground', true)
    
    -- Add support for manually closing the window
    function win.On.PropagateNotificationWin.Clicked(ev)
        disp:ExitLoop()
    end
    
    win:Show()
    
    -- Show for specified duration then close
    bmd.wait(duration)
    disp:ExitLoop()
end

------------------------
-- Main Function
------------------------
local function main()
    -- Check if window already exists (toggle behavior)
    local existingWin = fu.UIManager:FindWindow("PropagateWin")
    if existingWin then
        if DEBUG_MODE then print("[Propagate] Window already open, closing it (Toggle behavior)") end
        existingWin:Close()
        return
    end

    -- Get mouse position from arguments
    if DEBUG_MODE then print("[Propagate] Mouse position:", mousex, mousey) end

    -- Get core objects
    local comp = fu:GetCurrentComp()
    if not comp then 
        print("[Propagate] No active composition")
        return 
    end
    
    local activeTool = comp.ActiveTool
    if not activeTool then
        print("[Propagate] No active tool selected")
        showNotification("No <span style='color: rgb(230, 75, 61);'>Active</span> Tool Selected", NOTIFICATION_DURATION, mousex, mousey)
        return 
    end
    
    -- Get target tools
    local selectedTools = comp:GetToolList(true) or {}
    local targetTools = {}
    for _, tool in pairs(selectedTools) do
        if tool ~= activeTool then
            table.insert(targetTools, tool)
        end
    end

    if #targetTools == 0 then
        print("[Propagate] No other tools selected. Nothing to propagate to.")
        showNotification("No Target Tools Selected", NOTIFICATION_DURATION, mousex, mousey)
        return
    end
    if DEBUG_MODE then
        print("[Propagate] Found " .. #targetTools .. " target tools")
        
        -- Add expression support info to console
        if INCLUDE_EXPRESSIONS then
            print("[Propagate] Expression propagation enabled")
        end
        
        -- Add connection support info to console
        if INCLUDE_CONNECTIONS then
            print("[Propagate] Connection propagation enabled")
        end
        
        -- Add output connection support info to console
        if INCLUDE_OUTPUT_CONNECTIONS then
            print("[Propagate] Output connection propagation enabled")
        end
    end
    
    -- Create and run the UI
    local ui = UI:init(comp, activeTool, targetTools, mousex, mousey)
    ui:run()
end

-- Run the main function
main()
