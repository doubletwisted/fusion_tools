-- Import the UI library
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)

-- Function to create a BetterResize node with KeepAspect option
function createResizeNode(comp, source, width, height, x, y)
    local resize = comp:AddTool("BetterResize", x, y)
    resize.Width = width
    resize.Height = height
    resize.KeepAspect = 1
    resize.HiQOnly = 0
    resize.PixelAspect = {1, 1}
    resize.Input = source.Output
    if markGeneratedTool then
        markGeneratedTool(resize)
    end
    return resize
end

-- Function to create a background of appropriate size
function createBackgroundNode(comp, width, height, x, y)
    local background = comp:AddTool("Background", x, y)
    background.Width = width
    background.Height = height
    if markGeneratedTool then
        markGeneratedTool(background)
    end
    return background
end

-- Function to create a TextPlus node displaying only the file name
function createTextPlusNode(comp, loader, x, y, tileWidth, tileHeight, textColor)
    local fullFilename = getLoaderClipPath(loader)
    -- Extract only the filename from the full path
    local filename = string.match(fullFilename, "([^\\/]*)$")
    local textPlus = comp:AddTool("TextPlus", x, y)
    textPlus.Width = tileWidth
    textPlus.Height = tileHeight
    textPlus.Depth = 1
    textPlus.Center = {0.5, 0.01}
    textPlus:SetInput("StyledText", filename) -- Set the filename without path
    textPlus.Font = "Open Sans"
    textPlus.Style = "Bold"
    textPlus.Size = 0.0373
    textPlus.VerticalTopCenterBottom = 1
    textPlus.VerticalJustificationNew = 3
    textPlus.HorizontalJustificationNew = 3
    
    -- Set the text color
    textPlus.Red1 = textColor[1]
    textPlus.Green1 = textColor[2]
    textPlus.Blue1 = textColor[3]
    textPlus.Alpha1 = textColor[4]
    if markGeneratedTool then
        markGeneratedTool(textPlus)
    end
    
    return textPlus
end


-- Function to create a Merge node with specific settings
function createTextMergeNode(comp, background, foreground, x, y)
    local merge = comp:AddTool("Merge", x, y)
    merge.Background = background.Output
    merge.Foreground = foreground.Output
    merge.PerformDepthMerge = 0
    if markGeneratedTool then
        markGeneratedTool(merge)
    end
    return merge
end

