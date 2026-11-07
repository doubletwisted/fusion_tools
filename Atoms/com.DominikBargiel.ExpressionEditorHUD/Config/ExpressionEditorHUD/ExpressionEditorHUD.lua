--[[--
Expression Editor HUD - v1.29
by Dominik Bargiel dominikbargiel97@gmail.com
-------------------------------------------------------------------------------
Copyright Notice:
-------------------------------------------------------------------------------
This script is part of WSL (We Suck Less) tools collection.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, subject to
the following conditions:

1. The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.
   
2. Distribution is restricted to:
   - WSL Reactor package manager
   - We Suck Less forum (www.steakunderwater.com)
   - The author's GitHub repository (github.com/doubletwisted/fusion_tools)

Any other distribution or sharing of this script outside of these channels
requires explicit permission from the author.

Copyright © 2025 Dominik Bargiel
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
Description:
-------------------------------------------------------------------------------
A tool that displays and allows editing of expressions attached to the selected node.
Features include:
- Syntax highlighting for Fusion expressions
- Dynamic pagination for handling many expressions
- Automatic text field height adjustment
- Adjustable font size
- Copy/Paste functionality
- Remove button per expression (no modifier key)
- Status bar with helpful information

TODO:
- some kind of preset systemn
- window remember it's size and position 


Tips & Shortcuts 
- Press "E" to open the window for active node
- Remove button next to Apply removes the expression for that row
- Ctrl+W or Escape or Ctrl+F4 - Close the window 

-------------------------------------------------------------------------------
Version History:
-------------------------------------------------------------------------------
v1.0 - 2025-04-05
    - Initial release

v1.1 - 2026-01-17
    - Fixed window position calculation
    - Fixed window size calculation
    - debug mode
    - works with macros 
v1.2 - 2026-03-03
    - remove alt modifier to change apply button to remove 
    - add remove button
    - fixed colors for buttons

v1.21 - 2026-03-04
       - moved character count label to the right
v1.22 - 2026-09-13
    - Bound automatic sizing to 85% of the launch monitor
    - Budget editor heights across every page and preserve drafts on resize
v1.23 - 2026-09-13
    - Use native page and row stretching instead of resizing fields during dragging
    - Fill the expression area and track added newlines using explicit control IDs
v1.24 - 2026-09-13
    - Ignore queued events for windows not owned by this dispatcher
v1.25 - 2026-09-13
    - Preserve content-height ratios for very long expressions on opening
v1.26 - 2026-09-14
    - Pack pages by expression height instead of a fixed row count
    - Use proportional newline sizing without giving one field a special boost
v1.27 - 2026-09-14
    - Fit opening heights to text with less bottom padding
    - Request 20 pixels of field growth per added newline within the current window
v1.28 - 2026-09-14
    - Allocate equal line counts equally without large per-field minimum heights
    - Coalesce resizing and fill the available area without resetting constraints
    - Center long pages at the 85% opening height with frame space reserved
v1.29 - 2026-09-14
    - Recalculate field proportions on removed as well as added newlines
--]]--

local VERSION = "1.29"

-- Debug mode (set true to enable verbose logging)
local DEBUG = false
local function dprint(...)
    if DEBUG then
        _G.print(...)
    end
end
local function iprint(...)
    _G.print(...)
end
local print = dprint

-- Variables for window dragging
local dragPos = nil
local dragging = false

-- At the top of your script
local lastMouseX, lastMouseY = 0, 0
local isDragging = false

-- Store initial window width for comparison
local lastWindowWidth = 0

-- Get arguments passed from the .fu file
print("[ExpressionEditor Lua] Mouse position:", mousex, mousey)


-- Get the active tool
local comp = fu:GetCurrentComp()
if not comp then 
    iprint("[ExpressionEditor Lua] No active composition")
    return 
end

local tool = comp.ActiveTool
if not tool then 
    iprint("[ExpressionEditor Lua] No active tool")
    return 
end

-- Get tool attributes
local attrs = tool:GetAttrs()
local toolName = attrs['TOOLS_Name']

print("[ExpressionEditor Lua] Active tool:", toolName)

-- Set up UI
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local editorLoopRunning = false
local exitEventLoop = disp.ExitLoop
rawset(disp, 'ExitLoop', function(self, ...)
    editorLoopRunning = false
    return exitEventLoop(self, ...)
end)

-- UIManager may deliver queued events from a retired/different window. Fusion's
-- Dispatch indexes that window's On table before checking whether it exists.
-- Filter by ownership on this dispatcher instance; keep Fusion's normal event
-- delivery and ExitLoop behavior for our own windows.
local ownedWindowIDs = {}
local dispatchEvent = disp.Dispatch
rawset(disp, "Dispatch", function(self, ev)
    if ev and ev.window and not ownedWindowIDs[ev.window] then return end
    return dispatchEvent(self, ev)
end)

-- Check if a window already exists for this tool
-- We'll use a unique ID based on the tool name
local windowID = 'ExpressionEditorWin_' .. toolName .. '_' .. os.time() -- Add timestamp to make each ID unique
ownedWindowIDs[windowID] = true

-- No longer need to check for existing windows since each will have a unique ID
-- Look for an existing window with this ID
-- local existingWindow = ui:FindWindow(windowID)
-- if existingWindow then
--     print("[ExpressionEditor Lua] Window already exists for tool: " .. toolName)
--     -- Bring existing window to front
--     existingWindow:Raise()
--     existingWindow:ActivateWindow()
--     return
-- end

