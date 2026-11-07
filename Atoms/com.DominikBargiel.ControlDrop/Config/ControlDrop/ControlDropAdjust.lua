-- Get the active tool in the composition
local tool = comp.ActiveTool

-- Check if a tool is selected and it's a Loader
if not tool or tool.ID ~= "Loader" then
    return
end

-- Define functions
function ParseGlobalIn(tool)
    local parsedName = bmd.parseFilename(tool.Clip[1])
    return parsedName.Number
end

function moveLoader(tool, startFrom)
    comp:StartUndo("Set loader start")
    -- Let Fusion handle all the sequence settings
    bmd.MoveClip(tool, comp:GetAttrs().COMPN_GlobalStart, tonumber(startFrom))
    comp:EndUndo()
end

-- Main logic
local parsedGlobalIn = ParseGlobalIn(tool)
if parsedGlobalIn then
    moveLoader(tool, parsedGlobalIn)
end