-- Function to arrange layers in a grid by merge nodes.
function createImagesMergeNodes(comp, sources, rows, cols, background, x, y, hSpacing, vSpacing, tileWidth, tileHeight)
    local idx = 1
    local mergedimages = {}
    
    -- Calculate total dimensions including spacing
    local totalWidth = background.Width[fu.TIME_UNDEFINED]
    local totalHeight = background.Height[fu.TIME_UNDEFINED]
    
    -- Calculate cell dimensions including spacing
    local cellWidth = tileWidth / totalWidth
    local cellHeight = tileHeight / totalHeight
    
    -- Calculate spacing as a fraction of the total size
    local hSpacingNorm = hSpacing / totalWidth
    local vSpacingNorm = vSpacing / totalHeight
    
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            if idx <= #sources then
                local merge = comp:AddTool("Merge", x + idx, y)
                table.insert(mergedimages, merge)
                if markGeneratedTool then
                    markGeneratedTool(merge)
                end
                
                -- Calculate center position with spacing
                local centerX = (col * (cellWidth + hSpacingNorm))
                centerX = centerX + (cellWidth / 2)
                
                local centerY = 1 - ((row * (cellHeight + vSpacingNorm)) + (cellHeight / 2))
                
                -- Adjust for edge cases
                centerX = math.min(math.max(centerX, 0), 1)
                centerY = math.min(math.max(centerY, 0), 1)
                
                if idx == 1 then
                    merge.Background = background.Output
                else 
                    merge.Background = mergedimages[idx-1].Output
                end

                merge.Foreground = sources[idx].Output
                merge.Center = {centerX, centerY}

                idx = idx + 1
            end
        end
    end
    return mergedimages[#mergedimages]
end

local GENERATED_DATA_KEY = "CreateGridCollage.Generated"
local GENERATED_SOURCE_KEY = "CreateGridCollage.SourceLoader"

function getToolAttrs(tool)
    local attrs = nil
    pcall(function()
        attrs = tool:GetAttrs()
    end)
    return attrs or {}
end

function getToolName(tool)
    return getToolAttrs(tool).TOOLS_Name or "Tool"
end

function getLoaderClipPath(loader)
    local clipPath = ""
    pcall(function()
        clipPath = tostring(loader.Clip[fu.TIME_UNDEFINED] or "")
    end)
    return clipPath
end

function getLoaderSortName(loader)
    local clipPath = getLoaderClipPath(loader)
    return string.match(clipPath, "([^\\/%s]+)%.%w+$") or clipPath
end

function markGeneratedTool(tool, sourceName)
    if not tool then
        return
    end
    pcall(function()
        tool:SetData(GENERATED_DATA_KEY, true)
    end)
    if sourceName then
        pcall(function()
            tool:SetData(GENERATED_SOURCE_KEY, sourceName)
        end)
    end
end

function isGeneratedTool(tool)
    local generated = false
    pcall(function()
        local value = tool:GetData(GENERATED_DATA_KEY)
        generated = value == true or value == "true" or value == 1
    end)
    return generated
end

function filterOriginalLoaders(loaderNodes)
    local filtered = {}
    for _, loader in ipairs(loaderNodes or {}) do
        if not isGeneratedTool(loader) then
            table.insert(filtered, loader)
        end
    end
    return filtered
end

function getTargetLoaders(comp)
    local selectedLoaders = filterOriginalLoaders(comp:GetToolList(true, "Loader"))
    return selectedLoaders, "selected originals"
end

function getLoaderInfoText(count, scope)
    local label = "loader nodes"
    if count == 1 then
        label = "loader node"
    end
    return string.format("%d %s targeted (%s)", count, label, scope)
end

function calculateDefaultGrid(numLoaders)
    local defaultRows = 1
    local defaultCols = math.max(numLoaders, 1)

    if numLoaders >= 6 and numLoaders < 12 then
        defaultRows = 2
        defaultCols = math.ceil(numLoaders / 2)
    elseif numLoaders >= 12 and numLoaders < 20 then
        defaultRows = 3
        defaultCols = math.ceil(numLoaders / 3)
    elseif numLoaders >= 20 then
        defaultRows = 4
        defaultCols = math.ceil(numLoaders / 4)
    end

    return defaultRows, defaultCols
end

function getAdjustedGrid(rows, cols, sourceCount)
    rows = math.max(tonumber(rows) or 1, 1)
    cols = math.max(tonumber(cols) or 1, 1)

    if sourceCount > 0 and rows * cols < sourceCount then
        cols = math.ceil(sourceCount / rows)
    end

    return rows, cols
end

function getAspectRatioBounds(loaders)
    local minAspectRatio = nil
    local maxAspectRatio = nil
    for _, loader in ipairs(loaders) do
        local img = nil
        pcall(function()
            img = loader.Output:GetValue()
        end)
        if img then
            local imageWidth = img.Width
            local imageHeight = img.Height
            if imageWidth and imageHeight and imageHeight > 0 then
                local aspectRatio = imageWidth / imageHeight
                minAspectRatio = minAspectRatio and math.min(minAspectRatio, aspectRatio) or aspectRatio
                maxAspectRatio = maxAspectRatio and math.max(maxAspectRatio, aspectRatio) or aspectRatio
            end
        end
    end
    return minAspectRatio or 0, maxAspectRatio or 0
end

function calculateTileHeight(loaders, tileWidth)
    local _, maxAspectRatio = getAspectRatioBounds(loaders)

    if maxAspectRatio > 0 then
        return math.floor(tileWidth / maxAspectRatio)
    end

    return nil
end

function getLoaderAspectRatio(loader)
    local aspectRatio = nil
    pcall(function()
        local img = loader.Output:GetValue()
        if img and img.Width and img.Height and img.Height > 0 then
            aspectRatio = img.Width / img.Height
        end
    end)
    return aspectRatio
end

function getImageResizeDimensions(loader, tileWidth, tileHeight, fitTallImages)
    if fitTallImages then
        local aspectRatio = getLoaderAspectRatio(loader)
        local tileAspectRatio = tileWidth / tileHeight
        if aspectRatio and aspectRatio < tileAspectRatio then
            return math.max(math.floor((tileHeight * aspectRatio) + 0.5), 1), tileHeight
        end
    end

    return tileWidth, tileHeight
end

function sortLoaders(loaderNodes, sortOrder)
    local sortableNodes = {}
    for i = 1, #loaderNodes do
        sortableNodes[i] = loaderNodes[i]
    end

    if sortOrder == 1 then  -- Alphabetical
        print("Sorting alphabetically...")
        table.sort(sortableNodes, function(a, b)
            local nameA = getLoaderSortName(a)
            local nameB = getLoaderSortName(b)
            print("Comparing files: " .. nameA .. " with " .. nameB)
            return string.lower(nameA) < string.lower(nameB)
        end)
    elseif sortOrder == 2 then  -- Reverse Alphabetical
        print("Sorting reverse alphabetically...")
        table.sort(sortableNodes, function(a, b)
            local nameA = getLoaderSortName(a)
            local nameB = getLoaderSortName(b)
            print("Comparing files: " .. nameA .. " with " .. nameB)
            return string.lower(nameA) > string.lower(nameB)
        end)
    end

    return sortableNodes
end

function printLoaderOrder(loaders)
    print("\nFinal order after sorting:")
    for i, node in ipairs(loaders) do
        print(i .. ": " .. getLoaderSortName(node))
    end
end

function getAllTools(comp)
    local allTools = nil
    pcall(function()
        allTools = comp:GetToolList(false)
    end)
    if allTools then
        return allTools
    end
    return comp:GetToolList(false, "Loader")
end

function getFlowBounds(comp)
    local flow = comp.CurrentFrame.FlowView
    local minX, minY, maxX, maxY = nil, nil, nil, nil

    for _, tool in pairs(getAllTools(comp) or {}) do
        local ok, x, y = pcall(function()
            return flow:GetPos(tool)
        end)
        if ok and x and y then
            minX = minX and math.min(minX, x) or x
            minY = minY and math.min(minY, y) or y
            maxX = maxX and math.max(maxX, x) or x
            maxY = maxY and math.max(maxY, y) or y
        end
    end

    return {
        minX = minX or 0,
        minY = minY or 0,
        maxX = maxX or 0,
        maxY = maxY or 0
    }
end

function copyLoaderNode(comp, loader, x, y)
    local flow = comp.CurrentFrame.FlowView
    local copiedLoader = nil
    local sourceName = getToolName(loader)

    local ok, err = pcall(function()
        flow:Select()
        comp:Copy(loader)
        comp:Paste()
        copiedLoader = comp.ActiveTool
    end)

    if not ok or not copiedLoader then
        print("Failed to copy Loader " .. sourceName .. ": " .. tostring(err))
        return nil
    end

    flow:SetPos(copiedLoader, x, y)
    markGeneratedTool(copiedLoader, sourceName)
    return copiedLoader
end

function createCurrentLayout(comp, loaders, gridRows, gridCols, tileWidth, tileHeight, showNames, hSpacing, vSpacing, textColor, fitTallImages)
    local positions = {}
    for _, loader in ipairs(loaders) do
        local x, y = comp.CurrentFrame.FlowView:GetPos(loader)
        table.insert(positions, {x = x, y = y})
    end

    local totalWidth = (gridCols * tileWidth) + (hSpacing * (gridCols - 1))
    local totalHeight = (gridRows * tileHeight) + (vSpacing * (gridRows - 1))
    local bgpos = positions[1]
    local background = createBackgroundNode(comp, math.floor(totalWidth + 0.5), math.floor(totalHeight + 0.5), bgpos.x - 3, bgpos.y + 3)

    local mergedNodes = {}
    for i, loader in ipairs(loaders) do
        local pos = positions[i]
        local resizeX = pos.x + 0.5
        local mergeX = pos.x + 2
        local resizeWidth, resizeHeight = getImageResizeDimensions(loader, tileWidth, tileHeight, fitTallImages)
        local resize = createResizeNode(comp, loader, resizeWidth, resizeHeight, resizeX, pos.y + 2)

        if showNames then
            local textPlus = createTextPlusNode(comp, loader, mergeX, pos.y, tileWidth, tileHeight, textColor)
            local merge = createTextMergeNode(comp, resize, textPlus, mergeX, pos.y + 2)
            table.insert(mergedNodes, merge)
        else
            table.insert(mergedNodes, resize)
        end
    end

    local pos = positions[1]
    return createImagesMergeNodes(comp, mergedNodes, gridRows, gridCols, background,
        pos.x - 1, pos.y + 4, hSpacing, vSpacing, tileWidth, tileHeight)
end

function createReferenceLayout(comp, loaders, gridRows, gridCols, tileWidth, tileHeight, showNames, hSpacing, vSpacing, textColor, fitTallImages)
    local bounds = getFlowBounds(comp)
    local anchorX = bounds.maxX + 25
    local anchorY = bounds.minY + 25
    local branchXSpacing = showNames and 5 or 3
    local branchYSpacing = showNames and 5 or 4
    local mergedNodes = {}

    for i, loader in ipairs(loaders) do
        local row = math.floor((i - 1) / gridCols)
        local col = (i - 1) % gridCols
        local baseX = anchorX + (col * branchXSpacing)
        local baseY = anchorY + (row * branchYSpacing)
        local copiedLoader = copyLoaderNode(comp, loader, baseX, baseY)

        if not copiedLoader then
            return nil, "Could not copy Loader " .. getToolName(loader)
        end

        local resizeX = baseX
        local mergeX = baseX + 2
        local resizeWidth, resizeHeight = getImageResizeDimensions(copiedLoader, tileWidth, tileHeight, fitTallImages)
        local resize = createResizeNode(comp, copiedLoader, resizeWidth, resizeHeight, resizeX, baseY + 2)

        if showNames then
            local textPlus = createTextPlusNode(comp, copiedLoader, mergeX, baseY, tileWidth, tileHeight, textColor)
            local merge = createTextMergeNode(comp, resize, textPlus, mergeX, baseY + 2)
            table.insert(mergedNodes, merge)
        else
            table.insert(mergedNodes, resize)
        end
    end

    local totalWidth = (gridCols * tileWidth) + (hSpacing * (gridCols - 1))
    local totalHeight = (gridRows * tileHeight) + (vSpacing * (gridRows - 1))
    local mergeY = anchorY + (gridRows * branchYSpacing) + 2
    local background = createBackgroundNode(comp, math.floor(totalWidth + 0.5), math.floor(totalHeight + 0.5), anchorX - 2, mergeY)

    return createImagesMergeNodes(comp, mergedNodes, gridRows, gridCols, background,
        anchorX, mergeY, hSpacing, vSpacing, tileWidth, tileHeight)
end


-- Create the user interface dialog
function createDialog()
    local comp = fu:GetCurrentComp()
    local loaderNodes, loaderScope = getTargetLoaders(comp)
    local numLoaders = #loaderNodes
    local defaultRows, defaultCols = calculateDefaultGrid(numLoaders)
    
    -- Create the dialog
    local dlg = disp:AddWindow({
        ID = "TileGridDialog",
        WindowTitle = "Tile and Grid Settings",
        Geometry = {100, 100, 430, 530},
        ui:VGroup{
            ID = "root",
            ui:VGap(10),
            ui:Label{ID = "selectedNodesInfo", Text = getLoaderInfoText(numLoaders, loaderScope)},
            ui:Label{ID = "labelTileWidth", Text = "Enter tile width:"},
            ui:LineEdit{ID = "tileWidth", Text = "500"},
            ui:Label{ID = "labelGridRows", Text = "Enter number of grid rows:"},
            ui:LineEdit{ID = "gridRows", Text = tostring(defaultRows)},
            ui:Label{ID = "labelGridCols", Text = "Enter number of grid columns:"},
            ui:LineEdit{ID = "gridCols", Text = tostring(defaultCols)},
            ui:VGap(5),
            ui:HGroup{
                ui:Label{Text = "Spacing:", Weight = 0.3},
                ui:VGroup{
                    Weight = 0.7,
                    ui:HGroup{
                        ui:Label{Text = "Horizontal:", Weight = 0.5},
                        ui:LineEdit{ID = "hSpacing", Weight = 0.5, Text = "0"}
                    },
                    ui:HGroup{
                        ui:Label{Text = "Vertical:", Weight = 0.5},
                        ui:LineEdit{ID = "vSpacing", Weight = 0.5, Text = "0"}
                    }
                }
            },
            ui:VGap(5),
            ui:CheckBox{ID = "referenceMode", Text = "Clean reference block", Checked = false},
            ui:CheckBox{ID = "fitTallImages", Text = "Fit tall images", Checked = true},
            ui:CheckBox{ID = "showNames", Text = "Show file names", Checked = true},
            ui:HGroup{
                ui:Label{
                    Weight = 0.3,
                    Text = "Text Color: ",
                },
                ui:ComboBox{
                    Weight = 0.7,
                    ID = "textColor",
                }
            },
            ui:HGroup{
                ui:Label{
                    Weight = 0.3,
                    Text = "Sort Order: ",
                },
                ui:ComboBox{
                    Weight = 0.7,
                    ID = "sortOrder",
                }
            },
            ui:Label{ID = "totalSize", Text = "Final Size: calculating...", WordWrap = true},
            ui:HGroup{
                ui:Button{ID = "okButton", Text = "OK"},
                ui:Button{ID = "cancelButton", Text = "Cancel"}
            }
        }
    })

    -- Get the ComboBox item and add the options
    local items = dlg:GetItems()
    items.sortOrder:AddItem("Original Order")
    items.sortOrder:AddItem("Alphabetical")
    items.sortOrder:AddItem("Reverse Alphabetical")
    items.sortOrder:SetCurrentIndex(0)  -- Set default selection
    
    -- Add color options to the color dropdown
    items.textColor:AddItem("White")
    items.textColor:AddItem("Black")
    items.textColor:AddItem("Red")
    items.textColor:AddItem("Green")
    items.textColor:AddItem("Blue")
    items.textColor:AddItem("Yellow")
    items.textColor:AddItem("Cyan")
    items.textColor:AddItem("Magenta")
    items.textColor:AddItem("Orange")
    items.textColor:AddItem("Purple")
    items.textColor:SetCurrentIndex(0)  -- Default to White

    -- Add event handler for ComboBox changes
    function dlg.On.sortOrder.CurrentIndexChanged(ev)
        -- The value will be automatically passed to main() through the okButton handler
    end

    -- Update the event handlers
    function dlg.On.TileGridDialog.Close(ev)
        disp:ExitLoop()
    end

    function updateTargetInfo(resetGrid)
        local items = dlg:GetItems()
        local targetLoaders, targetScope = getTargetLoaders(comp)
        items.selectedNodesInfo.Text = getLoaderInfoText(#targetLoaders, targetScope)

        if resetGrid then
            local rows, cols = calculateDefaultGrid(#targetLoaders)
            items.gridRows.Text = tostring(rows)
            items.gridCols.Text = tostring(cols)
        end

        return targetLoaders
    end

    -- Add preview calculation for total size
    function updateTotalSize()
        local items = dlg:GetItems()
        local tileWidth = tonumber(items.tileWidth.Text)
        local gridRows = tonumber(items.gridRows.Text)
        local gridCols = tonumber(items.gridCols.Text)
        local hSpacing = tonumber(items.hSpacing.Text) or 0
        local vSpacing = tonumber(items.vSpacing.Text) or 0
        
        if tileWidth and gridRows and gridCols then
            local loaderNodes = updateTargetInfo(false)
            
            if #loaderNodes > 0 then
                local tileHeight = calculateTileHeight(loaderNodes, tileWidth)
                
                if tileHeight then
                    local adjustedRows, adjustedCols = getAdjustedGrid(gridRows, gridCols, #loaderNodes)
                    -- Add spacing to total dimensions
                    local totalWidth = (adjustedCols * tileWidth) + (hSpacing * (adjustedCols - 1))
                    local totalHeight = (adjustedRows * tileHeight) + (vSpacing * (adjustedRows - 1))
                    
                    if adjustedCols ~= gridCols then
                        items.totalSize.Text = string.format("Final Size: %dx%d pixels (columns will expand to %d)", totalWidth, totalHeight, adjustedCols)
                    else
                        items.totalSize.Text = string.format("Final Size: %dx%d pixels", totalWidth, totalHeight)
                    end
                else
                    items.totalSize.Text = "Final Size: calculating... (waiting for image data)"
                end
            else
                items.totalSize.Text = "Final Size: no Loader nodes found"
            end
        end
    end

    function dlg.On.tileWidth.TextChanged(ev)
        updateTotalSize()
    end

    function dlg.On.gridRows.TextChanged(ev)
        updateTotalSize()
    end

    function dlg.On.gridCols.TextChanged(ev)
        updateTotalSize()
    end

    function dlg.On.hSpacing.TextChanged(ev)
        local value = tonumber(ev.Text)
        if value then
            updateTotalSize()
        end
    end

    function dlg.On.vSpacing.TextChanged(ev)
        local value = tonumber(ev.Text)
        if value then
            updateTotalSize()
        end
    end

    function dlg.On.fitTallImages.Clicked(ev)
        updateTotalSize()
    end

    function dlg.On.okButton.Clicked(ev)
        local items = dlg:GetItems()
        local tileWidth = tonumber(items.tileWidth.Text)
        local gridRows = tonumber(items.gridRows.Text)
        local gridCols = tonumber(items.gridCols.Text)
        local showNames = items.showNames.Checked
        local sortOrder = items.sortOrder:GetCurrentIndex()
        local hSpacing = tonumber(items.hSpacing.Text) or 0
        local vSpacing = tonumber(items.vSpacing.Text) or 0
        local useReferenceMode = items.referenceMode.Checked
        local fitTallImages = items.fitTallImages.Checked
        
        -- Get color selection from dropdown
        local colorIndex = items.textColor:GetCurrentIndex()
        local textColor
        
        -- Map color index to RGB values
        if colorIndex == 0 then      -- White
            textColor = {1, 1, 1, 1}
        elseif colorIndex == 1 then  -- Black
            textColor = {0, 0, 0, 1}
        elseif colorIndex == 2 then  -- Red
            textColor = {1, 0, 0, 1}
        elseif colorIndex == 3 then  -- Green
            textColor = {0, 1, 0, 1}
        elseif colorIndex == 4 then  -- Blue
            textColor = {0, 0, 1, 1}
        elseif colorIndex == 5 then  -- Yellow
            textColor = {1, 1, 0, 1}
        elseif colorIndex == 6 then  -- Cyan
            textColor = {0, 1, 1, 1}
        elseif colorIndex == 7 then  -- Magenta
            textColor = {1, 0, 1, 1}
        elseif colorIndex == 8 then  -- Orange
            textColor = {1, 0.5, 0, 1}
        elseif colorIndex == 9 then  -- Purple
            textColor = {0.5, 0, 1, 1}
        else                         -- Default to White
            textColor = {1, 1, 1, 1}
        end

        if not tileWidth or not gridRows or not gridCols then
            print("Invalid input. Please enter valid numbers.")
            return
        end

        dlg:Hide()
        main(tileWidth, gridRows, gridCols, showNames, sortOrder, hSpacing, vSpacing, textColor, useReferenceMode, fitTallImages)
    end

    function dlg.On.cancelButton.Clicked(ev)
        dlg:Hide()
        disp:ExitLoop()
    end

    -- Calculate initial total size
    updateTargetInfo(false)
    updateTotalSize()

    return dlg
end

-- Main function to execute the script logic
function main(tileWidth, gridRows, gridCols, showNames, sortOrder, hSpacing, vSpacing, textColor, useReferenceMode, fitTallImages)
    local comp = fu:GetCurrentComp()
    
    local loaderNodes = getTargetLoaders(comp)

    -- Check if there are any loaders selected
    if #loaderNodes == 0 then
        if useReferenceMode then
            print("No original Loader nodes found.")
        else
            print("No Loader nodes selected.")
        end
        return
    end

    local tileHeight = calculateTileHeight(loaderNodes, tileWidth)
    if not tileHeight then
        tileHeight = math.floor(tileWidth)
        print("Warning: Could not determine aspect ratio, using square tiles.")
    end

    local sortableNodes = sortLoaders(loaderNodes, sortOrder)
    local adjustedRows, adjustedCols = getAdjustedGrid(gridRows, gridCols, #sortableNodes)

    if adjustedCols ~= gridCols then
        print(string.format("Grid has too few cells, expanding columns from %d to %d.", gridCols, adjustedCols))
    end

    gridRows = adjustedRows
    gridCols = adjustedCols

    printLoaderOrder(sortableNodes)

    -- Keep Fusion from redrawing the flow until all nodes and links are built.
    local locked = false
    pcall(function()
        comp:Lock()
        locked = true
    end)

    local undoStarted = false
    local ok, err = pcall(function()
        comp:StartUndo("Create Grid Collage")
        undoStarted = true

        if useReferenceMode then
            local result, message = createReferenceLayout(comp, sortableNodes, gridRows, gridCols, tileWidth, tileHeight, showNames, hSpacing, vSpacing, textColor, fitTallImages)
            if not result then
                error(message or "Could not create clean reference block.")
            end
        else
            createCurrentLayout(comp, sortableNodes, gridRows, gridCols, tileWidth, tileHeight, showNames, hSpacing, vSpacing, textColor, fitTallImages)
        end
    end)

    if undoStarted then
        pcall(function()
            comp:EndUndo()
        end)
    end

    if locked then
        pcall(function()
            comp:Unlock()
        end)
    end

    if not ok then
        print("Create Grid Collage failed: " .. tostring(err))
    end
end

-- Show the dialog and start the event loop
local dlg = createDialog()
dlg:Show()
disp:RunLoop()
dlg:Hide()