-- Function to get expressions from the node
local function getNodeExpressions(tool)
    local expressions = {}
    
    -- Try to get tool settings using Composition.CopySettings
    print("[ExpressionEditor Lua] Trying comp:CopySettings(tool)")
    local success, settings = pcall(function()
        return comp:CopySettings(tool)
    end)
    
    if success and settings and settings.Tools then
        local toolName = tool:GetAttrs().TOOLS_Name
        local toolSettings = settings.Tools[toolName]
        
        if toolSettings and toolSettings.Inputs then
            print("[ExpressionEditor Lua] Found inputs in settings")

            -- Process each input
            for inputName, inputData in pairs(toolSettings.Inputs) do
                print("[ExpressionEditor Lua] Processing input: " .. inputName)
            end
            
            -- Process each input
            for inputName, inputData in pairs(toolSettings.Inputs) do
                print("[ExpressionEditor Lua] Processing input: " .. inputName)
                -- Some macro inputs are numbers or non-table values; guard before indexing
                if type(inputData) == "table" and inputData.Expression ~= nil then
                    print("[ExpressionEditor Lua] Found expression for " .. inputName .. ": " .. inputData.Expression)
                    
                    table.insert(expressions, {
                        name = inputName,
                        expression = inputData.Expression,
                    })
                end
            end
        end
    else
        print("[ExpressionEditor Lua] CopySettings failed or no settings found")
    end
    
    -- Sort by input name
    table.sort(expressions, function(a, b) return a.name < b.name end)
    
    -- Debug: Print all expressions found
    print("[ExpressionEditor Lua] Expressions found:", #expressions)
    for _, expr in ipairs(expressions) do
        print("[ExpressionEditor Lua]   " .. expr.name .. " = " .. expr.expression)
    end
    
    return expressions
end

-- Get expressions from the node
local nodeExpressions = getNodeExpressions(tool)

-- Track if expressions have been modified by the user
local expressionsModified = false

-- Default font size
local currentFontSize = 11

-- Dynamic pagination settings - initially we'll use a placeholder that will be properly calculated
local EXPRESSIONS_PER_PAGE = 6  -- Start with a conservative value, will be updated before window creation
local expressionPageRanges = {}
local currentPage = 1
local totalPages = 1 -- Will be recalculated
-- Manual tracking of the current stack page index (0-based)
local currentPageIndex = 0

-- Query the monitor containing the launch point, in desktop coordinates.
-- Fusion's saved Global.Main.Window preference is not a screen measurement.
local function getScreenBounds(x, y)
    local ok, bounds = pcall(function()
        local ffi = require("ffi")
        if ffi.os == "Windows" then
            pcall(ffi.cdef, [[
                typedef struct { long x, y; } EEHUD_POINT;
                typedef struct { long left, top, right, bottom; } EEHUD_RECT;
                typedef struct { unsigned long cbSize; EEHUD_RECT monitor, work; unsigned long flags; } EEHUD_MONITORINFO;
                void* __stdcall MonitorFromPoint(EEHUD_POINT point, unsigned long flags);
                int __stdcall GetMonitorInfoW(void* monitor, EEHUD_MONITORINFO* info);
                int __stdcall GetCursorPos(EEHUD_POINT* point);
            ]])
            local user32 = ffi.load("user32")
            local point = ffi.new("EEHUD_POINT")
            if x and y then point.x, point.y = x, y else user32.GetCursorPos(point) end
            local monitor = user32.MonitorFromPoint(point, 2)
            local info = ffi.new("EEHUD_MONITORINFO")
            info.cbSize = ffi.sizeof(info)
            if user32.GetMonitorInfoW(monitor, info) == 0 then return nil end
            local r = info.work
            return {x=tonumber(r.left), y=tonumber(r.top),
                width=tonumber(r.right-r.left), height=tonumber(r.bottom-r.top)}
        elseif ffi.os == "OSX" then
            pcall(ffi.cdef, [[
                typedef struct { double x, y; } EEHUD_CGPoint;
                typedef struct { double width, height; } EEHUD_CGSize;
                typedef struct { EEHUD_CGPoint origin; EEHUD_CGSize size; } EEHUD_CGRect;
                int CGGetActiveDisplayList(unsigned int maxDisplays, unsigned int* displays, unsigned int* count);
                unsigned int CGMainDisplayID(void);
                EEHUD_CGRect CGDisplayBounds(unsigned int display);
            ]])
            local cg = ffi.load("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
            local displays, count = ffi.new("unsigned int[32]"), ffi.new("unsigned int[1]")
            local selected = cg.CGDisplayBounds(cg.CGMainDisplayID())
            if x and y and cg.CGGetActiveDisplayList(32, displays, count) == 0 then
                for i = 0, tonumber(count[0]) - 1 do
                    local r = cg.CGDisplayBounds(displays[i])
                    if x >= r.origin.x and x < r.origin.x+r.size.width and
                        y >= r.origin.y and y < r.origin.y+r.size.height then
                        selected = r
                        break
                    end
                end
            end
            return {x=tonumber(selected.origin.x), y=tonumber(selected.origin.y),
                width=tonumber(selected.size.width), height=tonumber(selected.size.height)}
        end
    end)
    if ok and bounds and bounds.width > 0 and bounds.height > 0 then return bounds end

    -- Conservative fallback for hosts without native display access. Ignore
    -- unset (-1) preferences and never trust a saved window larger than 1024x768.
    local pref = {}
    pcall(function() pref = fusion:GetPrefs("Global.Main.Window") or {} end)
    if type(pref) ~= "table" then pref = {} end
    local w, h = tonumber(pref.Width or pref.width), tonumber(pref.Height or pref.height)
    return {x=0, y=0, width=(w and w > 0) and math.min(w, 1024) or 1024,
        height=(h and h > 0) and math.min(h, 768) or 768}
end

local screen = getScreenBounds(mousex, mousey)
-- Reserve the native title bar/frame as well as the requested 15% margin.
local maxHeight = math.floor(screen.height * 0.85) - 40
local maxWidth = math.floor(screen.width * 0.85) - 16
-- Root margins, toolbar/footer and gaps measured in Fusion's native layout.
local WINDOW_CHROME_HEIGHT = 82
local ROW_CHROME_HEIGHT = 37
local layoutBusy = false
local buildingWindow = false
local layoutQueued = false
local layoutLineCounts = {}

local function getMaxExpressionHeight()
    local count = math.max(1, EXPRESSIONS_PER_PAGE)
    return math.max(1, math.floor((maxHeight - WINDOW_CHROME_HEIGHT) / count) - ROW_CHROME_HEIGHT)
end

-- Global to store expression controls
local expressionControls = {}

-- Forward declarations
local win = nil

-- Function to calculate optimal number of expressions per page based on window height
function calculateOptimalExpressionsPerPage(height)
    height = math.min(height or maxHeight, maxHeight)
    local rowHeight = calculateTextHeight("") + ROW_CHROME_HEIGHT
    local expressionsCount = math.max(1, math.min(15,
        math.floor((height - WINDOW_CHROME_HEIGHT) / rowHeight)))

    return expressionsCount
end

-- Function to create window with proper pagination using QStackedWidget
function createExpressionEditorWindow()
    buildingWindow = true
    print("[ExpressionEditor Lua] Creating window with QStackedWidget for pagination")
    
    -- Set initial window size - need this to calculate optimal expressions per page
    -- Pack pages using actual content, not the two-line minimum. Keep those
    -- pages stable while editing/resizing so drafts and navigation survive.
    expressionPageRanges = buildExpressionPages(nodeExpressions, math.min(700, maxWidth) - 40, maxHeight)
    totalPages = #expressionPageRanges
    EXPRESSIONS_PER_PAGE = 1
    for _, range in ipairs(expressionPageRanges) do
        EXPRESSIONS_PER_PAGE = math.max(EXPRESSIONS_PER_PAGE, range.last - range.first + 1)
    end
    print("[ExpressionEditor Lua] Initial pagination: ", EXPRESSIONS_PER_PAGE, "expressions per page,", totalPages, "total pages")
    
    -- Create pages for the stacked widget (one page for each set of expressions)
    local stackedPages = {}
    
    -- Reset the current page index
    currentPageIndex = 0
    
    -- Create each page as a VGroup
    for page = 1, totalPages do
        local startIndex = expressionPageRanges[page].first
        local endIndex = expressionPageRanges[page].last
        print("[ExpressionEditor Lua] Creating page", page, "with expressions", startIndex, "to", endIndex)
        
        -- Create container for this page
        local pageGroup = ui:VGroup{
            ID = 'page_' .. page,
            Weight = 1.0,
            Spacing = 10,
        }
        
        -- Add expressions for this page
        for i = startIndex, endIndex do
            if i <= #nodeExpressions then
                local expr = nodeExpressions[i]
                if not expr or not expr.name or not expr.expression then
                    iprint("[ExpressionEditor Lua] Warning: Invalid expression at index", i)
                    goto continue
                end
                
                -- Clean name for IDs
                local cleanName = expr.name:gsub("[^%w_]", "_")
                

                -- Create expression control
                local exprControl = ui:VGroup{
                    ID = "expressionGroup_" .. cleanName,
                    Weight = 1.0,
                    Margins = {2, 2, 2, 2}, -- Reduced from 5,5,5,5
                    
                    -- Row with name and buttons
                    ui:HGroup{
                        ID = "nameAndButtons_" .. cleanName,
                        Spacing = 5,
                        Weight = 0,
                        
                        -- Expression name label: uses all space from left up to char count (widen window to see full name)
                        ui:Label{
                            ID = "label_" .. cleanName,
                            Text = expr.name,
                            Weight = 1.0,
                            MinimumSize = {40, 20},
                            Alignment = { AlignLeft = true, AlignVCenter = true },
                            StyleSheet = [[
                                QLabel {
                                    color: rgb(220, 220, 150);
                                    font-size: 12px;
                                    font-weight: bold;
                                    background-color: rgba(70, 70, 70, 0);
                                }
                            ]],
                        },
                        
                        
                        -- Character count label (anchored to the left of Copy)
                        ui:Label{
                            ID = "charCount_" .. cleanName,
                            Text = #expr.expression .. " chars",
                            MinimumSize = {60, 20},
                            MaximumSize = {60, 20},
                            Alignment = { AlignHCenter = true, AlignVCenter = true },
                            StyleSheet = [[
                                QLabel {
                                    color: rgb(120, 120, 120);
                                    font-size: 11px;
                                    background-color: rgba(70, 70, 70, 0);
                                }
                            ]],
                        },
                        
                        
--[[                         -- Hide button
                        ui:Button{
                            ID = "hide_" .. cleanName,
                            Text = "Hide",
                            MinimumSize = {40, 22},
                            MaximumSize = {60, 22},
                            StyleSheet = [[
                                QPushButton {
                                    background-color: rgba(70, 70, 70, 0);
                                    color: rgb(200, 200, 200);
                                    border: 1px solid rgba(100, 100, 100, 0);
                                    font-size: 11px;
                                }
                                QPushButton:hover {
                                    background-color: rgba(90, 90, 90, 220);
                                }
                                QPushButton:pressed {
                                    background-color: rgba(50, 50, 50, 220);
                                }
                            ]]--,
                        --},
                         
                        -- Copy button
                        ui:Button{
                            ID = "copy_" .. cleanName,
                            Text = "Copy",
                            MinimumSize = {40, 22},
                            MaximumSize = {40, 22},
                            StyleSheet = [[
                                QPushButton {
                                    background-color: rgba(100, 80, 40, 0);
                                    color: rgb(200, 200, 200);
                                    font-size: 11px;
                                }
                                QPushButton:hover {
                                    color: rgb(255, 255, 255);
                                    text-decoration: underline;
                                }
                                QPushButton:pressed {
                                    background-color: rgba(80, 60, 20, 220);
                                }
                            ]],
                        },
                        
                        -- Paste button
                        ui:Button{
                            ID = "paste_" .. cleanName,
                            Text = "Paste",
                            MinimumSize = {40, 22},
                            MaximumSize = {40, 22},
                            StyleSheet = [[
                                QPushButton {
                                    background-color: rgba(100, 80, 40, 0);
                                    color: rgb(200, 200, 200);
                                    font-size: 11px;
                                }
                                QPushButton:hover {
                                    color: rgb(255, 255, 255);
                                    text-decoration: underline;
                                }
                                QPushButton:pressed {
                                    background-color: rgba(20, 60, 80, 220);
                                }
                            ]],
                        },
                        
                        ui:HGap(20, 0.1), -- Fill remaining space to push buttons to right
                        
                        -- Remove button
                        ui:Button{
                            ID = "remove_" .. cleanName,
                            Text = "Remove",
                            ToolTip = "Remove this expression from the node for which Expression editor was open",
                            MinimumSize = {50, 22},
                            MaximumSize = {50, 22},
                            StyleSheet = [[
                                QPushButton {
                                    background-color: rgba(80, 80, 80, 100);
                                    color: rgb(150, 150, 150);
                                    border-radius: 7px;
                                    font-size: 11px;
                                }
                                QPushButton:hover {
                                    background-color: rgba(180, 60, 60, 220);
                                    color: white;
                                }
                                QPushButton:pressed {
                                    background-color: rgba(100, 20, 20, 220);
                                }
                            ]],
                        },
                        
                        
                        -- Apply button
                        ui:Button{
                            ID = "apply_" .. cleanName,
                            Text = "Apply",
                            ToolTip = "Apply this expression to node for which Expression editor was open",
                            MinimumSize = {50, 22},
                            MaximumSize = {50, 22},    
                            StyleSheet = [[
                                QPushButton {
                                    background-color: rgba(80, 80, 80, 100);
                                    color: rgb(150, 150, 150);
                                    border-radius: 7px;
                                    font-size: 11px;
                                }
                                QPushButton:disabled {
                                    background-color: rgba(60, 60, 60, 100);
                                    color: rgb(120, 120, 120);
                                    border: 0px solid rgb(182, 192, 0);
                                }
                                QPushButton:hover {
                                    background-color: rgba(60, 120, 60, 220);
                                    color: rgb(255, 255, 255);
                                }
                                QPushButton:pressed {
                                    background-color: rgba(90, 200, 90, 220);
                                    color: rgb(200, 200, 200);
                                }
                            ]],
                        },
                    },
                    
                    -- Expression text with syntax highlighting - directly in the group
                    ui:TextEdit{
                        ID = "expr_" .. cleanName,
                        Text = expr.expression,
                        Weight = 1.0,
                        MinimumSize = {300, 0},
                        MaximumSize = {16777215, 16777215}, -- Native layout supplies the height
                        WordWrapMode = "WrapAtWordBoundaryOrAnywhere",
                        AcceptRichText = false,
                        ReadOnly = false,
                        Lexer = "fusion",
                        StyleSheet = string.format([[
                            QTextEdit {
                                background-color: rgba(25, 25, 25, 220);
                                color: rgb(200, 200, 200);
                                border: none;
                                border-radius: 2px;
                                padding: 5px;
                                font-family: Droid Sans Mono;
                                font-size: %dpx;
                                selection-background-color: #4376A1;
                            }
                            QTextEdit:focus {
                                border: 1px solid rgb(60, 120, 60);
                            }
                        ]], currentFontSize),
                    },
                }
                
                pageGroup:AddChild(exprControl)
                print("[ExpressionEditor Lua] Added expression", i, "to page", page)
                
                ::continue::
            end
        end
        
        -- Add this page to our collection
        table.insert(stackedPages, pageGroup)
    end
    
    -- If no expressions found, create an empty page with a message
    if #stackedPages == 0 then
        local emptyPage = ui:VGroup{
            ID = 'emptyPage',
            ui:Label{
                ID = 'noExpressionsLabel',
                Text = "No expressions found on this node",
                StyleSheet = [[
                    QLabel {
                        color: rgb(200, 200, 200);
                        font-size: 14px;
                        margin: 20px;
                        padding: 10px;
                        background-color: rgba(40, 40, 40, 100);
                        border: 1px solid rgb(60, 60, 60);
                        border-radius: 3px;
                    }
                ]],
                Alignment = { AlignHCenter = true },
            }
        }
        table.insert(stackedPages, emptyPage)
        totalPages = 1
    end

    -- Build information text
    local info = "Node: " .. attrs['TOOLS_Name'] .. "\nExpressions Found: " .. #nodeExpressions

    -- Create the window with a stacked widget for pages
    win = disp:AddWindow({
        ID = windowID,
        TargetID = windowID,
        WindowTitle = 'Expression Editor - ' .. toolName,
        Resize = true,
        MaximumSize = {maxWidth, maxHeight},
        WindowFlags = {
            Popup = true,
            --WindowStaysOnTopHint = true,
            Tool = true,
            --FramelessWindowHint = true,
        },
        Events = {
            Resize = true,
            Close = true,
            FocusIn = true,
            FocusOut = true,
            --MousePress = true,
            --MouseRelease = true,
            --MouseMove = true,
        },
        Geometry = {screen.x + 20, screen.y + 40, math.min(700, maxWidth), math.min(600, maxHeight)},
        
        ui:VGroup{
            ID = 'root',
            Weight = 1.0,
            StyleSheet = [[
                QWidget {
                    background-color: rgba(30, 30, 30, 180);
                    border-radius: 7px;
                }
            ]],
            
            -- Title bar with all header elements grouped together
            ui:HGroup{
                ID = 'titleBar',
                Weight = 0,
                Spacing = 5,
                
                StyleSheet = [[
                    QWidget {
                        background-color: rgba(0, 0, 0, 10);
                    }
                ]],
                
                -- Left side: Refresh button
                ui:Button{
                    ID = "refreshButton",
                    Text = "Refresh",
                    ToolTip = "Refresh the expression editor for current ACTIVE node",
                    MinimumSize = {50, 22},
                    MaximumSize = {50, 22},
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgba(40, 100, 40, 0);
                            color: rgb(200, 200, 200);
                            border: 1px solid rgb(170, 170, 170);
                            border-radius: 7px;
                            font-size: 11px;
                        }
                        QPushButton:hover {
                            background-color: rgba(120, 120, 120, 200);
                            color: rgb(255, 255, 255);
                        }
                        QPushButton:pressed {
                            background-color: rgba(180, 180, 180, 220);
                        }
                    ]],
                },
                
                ui:HGap(10, 1.25), -- Flexible space to push font controls to right
                
                -- Middle: Page navigation
                ui:HGroup{
                    ID = 'paginationControls',
                    Spacing = 2,
                    
                    -- Page number label
                    ui:Label{
                        ID = "totalPages",
                        Text = totalPages .. " pages",
                        Alignment = { AlignLeft = true, AlignVCenter = true },
                        MinimumSize = {50, 22},
                        MaximumSize = {50, 22},
                        StyleSheet = [[
                            QLabel {
                                color: rgb(120, 120, 120);
                                font-size: 10px;
                                padding: 1px;
                            }
                        ]],
                    },
                    
                    
                    ui:Button{
                        ID = "prevPageButton",
                        Text = "◀ Page " .. (currentPageIndex),
                        Enabled = false, -- Will be updated after stacked widget is set up
                        MinimumSize = {55, 22},
                        MaximumSize = {55, 22},
                        StyleSheet = [[
                            QPushButton {
                                background-color: rgba(40, 100, 40, 0);
                                color: rgb(200, 200, 200);
                                border: 1px solid rgb(170, 170, 170);
                                border-radius: 7px;
                                font-size: 11px;
                            }
                            QPushButton:disabled {
                                background-color: rgba(60, 60, 60, 100);
                                color: rgb(120, 120, 120);
                                border: 0px solid rgb(182, 192, 0);
                            }
                            QPushButton:hover {
                                background-color: rgba(120, 120, 120, 200);
                                color: rgb(255, 255, 255);
                            }
                            QPushButton:pressed {
                                background-color: rgba(180, 180, 180, 220);
                            }
                        ]],
                    },
                    
                    ui:Button{
                        ID = "nextPageButton",
                        Text = "Page " .. (currentPageIndex + 2) .. " ▶",
                        Enabled = totalPages > 1, -- Only enable if we have more than one page
                        MinimumSize = {55, 22},
                        MaximumSize = {55, 22},
                        StyleSheet = [[
                            QPushButton {
                                background-color: rgba(40, 100, 40, 0);
                                color: rgb(200, 200, 200);
                                border: 1px solid rgb(170, 170, 170);
                                border-radius: 7px;
                                font-size: 11px;
                            }
                            QPushButton:disabled {
                                background-color: rgba(60, 60, 60, 100);
                                color: rgb(120, 120, 120);
                                border: 0px solid rgb(182, 192, 0);
                            }
                            QPushButton:hover {
                                background-color: rgba(120, 120, 120, 200);
                                color: rgb(255, 255, 255);
                            }
                            QPushButton:pressed {
                                background-color: rgba(180, 180, 180, 220);
                            }
                        ]],
                    },
                },
                
                ui:HGap(10, 1.0), -- Flexible space to push font controls to right
                
                -- Right: Font size controls
                ui:Label{ 
                    Text = "Font", 
                    Alignment = { AlignRight = true, AlignVCenter = true },
                    MinimumSize = {30, 22},
                    MaximumSize = {30, 22},
                    StyleSheet = [[
                        QLabel { 
                            color: rgb(120, 120, 120);
                            background-color: rgba(0, 0, 0, 0);
                            font-size: 12px; 
                        }
                    ]],
                },
                
                ui:Button{ 
                    ID = "decreaseFontSize", 
                    Text = "-", 
                    MinimumSize = {20, 20},
                    MaximumSize = {20, 20},
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgba(60, 60, 60, 200);
                            color: white;
                            border: 1px solid rgb(80, 80, 80);
                            border-radius: 4px;
                            font-size: 11px;
                        }
                        QPushButton:hover {
                            background-color: rgba(120, 120, 120, 200);
                            color: rgb(255, 255, 255);
                        }
                    ]],
                },
                
                ui:Button{ 
                    ID = "increaseFontSize", 
                    Text = "+", 
                    MinimumSize = {20, 20},
                    MaximumSize = {20, 20},
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgba(60, 60, 60, 200);
                            color: white;
                            border: 1px solid rgb(80, 80, 80);
                            border-radius: 4px;
                            font-size: 11px;
                        }
                        QPushButton:hover {
                            background-color: rgba(120, 120, 120, 200);
                            color: rgb(255, 255, 255);
                        }
                    ]],
                },
                
                
--[[                 -- Close button
                ui:Button{
                    ID = "closeButton",
                    Text = "×",
                    MinimumSize = {20, 20},
                    MaximumSize = {20, 20},
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgba(60, 60, 60, 200);
                            color: white;
                            border: 1px solid rgb(100, 100, 100);
                            border-radius: 4px;
                            font-size: 11px;
                            font-weight: bold;
                        }
                        QPushButton:hover {
                            background-color: rgba(180, 60, 60, 200);
                        }
                    ]]
                --}, 

                
            },
            
            ui:VGap(5, 0.0),

            -- The stacked widget - core of our pagination system
            ui:Stack{
                ID = 'expressionPagesStack',
                Weight = 1.0,
                CurrentIndex = 0, -- Start at the first page (index 0)
                MinimumSize = {600, 0},
                Margins = {0, 0, 0, 0},
                
                -- Add all our pages to the stack
                unpack(stackedPages)
            },
            
            -- Status bar - combine with info button in one row
            ui:HGroup{
                ID = 'statusBarWithInfo',
                Weight = 0,
                Spacing = 2,
                Margins = {0, 0, 0, 0},
                
                -- Status text on the left
                ui:Label{
                    ID = 'statusBar',
                    Text = "Ready.",
                    ToolTip = "Status of the expression editor",
                    Alignment = { AlignLeft = true, AlignBottom = true },
                    MinimumSize = {300, 30},
                    MaximumSize = {6666, 30},
                    Margins = {0, 0, 0, 0},
                    StyleSheet = [[
                        QLabel {
                            color: rgb(200, 200, 200);
                            font-size: 12px;
                            margin-top: 1px;
                            margin-bottom: 1px;
                            padding-left: 10px;
                            background-color: transparent;
                        }
                    ]],
                },
                
                ui:Label{
                    ID = 'versionLabel',
                    Text = "v" .. VERSION,
                    ToolTip = "Version of the expression editor",
                    Alignment = { AlignRight = true },
                    MinimumSize = {100, 30},
                    MaximumSize = {100, 30},
                    Margins = {0, 0, 0, 0},
                    StyleSheet = [[
                        QLabel {
                            color: rgb(120, 120, 120);
                            font-size: 12px;
                            margin-top: 1px;
                            margin-bottom: 1px;
                            padding-left: 10px;
                            background-color: transparent;
                        }
                    ]],
                },

                -- Info button in the right side of the same row
                ui:Button{
                    ID = "infoButton",
                    Text = "?",
                    ToolTip = "Show information and help",
                    MinimumSize = {22, 22},
                    MaximumSize = {22, 22},
                    Alignment = { AlignBottom = true,  },
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgba(60, 60, 60, 200);
                            color: white;
                            border: 1px solid rgb(80, 80, 80);
                            border-radius: 4px;
                            font-size: 11px;
                        }
                        QPushButton:hover {
                            background-color: rgba(120, 120, 120, 200);
                            color: rgb(255, 255, 255);
                        }
                    ]],
                },
            },
        },
    })

    -- Set up UI handlers

    -- Window close handler
    win.On[windowID] = {
        Close = function(ev)
            disp:ExitLoop()
        end,
        
        -- Coalesce resize events. Only maxima change; minima stay small and
        -- no constraints are cleared or reset during a drag.
        Resize = function(ev)
            if buildingWindow or layoutBusy then return end
            layoutQueued = true
        end,

        MousePress = function(ev)
            print("[ExpressionEditor Lua] Mouse pressed")
            dragging = true
        end,

        MouseRelease = function(ev)
            print("[ExpressionEditor Lua] Mouse released")
            dragging = false
        end,
        
        MouseMove = function(ev)
            print("[ExpressionEditor Lua] Mouse moved")
        end
    }

    -- Close button
    win.On.closeButton = {
        Clicked = function(ev)
            disp:ExitLoop()
        end
    }

    -- Previous page button
    win.On.prevPageButton = {
        Clicked = function(ev)
            local stack = win:Find("expressionPagesStack")
            if stack then
                -- Use our manually tracked index instead of stack.CurrentIndex
                -- Ensure we don't go below 0
                local newIndex = math.max(0, currentPageIndex - 1)
                
                print("[ExpressionEditor Lua] Switching to previous page, current:", currentPageIndex, "new:", newIndex)
                
                -- Update our tracking variable
                currentPageIndex = newIndex
                
                -- Set current index on stack
                stack.CurrentIndex = newIndex
                
                -- Directly manage visibility since stack.CurrentIndex isn't reliable
                local children = nil
                pcall(function() 
                    if type(stack.GetChildren) == "function" then
                        children = stack:GetChildren()
                    end
                end)
                
                if children then
                    for i, child in ipairs(children) do
                        local success = pcall(function() 
                            child.Visible = (i-1 == newIndex)
                            print("[ExpressionEditor Lua] Set page", i-1, "visibility to", (i-1 == newIndex))
                        end)
                        
                        if not success then
                            pcall(function()
                                if type(child.SetVisible) == "function" then
                                    child:SetVisible(i-1 == newIndex)
                                    print("[ExpressionEditor Lua] Set page", i-1, "visibility using SetVisible:", (i-1 == newIndex))
                                end
                            end)
                        end
                    end
                end
                
                -- Update pagination controls
                updatePaginationControls(newIndex, totalPages)
                updateWindowSize()
            end
        end
    }

    -- Next page button
    win.On.nextPageButton = {
        Clicked = function(ev)
            local stack = win:Find("expressionPagesStack")
            if stack then
                -- Use our manually tracked index instead of stack.CurrentIndex
                -- Ensure we don't exceed total pages
                local newIndex = math.min(totalPages - 1, currentPageIndex + 1)
                
                print("[ExpressionEditor Lua] Switching to next page, current:", currentPageIndex, "new:", newIndex)
                
                -- Update our tracking variable
                currentPageIndex = newIndex
                
                -- Set current index on stack
                stack.CurrentIndex = newIndex
                
                -- Directly manage visibility since stack.CurrentIndex isn't reliable
                local children = nil
                pcall(function() 
                    if type(stack.GetChildren) == "function" then
                        children = stack:GetChildren()
                    end
                end)
                
                if children then
                    for i, child in ipairs(children) do
                        local success = pcall(function() 
                            child.Visible = (i-1 == newIndex)
                            print("[ExpressionEditor Lua] Set page", i-1, "visibility to", (i-1 == newIndex))
                        end)
                        
                        if not success then
                            pcall(function()
                                if type(child.SetVisible) == "function" then
                                    child:SetVisible(i-1 == newIndex)
                                    print("[ExpressionEditor Lua] Set page", i-1, "visibility using SetVisible:", (i-1 == newIndex))
                                end
                            end)
                        end
                    end
                end
                
                -- Update pagination controls
                updatePaginationControls(newIndex, totalPages)
                updateWindowSize()
            end
        end
    }

    -- Font size handlers
    win.On.decreaseFontSize = {
        Clicked = function(ev)
            updateFontSize(math.max(8, currentFontSize - 1))
        end
    }

    win.On.increaseFontSize = {
        Clicked = function(ev)
            updateFontSize(currentFontSize + 1)
        end
    }

    -- Refresh button
    win.On.refreshButton = {
        Clicked = function(ev)
            refreshExpressions()
        end
    }

    -- Setup expression button handlers
    setupExpressionButtons()

    -- Ensure pagination controls are correctly set
    updatePaginationControls(0, totalPages)

    -- Size every page before showing; hidden pages must fit the same budget.
    buildingWindow = false
    updateWindowSize()
    
    -- Force layout calculation before showing
    win:RecalcLayout()
    
    -- Center the opening window on the launch monitor, reserving frame space.
    local g = win:GetGeometry()
    clampWindowPosition(screen.x + (screen.width - (g.width or g[3])) / 2,
        screen.y + (screen.height - (g.height or g[4]) - 40) / 2 + 24)
    win:Show()

    return win
end

-- Setup expression button handlers
function setupExpressionButtons()
    print("[ExpressionEditor Lua] Setting up expression button handlers")
    local allItems = win:GetItems()
    local buttonCount = 0
    
    -- Track original expressions to detect changes - make this global to the script
    originalExpressions = {}
    
    if allItems then
        -- Register handlers for buttons using ID patterns
        for id, item in pairs(allItems) do
            -- Auto-adjust expression text field heights
            if id:match("^expr_") then
                local exprName = id:match("^expr_(.+)$")
                local exprText = win:Find(id)
                
                if exprText then
                    -- Calculate appropriate height based on content
                    adjustExpressionTextHeight(exprText, id)
                end
            end
            
            -- Check if it's a button by ID naming convention
            if id:match("^copy_") or id:match("^paste_") or id:match("^remove_") or id:match("^apply_") or id:match("^hide_") then
                buttonCount = buttonCount + 1
                print("[ExpressionEditor Lua] Found button:", id)
                
                -- Extract expression name from button ID
                local exprName = nil
                if id:match("^copy_(.+)$") then
                    exprName = id:match("^copy_(.+)$")
                elseif id:match("^paste_(.+)$") then
                    exprName = id:match("^paste_(.+)$")
                elseif id:match("^remove_(.+)$") then
                    exprName = id:match("^remove_(.+)$")
                elseif id:match("^apply_(.+)$") then
                    exprName = id:match("^apply_(.+)$")
                elseif id:match("^hide_(.+)$") then
                    exprName = id:match("^hide_(.+)$")
                end
                
                if exprName then
                    print("[ExpressionEditor Lua] Button for expression:", exprName)
                    
                    -- Store original expression text for comparison
                    local exprTextID = "expr_" .. exprName
                    local exprText = win:Find(exprTextID)
                    if exprText and not originalExpressions[exprName] then
                        originalExpressions[exprName] = exprText.PlainText
                    end
                    
                    -- Get the action from the button ID
                    local action = nil
                    if id:match("^copy_") then action = "copy"
                    elseif id:match("^paste_") then action = "paste"
                    elseif id:match("^remove_") then action = "remove"
                    elseif id:match("^apply_") then action = "apply"
                    elseif id:match("^hide_") then action = "hide"
                    end
                    
                    if action then
                        -- Register handler based on action type
                        win.On[id] = {
                            Clicked = function(ev)
                                print("[ExpressionEditor Lua] BUTTON CLICKED:", id, "Action:", action, "Expression:", exprName)
                                
                                -- Find the expression text field
                                local exprTextID = "expr_" .. exprName
                                local exprText = win:Find(exprTextID)
                                
                                if action == "copy" and exprText then
                                    print("[ExpressionEditor Lua] Copying text to clipboard")
                                    pcall(function() bmd.setclipboard(exprText.PlainText) end)
                                    local statusBar = win:Find("statusBar")
                                    if statusBar then statusBar.Text = "Copied to clipboard" end
                                elseif action == "paste" and exprText then
                                    print("[ExpressionEditor Lua] Pasting from clipboard")
                                    local clipText = ""
                                    pcall(function() clipText = bmd.getclipboard() end)
                                    if clipText and #clipText > 0 then
                                        print("[ExpressionEditor Lua] Pasting text:", clipText)
                                        exprText.Text = clipText
                                        local statusBar = win:Find("statusBar")
                                        if statusBar then statusBar.Text = "Pasted from clipboard" end
                                        
                                        -- Update apply button since we modified the text
                                        local applyBtnID = "apply_" .. exprName
                                        local applyBtn = win:Find(applyBtnID)
                                        if applyBtn then
                                            applyBtn.StyleSheet = [[
                                                QPushButton {
                                                    background-color: rgba(60, 120, 60, 220);
                                                    color: white;
                                                    border: 0px solid transparent;
                                                    border-radius: 4px;
                                                    font-size: 11px;
                                                }
                                                QPushButton:hover {
                                                    background-color: rgba(80, 140, 80, 220);
                                                    color: rgb(255, 255, 255);
                                                }
                                                QPushButton:pressed {
                                                    background-color: rgba(40, 100, 40, 220);
                                                }
                                            ]]
                                        end
                                    end
                                elseif action == "remove" then
                                    print("[ExpressionEditor Lua] Removing expression")
                                    local originalName = nil
                                    for _, expr in ipairs(nodeExpressions) do
                                        local cName = expr.name:gsub("[^%w_]", "_")
                                        if cName == exprName then
                                            originalName = expr.name
                                            break
                                        end
                                    end
                                    if originalName then
                                        local success, result = pcall(function()
                                            comp:StartUndo("Remove Expression for " .. originalName)
                                            tool[originalName]:SetExpression()
                                            comp:EndUndo(true)
                                            return true
                                        end)
                                        local statusBar = win:Find("statusBar")
                                        if statusBar then
                                            statusBar.Text = success and "Expression removed" or "Failed to remove expression"
                                        end
                                        if success then
                                            if statusBar then statusBar.Text = "Expression removed. Refreshing..." end
                                            bmd.wait(0.2)
                                            refreshExpressions()
                                        end
                                    end
                                elseif action == "apply" and exprText then
                                    print("[ExpressionEditor Lua] Applying expression")
                                    if exprText.PlainText then
                                        local originalName = nil
                                        for _, expr in ipairs(nodeExpressions) do
                                            local cleanName = expr.name:gsub("[^%w_]", "_")
                                            if cleanName == exprName then
                                                originalName = expr.name
                                                break
                                            end
                                        end
                                        if originalName then
                                            local success, result = pcall(function()
                                                return updateExpression(originalName, exprText.PlainText)
                                            end)
                                            local statusBar = win:Find("statusBar")
                                            if statusBar then
                                                statusBar.Text = success and "Expression applied" or "Failed to apply expression"
                                            end
                                            if success then
                                                originalExpressions[exprName] = exprText.PlainText
                                                local applyBtn = win:Find(id)
                                                if applyBtn then
                                                    applyBtn.StyleSheet = [[
                                                        QPushButton {
                                                            background-color: rgba(80, 80, 80, 100);
                                                            color: rgb(150, 150, 150);
                                                            border-radius: 7px;
                                                            font-size: 11px;
                                                        }
                                                        QPushButton:disabled {
                                                            background-color: rgba(60, 60, 60, 100);
                                                            color: rgb(120, 120, 120);
                                                            border: 0px solid rgb(182, 192, 0);
                                                        }
                                                        QPushButton:hover {
                                                            background-color: rgba(60, 120, 60, 220);
                                                            color: rgb(255, 255, 255);
                                                        }
                                                        QPushButton:pressed {
                                                            background-color: rgba(90, 200, 90, 220);
                                                            color: rgb(200, 200, 200);
                                                        }
                                                    ]]
                                                end
                                            end
                                        else
                                            print("[ExpressionEditor Lua] Could not find original expression name")
                                        end
                                    end
                                elseif action == "hide" and exprText then
                                    print("[ExpressionEditor Lua] Toggling visibility")
                                    local hideBtn = win:Find(id)
                                    local exprGroup = win:Find("expressionGroup_" .. exprName)
                                    
                                    if hideBtn.Text == "Hide" then
                                        -- Currently visible, so hide it
                                        exprText:Hide()
                                        hideBtn.Text = "Show"
                                        -- Set the group's Weight to 0 to collapse it
                                        exprText.MinimumSize = {300, 0}
                                        exprText.MaximumSize = {16777215, 0}
                                        
                                        -- Update the parent group to reduce its space
                                        if exprGroup then
                                            exprGroup.MaximumSize = {16777215, ROW_CHROME_HEIGHT}
                                        end
                                    else
                                        -- Currently hidden, so show it
                                        hideBtn.Text = "Hide"
                                        
                                        -- Show the text edit and restore its size
                                        exprText:Show()
                                        exprText.MinimumSize = {300, 0}
                                        exprText.MaximumSize = {16777215, 16777215}
                                        
                                        -- Restore the original weight
                                        if exprGroup then
                                            exprGroup.MaximumSize = {16777215, 16777215}
                                        end
                                    end
                                    
                                    -- Force layout recalculation
                                    updateWindowSize()
                                end
                            end
                        }
                        print("[ExpressionEditor Lua] Registered handler for button:", id)
                    end
                end
            end
            
            -- Set up text change handlers for expressions
            if id:match("^expr_") then
                local exprName = id:match("^expr_(.+)$")
                if exprName then
                    win.On[id] = {
                        TextChanged = function(ev)
                            local exprText = win:Find(id)
                            local applyBtnID = "apply_" .. exprName
                            local applyBtn = win:Find(applyBtnID)
                            local charCountLabel = win:Find("charCount_" .. exprName)
                            
                            if exprText then
                                -- Only added newlines may redistribute field space.
                                adjustExpressionTextHeight(exprText, id)
                                -- Update character count
                                if charCountLabel then
                                    charCountLabel.Text = #exprText.PlainText .. " chars"
                                end
                            end
                            
                            if exprText and applyBtn and originalExpressions[exprName] then
                                -- Compare with original text
                                if exprText.PlainText ~= originalExpressions[exprName] then
                                    -- Text changed - highlight apply button
                                    applyBtn.StyleSheet = [[
                                        QPushButton {
                                            background-color: rgba(60, 120, 60, 220);
                                            color: white;
                                            border: 0px solid transparent;
                                            border-radius: 4px;
                                            font-size: 11px;
                                        }
                                        QPushButton:hover {
                                            background-color: rgba(80, 140, 80, 220);
                                            color: rgb(255, 255, 255);
                                        }
                                        QPushButton:pressed {
                                            background-color: rgba(90, 200, 90, 220);
                                            color: rgb(200, 200, 200);
                                        }
                                    ]]
                                end
                            end
                        end
                    }
                    print("[ExpressionEditor Lua] Registered TextChanged handler for:", id)
                end
            end
        end
    end
    
    print("[ExpressionEditor Lua] Set up handlers for", buttonCount, "buttons")
    return buttonCount > 0
end

-- Helper function to update pagination controls
function updatePaginationControls(currentIndex, totalPages)
    -- Always update our tracking variable
    currentPageIndex = currentIndex
    
    local humanPageNumber = currentIndex + 1 -- Convert from 0-based to 1-based for display
    
    print("[ExpressionEditor Lua] Updating pagination controls:", humanPageNumber, "of", totalPages)
    
    -- Update window title and info
    updateWindowTitle()
    
    -- Update page number label
    local pageLabel = win:Find("pageNumberLabel")
    if pageLabel then
        pageLabel.Text = "Page " .. humanPageNumber .. " of " .. totalPages
    end
    
    -- Update button states
    local prevButton = win:Find("prevPageButton")
    if prevButton then
        prevButton.Enabled = (currentIndex > 0)
        print("[ExpressionEditor Lua] Previous button enabled:", prevButton.Enabled)
    end
    
    local nextButton = win:Find("nextPageButton") 
    if nextButton then
        nextButton.Enabled = (currentIndex < totalPages - 1)
        print("[ExpressionEditor Lua] Next button enabled:", nextButton.Enabled)
    end
    
    -- Make sure only the current page is visible
    local stack = win:Find("expressionPagesStack")
    if stack then
        -- Try to get children with GetChildren method
        local children = nil
        pcall(function() 
            if type(stack.GetChildren) == "function" then
                children = stack:GetChildren()
            end
        end)
        
        if children then
            print("[ExpressionEditor Lua] Found", #children, "pages in updatePaginationControls")
            for i, child in ipairs(children) do
                local success = pcall(function() 
                    child.Visible = (i-1 == currentIndex)
                    print("[ExpressionEditor Lua] Setting page", i-1, "visibility to", (i-1 == currentIndex))
                end)
                
                if not success then
                    pcall(function()
                        if type(child.SetVisible) == "function" then
                            child:SetVisible(i-1 == currentIndex)
                        end
                    end)
                end
            end
        else
            print("[ExpressionEditor Lua] No children found in updatePaginationControls")
        end
    end
    
    -- Force a layout update
    win:RecalcLayout()
    
    return true
end

-- Function to update font size for all text editors
function updateFontSize(newSize)
    -- Update the font size
    currentFontSize = newSize
    
    -- Update all text editors
    for _, expr in ipairs(nodeExpressions) do
        -- Clean the name for IDs
        local cleanName = expr.name:gsub("[^%w_]", "_")
        
        local textEdit = win:Find("expr_" .. cleanName)
        if textEdit then
            -- Safety check for StyleSheet property
            local success, error = pcall(function()
                textEdit.StyleSheet = string.format([[
                    QTextEdit {
                            background-color: rgba(25, 25, 25, 220);
                            color: rgb(200, 200, 200);
                            border: none;
                            border-radius: 2px;
                            padding: 5px;
                            font-family: Droid Sans Mono;
                            font-size: %dpx;
                            selection-background-color: #4376A1;
                        }
                    QTextEdit:focus {
                        border: 1px solid rgb(60, 120, 60);
                    }
                ]], currentFontSize)
            end)
            
            if not success then
                iprint("[ExpressionEditor Lua] Error updating font size for", expr.name, ":", error)
            end
        end
    end
    
    -- Update status bar
    local statusBar = win:Find('statusBar')
    if statusBar then
        statusBar.Text = "Font size changed to " .. currentFontSize
    end
    
    updateWindowSize()
end

-- Function to refresh expressions from the currently selected node
function refreshExpressions()
    -- Get the currently active tool
    local currentTool = comp.ActiveTool
    if not currentTool then 
        local statusBar = win and win:Find('statusBar')
        if statusBar then
            statusBar.Text = "No active tool selected"
        end
        return 
    end
    
    -- Update tool reference and title
    tool = currentTool
    toolName = tool:GetAttrs()['TOOLS_Name']
    
    -- Get expressions from new tool
    nodeExpressions = getNodeExpressions(tool)
    
    -- Reset original expressions to match what's currently on the node
    -- This ensures removed expressions aren't kept in memory
    originalExpressions = {}
    for _, expr in ipairs(nodeExpressions) do
        local cleanName = expr.name:gsub("[^%w_]", "_")
        originalExpressions[cleanName] = expr.expression
    end
    
    -- Store window geometry before closing
    local winX, winY, winWidth, winHeight = 0, 0, 800, 600
    pcall(function() 
        local geometry = win:GetGeometry()
        if geometry then
            -- Try different possible formats
            if type(geometry) == "table" then
                -- It might be a table with x,y,width,height properties
                if geometry.x and geometry.y and geometry.width and geometry.height then
                    winX, winY = geometry.x, geometry.y
                    winWidth, winHeight = geometry.width, geometry.height
                -- Or it might be a table with numeric indices
                elseif geometry[1] and geometry[2] and geometry[3] and geometry[4] then
                    winX, winY = geometry[1], geometry[2]
                    winWidth, winHeight = geometry[3], geometry[4]
                end
            end
        end
    end)
    
    print("[ExpressionEditor Lua] Stored window position:", winX, winY, winWidth, winHeight)
    
    -- Hide the old window (don't immediately destroy it)
    if win then
        win:Hide()
    end
    
    -- Create a new window without showing it
    win = createExpressionEditorWindow()
    
    -- Restore position and size before showing
    pcall(function() win:Move({winX, winY}) end)
    pcall(function()
        adjustWidgetsToWindowSize(math.min(winWidth, maxWidth), math.min(winHeight, maxHeight))
        win:Resize({math.min(winWidth, maxWidth), math.min(winHeight, maxHeight)})
        clampWindowPosition()
    end)
    
    -- Update the window title
    win:SetWindowTitle('Expression Editor - ' .. toolName)
    
    -- Force layout calculation
    win:RecalcLayout()
    
    -- Now show the window after it's positioned and sized
    win:Show()
    
    -- Update status bar to confirm refresh
    local statusBar = win:Find('statusBar')
    if statusBar then
        statusBar.Text = "Expression list refreshed"
    end
    
    print("[ExpressionEditor Lua] Expression list refreshed successfully")
    return true
end

-- Function to update an expression on the tool
function updateExpression(name, expression)
    print("[ExpressionEditor Lua] Updating expression for:", name, "to", expression)
    
    if not expression or expression == "" then
        iprint("[ExpressionEditor Lua] Warning: Empty expression, update cancelled")
        return false
    end
    
    -- Start an undo event
    comp:StartUndo("Change Expression for " .. name)
    
    local success, err = pcall(function()
        -- Use SetExpression to set the expression on the input
        print("[ExpressionEditor Lua] Setting expression on input:", name)
        print("[ExpressionEditor Lua] New expression value:", expression)
        tool[name]:SetExpression(expression)
        print("[ExpressionEditor Lua] Expression set successfully")
        
        -- Mark that expressions have been modified
        expressionsModified = true
    end)
    
    -- End the undo event
    comp:EndUndo(true)
    
    if not success then
        iprint("[ExpressionEditor Lua] Error updating expression:", err)
        return false
    end
    
    print("[ExpressionEditor Lua] Expression updated successfully")
    return true
end

-- Function to update window title and page info
function updateWindowTitle()
    local titleLabel = win:Find("windowTitleLabel")
    if titleLabel then
        titleLabel.Text = "<b>" .. attrs['TOOLS_Name'] .. "  (Page <b>" .. (currentPageIndex + 1) .. "/" .. totalPages .. " |  <b>" .. #nodeExpressions .. "</b> expressions"
    end
    
    -- Also update pagination button text
    local prevButton = win:Find("prevPageButton")
    if prevButton then
        prevButton.Text = "◀ Page " .. currentPageIndex
    end
    
    local nextButton = win:Find("nextPageButton")
    if nextButton then
        nextButton.Text = "Page " .. (currentPageIndex + 2) .. " ▶"
    end
end

-- Function to calculate text height based on content
function calculateTextHeight(text, width)
    local safeText = text or ""
    
    -- Count the number of lines (count newlines + 1)
    local lineCount = 0
    local charsPerLine = width and math.max(1, math.floor((width - 30) / (currentFontSize * 0.65)))
    for line in (safeText .. "\n"):gmatch("(.-)\n") do
        lineCount = lineCount + (charsPerLine and math.max(1, math.ceil(#line / charsPerLine)) or 1)
    end
    
    -- Keep a two-line floor for tiny expressions without adding an empty line
    -- to every long field. Padding must not accumulate with content length.
    lineCount = math.max(2, lineCount)
    
    -- Calculate height: base line height (based on font size) * lines + padding
    local lineHeight = math.ceil(currentFontSize * 1.15)
    local paddingHeight = 10
    local height = (lineHeight * lineCount) + paddingHeight
    return height, lineCount, lineHeight, paddingHeight
end

function buildExpressionPages(expressions, width, height)
    local pages = {}
    local budget = math.max(1, height - WINDOW_CHROME_HEIGHT)
    local used, count = 0, 0
    for i, expression in ipairs(expressions) do
        local needed = ROW_CHROME_HEIGHT + math.min(calculateTextHeight(expression.expression, width),
            math.max(1, budget - ROW_CHROME_HEIGHT))
        if count == 0 or used + needed > budget or count >= 15 then
            table.insert(pages, {first=i, last=i})
            used, count = 0, 0
        end
        pages[#pages].last = i
        used, count = used + needed, count + 1
    end
    if #pages == 0 then pages[1] = {first=1, last=0} end
    return pages
end

-- Weight is consumed when Fusion creates the layout item; assigning .Weight
-- afterward has no effect. Preserve long/medium content ratios at creation;
-- the small editor minima keep short fields usable without capping this ratio.
function expressionLayoutWeight(text, width)
    return math.max(1, calculateTextHeight(text, width) / 45)
end

-- Keep edit tracking outside the UI controls: Fusion widgets do not support
-- arbitrary custom properties. A refreshed window initializes these again.
local editorNewlineCounts = {}

-- Function to calculate and set appropriate height for expression text fields
function adjustExpressionTextHeight(textEdit, editorID)
    if not textEdit then return end
    local key = editorID or textEdit.ID or textEdit
    local _, newlineCount = (textEdit.PlainText or ""):gsub("\n", "")
    local previousCount = editorNewlineCounts[key]
    editorNewlineCounts[key] = newlineCount
    if buildingWindow then layoutLineCounts[key] = newlineCount + 1 end
    if not buildingWindow then
        if previousCount and newlineCount ~= previousCount and not layoutBusy then
            local g = win:GetGeometry()
            -- Use the existing window budget. Never call Resize or Move here.
            adjustWidgetsToWindowSize(g.width or g[3], g.height or g[4], true)
        end
        return
    end
    
    -- Small minima let the native layout shrink and stretch without scripts.
    local minimum = math.min(calculateTextHeight(""), getMaxExpressionHeight())
    textEdit.MinimumSize = {300, textEdit.Hidden and 0 or minimum}
    textEdit.MaximumSize = {16777215, textEdit.Hidden and 0 or 16777215}

end

-- Function to calculate window size based on content (moved before it's called)
function clampWindowPosition(x, y)
    if not win then return end
    local g = win:GetGeometry()
    local w, h = g.width or g[3], g.height or g[4]
    x, y = x or g.x or g[1], y or g.y or g[2]
    win:Move({math.max(screen.x + 8, math.min(x, screen.x + screen.width - w - 8)),
        math.max(screen.y + 32, math.min(y, screen.y + screen.height - h - 40))})
end

-- Use model indices rather than GetChildren/GetItems: groups and stacks are
-- not consistently enumerated across Fusion versions. Include hidden pages.
local function visitEditorPages(callback)
    for page = 1, totalPages do
        local editors, ids = {}, {}
        for i = expressionPageRanges[page].first, expressionPageRanges[page].last do
            local id = "expr_" .. nodeExpressions[i].name:gsub("[^%w_]", "_")
            local editor = win:Find(id)
            if editor then
                table.insert(editors, editor)
                table.insert(ids, id)
            end
        end
        callback(editors, page - 1, ids)
    end
end

function updateWindowSize()
    if not win or buildingWindow or layoutBusy then return end
    local g = win:GetGeometry()
    local width = math.min(g.width or g[3] or 800, maxWidth)
    local height = math.min(250, maxHeight)
    visitEditorPages(function(editors, pageIndex)
        if pageIndex ~= currentPageIndex then return end
        local pageHeight = WINDOW_CHROME_HEIGHT + #editors * ROW_CHROME_HEIGHT
        for _, editor in ipairs(editors) do
            if not editor.Hidden then
                pageHeight = pageHeight + calculateTextHeight(editor.PlainText, width - 40)
            end
        end
        height = math.max(height, pageHeight)
    end)
    if height > 600 then height = maxHeight end
    height = math.min(height, maxHeight)
    adjustWidgetsToWindowSize(width, height)
    layoutBusy = true
    win:Resize({width, height})
    layoutBusy = false
    clampWindowPosition()
end

-- Process at most one allocation after a batch of native resize events.
-- Fusion does not deliver arbitrary custom QueueEvent names reliably.
function flushPendingLayout()
    if not layoutQueued or buildingWindow or layoutBusy then return end
    layoutQueued = false
    local g = win:GetGeometry()
    adjustWidgetsToWindowSize(g.width or g[3], g.height or g[4])
end

function runEditorLoop()
    editorLoopRunning = true
    while editorLoopRunning do
        local ev = ui:GetEvent(true)
        while ev do
            disp:Dispatch(ev)
            ev = ui:GetEvent(false)
        end
        if editorLoopRunning then flushPendingLayout() end
    end
end

-- One fair allocation for opening, newline edits, and manual resizing.
-- Equal explicit line counts receive equal heights, independent of edit order.
function adjustWidgetsToWindowSize(width, height, lineCountChanged)
    if not win or buildingWindow or layoutBusy then return end
    layoutBusy = true
    local changed = false
    visitEditorPages(function(editors, pageIndex, ids)
        local count, totalWeight = 0, 0
        local weights = {}
        for i, editor in ipairs(editors) do
            local id = ids[i]
            if lineCountChanged or not layoutLineCounts[id] then
                local _, lines = (editor.PlainText or ''):gsub('\n', '')
                layoutLineCounts[id] = lines + 1
            end
            weights[i] = editor.Hidden and 0 or layoutLineCounts[id]
            totalWeight = totalWeight + weights[i]
            if not editor.Hidden then count = count + 1 end
        end
        local available = math.max(0, math.floor(height - WINDOW_CHROME_HEIGHT - #editors * ROW_CHROME_HEIGHT))
        local minimum = math.min(calculateTextHeight(''), math.floor(available / math.max(1, count)))
        local remaining = math.max(0, available - minimum * count)
        local allocations, fractions, used = {}, {}, 0
        for i, editor in ipairs(editors) do
            local exact = totalWeight > 0 and remaining * weights[i] / totalWeight or 0
            allocations[i] = editor.Hidden and 0 or minimum + math.floor(exact)
            fractions[i] = {index=i, value=editor.Hidden and -1 or exact-math.floor(exact)}
            used = used + allocations[i]
        end
        table.sort(fractions, function(a,b)
            if a.value == b.value then return a.index < b.index end
            return a.value > b.value
        end)
        for i=1,math.min(count, available-used) do
            local index=fractions[i].index
            allocations[index]=allocations[index]+1
        end
        for i,editor in ipairs(editors) do
            local oldMin,oldMax=editor.MinimumSize,editor.MaximumSize
            local wantedMin=editor.Hidden and 0 or minimum
            if not oldMin or (oldMin[2] or oldMin.y)~=wantedMin then
                editor.MinimumSize={300,wantedMin}
                changed=true
            end
            if not oldMax or (oldMax[2] or oldMax.y)~=allocations[i] then
                editor.MaximumSize={16777215,allocations[i]}
                changed=true
            end
            -- Bound the row too: its original construction weight must not
            -- reserve extra blank space after the editor reaches its allocation.
            local group=win:Find('expressionGroup_'..ids[i]:sub(6))
            if group then
                local rowMaximum=allocations[i]+ROW_CHROME_HEIGHT-10
                local old=group.MaximumSize
                if not old or (old[2] or old.y)~=rowMaximum then
                    group.MaximumSize={16777215,rowMaximum}
                    changed=true
                end
            end
        end
    end)
    if changed then win:RecalcLayout() end
    layoutBusy = false
end

-- Function to remove an expression from the tool
function removeExpression(name)
    print("[ExpressionEditor Lua] Removing expression for:", name)
    
    -- Start an undo event
    comp:StartUndo("Remove Expression for " .. name)
    
    local success, err = pcall(function()
        -- Call SetExpression without arguments to remove the expression
        print("[ExpressionEditor Lua] Removing expression from input:", name)
        tool[name]:SetExpression()
        print("[ExpressionEditor Lua] Expression removed successfully")
        
        -- Mark that expressions have been modified
        expressionsModified = true
    end)
    
    -- End the undo event
    comp:EndUndo(true)
    
    if not success then
        iprint("[ExpressionEditor Lua] Error removing expression:", err)
        return false
    end
    
    print("[ExpressionEditor Lua] Expression removed successfully")
    return true
end

-- Create and show the expression editor window using our QStackedWidget solution
print("[ExpressionEditor Lua] Creating expression editor window")
win = createExpressionEditorWindow()

-- Add ActionListener configuration to handle system shortcuts like Ctrl+W and Ctrl+F4
local configID = 'ExpressionEditor_' .. windowID
app:AddConfig(configID, {
    Target {
        ID = windowID,
    },

    Hotkeys {
        Target = windowID,
        Defaults = true,
        
        CONTROL_W = 'Execute{cmd = [[app.UIManager:QueueEvent(obj, "Close", {})]]}',
        CONTROL_F4 = 'Execute{cmd = [[app.UIManager:QueueEvent(obj, "Close", {})]]}',
        ESCAPE = 'Execute{cmd = [[app.UIManager:QueueEvent(obj, "Close", {})]]}',
    },
})

-- Info button
win.On.infoButton = {
    Clicked = function(ev)
        showInfoDialog()
    end
}

-- Function to show information dialog
function showInfoDialog()
    print("[ExpressionEditor Lua] Showing information dialog")
    
    -- Create a simple info window without using a separate dispatcher
    local infoWindowID = "InfoDialog_" .. os.time()
    ownedWindowIDs[infoWindowID] = true
    local infoWin = disp:AddWindow({
        ID = infoWindowID,
        WindowTitle = "Expression Editor Information",
        Geometry = {100, 100, 500, 500},
        WindowFlags = {
            Popup = true,
            Dialog = true,
            WindowStaysOnTopHint = true,
        },
        
        ui:VGroup{
            ID = "infoRoot",
            Spacing = 5,
            Margins = {5, 5, 5, 5},
            StyleSheet = [[
                QWidget {
                    background-color: rgba(30, 30, 30, 180);
                    border-radius: 7px;
                }
            ]],
            
            -- Scrollable text area with info content
            ui:TextEdit{
                ID = "infoText",
                ReadOnly = true,
                HTML = [[
                    <h2 style="color:#ccb;">Expression Editor</h2>
                    <p style="color:#ccc;">Version ]] .. VERSION .. [[</p>
                    
                    <h3 style="color:#cca;">Tips &amp; Shortcuts</h3>
                    <ul style="color:#ccc;">
                        <li><b>Ctrl+W or Escape or Ctrl+F4</b> - Close the window</li>
                    </ul>
                    
                    <h3 style="color:#cca;">Features</h3>
                    <ul style="color:#ccc;">
                        <li>Syntax highlighting for Fusion expressions</li>
                        <li>Dynamic pagination</li>
                        <li>Automatic text field height adjustment</li>
                        <li>Adjustable font size</li>
                    </ul>
                    
                    <h3 style="color:#cca;">Credits</h3>
                    <ul style="color:#ccc;">
                        <li>Created based on UI manager examples by Andrew Hazelden &lt;andrew@andrewhazelden.com&gt;</li>
                        <li>UI designed by @JustCropIt</li>
                        <li>Created by Dominik Bargiel &lt;dominikbargiel97@gmail.com&gt;</li>
                    </ul>
                ]],
                StyleSheet = [[
                    QTextEdit {
                        background-color: rgba(25, 25, 25, 220);
                        color: rgb(200, 200, 200);
                        border: 1px solid rgb(60, 60, 60);
                        border-radius: 2px;
                        padding: 4px;
                        font-family: Segoe UI, Arial;
                        font-size: 12px;
                        selection-background-color: #4376A1;
                    }
                ]],
            },
            
            -- Add clickable links and close button in a single HGroup
            ui:HGroup{
                ID = "linksAndCloseGroup",
                Weight = 0,
                Spacing = 2,
                
                -- Link to WSL thread
                ui:Label{
                    ID = "urlWSL",
                    Text = '<a style="color: rgb(139,155,216)" href="https://www.steakunderwater.com/wesuckless/viewtopic.php?p=55538#p55538">Development thread</a>',
                    WordWrap = false,
                    OpenExternalLinks = true,
                    StyleSheet = [[
                        QLabel {
                            background-color: transparent;
                            font-size: 12px;
                            padding: 1px;
                        }
                    ]],
                },
                
                -- Link to Instagram
                ui:Label{
                    ID = "urlInstagram",
                    Text = '<a style="color: rgb(139,155,216)" href="https://www.instagram.com/imitate.echo/">Instagram</a>',
                    WordWrap = false,
                    OpenExternalLinks = true,
                    StyleSheet = [[
                        QLabel {
                            background-color: transparent;
                            font-size: 12px;
                            padding: 1px;
                        }
                    ]],
                },
                
                -- Flexible space to push the close button to the right
                ui:HGap(0, 1.0),
                
                -- Close button
                ui:Button{
                    ID = "infoCloseButton",
                    Text = "Close",
                    MinimumSize = {50, 22},
                    MaximumSize = {50, 22},
                    StyleSheet = [[
                        QPushButton {
                            background-color: rgba(40, 100, 40, 0);
                            color: rgb(200, 200, 200);
                            border: 1px solid rgb(170, 170, 170);
                            border-radius: 7px;
                            font-size: 11px;
                        }
                        QPushButton:hover {
                            background-color: rgba(120, 120, 120, 200);
                            color: rgb(255, 255, 255);
                        }
                        QPushButton:pressed {
                            background-color: rgba(180, 180, 180, 220);
                        }
                    ]],
                },
            },
        },
    })
    
    -- Simple event handlers
    function infoWin.On.infoCloseButton.Clicked(ev)
        infoWin:Hide()
    end
    
    function infoWin.On.Close(ev)
        infoWin:Hide()
    end

    -- Show the info window
    infoWin:Show()
    
    -- Try to center the info window over the main window
    pcall(function()
        local mainGeom = win:GetGeometry()
        local infoGeom = infoWin:GetGeometry()
        
        if mainGeom and infoGeom then
            local centerX = mainGeom.x + (mainGeom.width - infoGeom.width) / 2
            local centerY = mainGeom.y + (mainGeom.height - infoGeom.height) / 2
            
            infoWin:Move({centerX, centerY})
        end
    end)
    
    return true
end

-- Keep the window updating until the script is quit
runEditorLoop()

-- When the window is closed, clean up the ActionListener config
app:RemoveConfig(configID)
collectgarbage()
