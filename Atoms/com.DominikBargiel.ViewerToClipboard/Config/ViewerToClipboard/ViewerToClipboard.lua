-- Copy the focused Fusion viewer image to the Windows clipboard, or paste a
-- Windows clipboard image into Fusion as a Loader.
-- Loaded by ViewerToClipboard.fu from Config:/ViewerToClipboard.

local TAG = "[ViewerToClipboard] "
local DEBUG = false
local LOG_PATH = nil
local TRACE_LOG_PATH = nil
local SAVE_RETRY_COUNT = 12
local SAVE_RETRY_DELAY = 0.1
local INITIAL_TARGET = rawget(_G, "ViewerToClipboardTarget")
local REQUEST_ID = type(INITIAL_TARGET) == "table" and INITIAL_TARGET.requestId or nil
if REQUEST_ID == nil then
    REQUEST_ID = os.date("%H%M%S") .. "-" ..
        string.format("%06d", math.floor((os.clock() % 1) * 1000000))
end

local function getFusion()
    local f = rawget(_G, "fusion") or rawget(_G, "fu") or rawget(_G, "app")
    if f ~= nil then
        return f
    end

    if bmd ~= nil and bmd.scriptapp ~= nil then
        local ok, result = pcall(function()
            return bmd.scriptapp("Fusion")
        end)

        if ok then
            return result
        end
    end

    return nil
end

local function resolvePath(path)
    local mapper = rawget(_G, "comp") or getFusion()
    if mapper ~= nil and mapper.MapPath ~= nil then
        local ok, resolved = pcall(function()
            return mapper:MapPath(path)
        end)

        if ok and resolved ~= nil then
            return resolved
        end
    end

    return nil
end

local function logPath()
    if LOG_PATH == nil then
        LOG_PATH = resolvePath("Temp:/fusion_viewer_to_clipboard_summary.log")
    end

    return LOG_PATH
end

local function traceLogPath()
    if TRACE_LOG_PATH == nil then
        TRACE_LOG_PATH = resolvePath("Temp:/fusion_viewer_to_clipboard_trace.log")
    end

    return TRACE_LOG_PATH
end

local function appendLog(path, text)
    if path ~= nil then
        local file = io.open(path, "a")
        if file ~= nil then
            file:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. text .. "\n")
            file:close()
        end
    end
end

local function formattedLogMessage(message)
    return TAG .. "[" .. tostring(REQUEST_ID) .. "] " .. tostring(message)
end

local function trace(message)
    if not DEBUG then
        return
    end

    appendLog(traceLogPath(), formattedLogMessage(message))
end

local function log(message)
    if not DEBUG then
        return
    end

    local text = formattedLogMessage(message)
    print(text)
    appendLog(logPath(), text)
    appendLog(traceLogPath(), text)
end

local function notify(message)
    print(TAG .. "[" .. tostring(REQUEST_ID) .. "] " .. tostring(message))
end

local function waitSeconds(seconds)
    if bmd ~= nil and bmd.wait ~= nil then
        bmd.wait(seconds)
    end
end

local function nowSeconds()
    if bmd ~= nil and bmd.getuptime ~= nil then
        local ok, value = pcall(function()
            return bmd.getuptime()
        end)
        if ok and tonumber(value) ~= nil then
            return tonumber(value)
        end
    end

    return os.clock()
end

local function elapsedMilliseconds(startedAt)
    return math.max(0, (nowSeconds() - startedAt) * 1000)
end

local function formatDuration(milliseconds)
    milliseconds = tonumber(milliseconds) or 0
    if milliseconds < 1000 then
        return string.format("%.0fms", milliseconds)
    end

    return string.format("%.2fs", milliseconds / 1000)
end

local function safe(callable, label)
    local ok, result = pcall(callable)
    if ok then
        return result
    end

    if label ~= nil then
        log(label .. " failed: " .. tostring(result))
    end

    return nil
end

local function describeObject(value)
    if value == nil then
        return "nil"
    end

    local parts = {
        "type=" .. type(value),
        "object=" .. tostring(value),
    }

    local id = safe(function()
        if value.GetID ~= nil then
            return value:GetID()
        end
    end)
    if id ~= nil then
        table.insert(parts, "id=" .. tostring(id))
    end

    local attrs = safe(function()
        if value.GetAttrs ~= nil then
            return value:GetAttrs()
        end
    end)
    if type(attrs) == "table" then
        local attrKeys = {
            "COMPS_Name",
            "COMPS_FileName",
            "COMPN_CurrentTime",
            "TOOLS_Name",
            "TOOLST_Name",
            "VIEW_Name",
        }

        for _, key in ipairs(attrKeys) do
            local attrValue = attrs[key]
            if attrValue ~= nil and attrValue ~= "" then
                table.insert(parts, key .. "=" .. tostring(attrValue))
            end
        end
    end

    return table.concat(parts, " ")
end

local function shortObject(value)
    if value == nil then
        return "nil"
    end

    local id = safe(function()
        if value.GetID ~= nil then
            return value:GetID()
        end
    end)
    local address = tostring(value):match("0x[%x]+")

    if id ~= nil and address ~= nil then
        return tostring(id) .. "@" .. address
    end

    if id ~= nil then
        return tostring(id)
    end

    return address or type(value)
end

local function compositionSummary(activeComp)
    local attrs = safe(function()
        return activeComp:GetAttrs()
    end)
    if type(attrs) ~= "table" then
        return shortObject(activeComp)
    end

    return tostring(attrs.COMPS_Name or shortObject(activeComp)) ..
        " frame=" .. tostring(attrs.COMPN_CurrentTime or "?")
end

local function readFile(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end

    local data = file:read("*all")
    file:close()
    return data
end

local function writeFile(path, data)
    local file = io.open(path, "wb")
    if file == nil then
        return false
    end

    file:write(data or "")
    file:close()
    return true
end

local function pathJoin(root, child)
    if root == nil or root == "" then
        return child
    end

    local sep = "\\"
    if root:find("/") and not root:find("\\") then
        sep = "/"
    end

    if root:sub(-1) == "/" or root:sub(-1) == "\\" then
        return root .. child
    end

    return root .. sep .. child
end

local function dirname(path)
    if path == nil then
        return nil
    end

    return path:match("^(.*)[/\\][^/\\]+$") or nil
end

local function sanitizeFilePart(text)
    text = tostring(text or "")
    text = text:gsub("[<>:\"/\\|%?%*]", "_")
    text = text:gsub("%s+", "_")
    text = text:gsub("_+", "_")
    text = text:gsub("^_+", "")
    text = text:gsub("_+$", "")

    if text == "" then
        return "0"
    end

    return text
end

local function ensureDir(path)
    if path == nil or path == "" then
        return false
    end

    if bmd ~= nil and bmd.fileexists ~= nil and bmd.fileexists(path) then
        return true
    end

    if bmd ~= nil and bmd.createdir ~= nil then
        safe(function()
            bmd.createdir(path)
        end, "bmd.createdir")
    end

    if bmd ~= nil and bmd.fileexists ~= nil then
        return bmd.fileexists(path) == true
    end

    local probe = io.open(pathJoin(path, ".viewer_to_clipboard_probe"), "wb")
    if probe ~= nil then
        probe:close()
        os.remove(pathJoin(path, ".viewer_to_clipboard_probe"))
        return true
    end

    return false
end

local function fileSize(path)
    if path == nil then
        return 0
    end

    local file = io.open(path, "rb")
    if file == nil then
        return 0
    end

    local size = file:seek("end") or 0
    file:close()
    return size
end

local function resolveProjectMediaDir()
    if bmd == nil or bmd.scriptapp == nil then
        return nil
    end

    local resolve = safe(function()
        return bmd.scriptapp("Resolve")
    end, "Resolve app")

    if resolve == nil then
        return nil
    end

    local project = safe(function()
        local projectManager = resolve:GetProjectManager()
        return projectManager and projectManager:GetCurrentProject() or nil
    end, "Resolve current project")

    if project == nil then
        return nil
    end

    local function looksLikePath(value)
        return type(value) == "string" and value ~= "" and
            (value:find("[/\\]") ~= nil or value:find("^%a:") ~= nil)
    end

    local function isExcludedSettingName(key)
        local name = tostring(key):lower()
        return name:find("cache") ~= nil or
            name:find("proxy") ~= nil or
            name:find("gallery") ~= nil or
            name:find("still") ~= nil
    end

    local function isMediaLocationSettingName(key)
        local name = tostring(key):lower()
        local condensed = name:gsub("[_%s%-%.]", "")
        return condensed:find("medialocation") ~= nil or
            (name:find("project") ~= nil and
                name:find("media") ~= nil and
                (name:find("location") ~= nil or
                    name:find("path") ~= nil or
                    name:find("dir") ~= nil or
                    name:find("folder") ~= nil or
                    name:find("root") ~= nil))
    end

    local directKeys = {
        "mediaLocationPath",
        "MediaLocationPath",
        "mediaLocation",
        "MediaLocation",
        "projectMediaLocation",
        "ProjectMediaLocation",
        "projectMediaPath",
        "ProjectMediaPath",
        "projectMediaDir",
        "ProjectMediaDir",
        "projectMediaFolder",
        "ProjectMediaFolder",
        "projectMediaRoot",
        "ProjectMediaRoot",
    }

    for _, key in ipairs(directKeys) do
        local value = safe(function()
            return project:GetSetting(key)
        end, "Resolve project setting " .. key)

        if looksLikePath(value) then
            return value
        end
    end

    local settings = safe(function()
        return project:GetSetting()
    end, "Resolve project settings")

    if type(settings) == "table" then
        for key, value in pairs(settings) do
            if looksLikePath(value) and isMediaLocationSettingName(key) and not isExcludedSettingName(key) then
                return value
            end
        end
    end

    local userProfile = os.getenv("USERPROFILE")
    if type(userProfile) == "string" and userProfile ~= "" then
        return pathJoin(userProfile, "DaVinci Resolve Media")
    end

    return nil
end

local function getCompFolder(activeComp)
    local attrs = safe(function()
        return activeComp:GetAttrs()
    end, "comp:GetAttrs")

    if type(attrs) ~= "table" then
        return nil
    end

    local filename = attrs.COMPS_FileName
    if type(filename) ~= "string" or filename == "" then
        return nil
    end

    local mapped = activeComp:MapPath(filename)
    return dirname(mapped)
end

local function getFrameName(activeComp)
    local attrs = safe(function()
        return activeComp:GetAttrs()
    end, "comp:GetAttrs frame")

    local frame = attrs and attrs.COMPN_CurrentTime or nil
    frame = tonumber(frame) or 0

    if math.floor(frame) == frame then
        return string.format("%06d", frame)
    end

    return sanitizeFilePart(string.format("%.3f", frame):gsub("%.?0+$", ""):gsub("%.", "p"))
end

local function pngBitDepth(path)
    local data = readFile(path)
    if data == nil or #data < 33 or data:sub(1, 8) ~= "\137PNG\r\n\026\n" then
        return nil
    end

    local chunkType = data:sub(13, 16)
    if chunkType ~= "IHDR" then
        return nil
    end

    return data:byte(25), data:byte(26)
end

local function uniquePath(path)
    if bmd == nil or bmd.fileexists == nil or bmd.fileexists(path) ~= true then
        return path
    end

    local stem, ext = path:match("^(.*)(%.[^%.\\/]+)$")
    if stem == nil then
        stem = path
        ext = ""
    end

    for i = 1, 99 do
        local candidate = string.format("%s_%02d%s", stem, i, ext)
        if bmd.fileexists(candidate) ~= true then
            return candidate
        end
    end

    return path
end

local function getOutputImagePath(activeComp)
    local root = getCompFolder(activeComp)
    local source = "comp"

    if root == nil then
        root = resolveProjectMediaDir()
        source = "resolve-media"
    end

    if root == nil then
        root = activeComp:MapPath("Temp:/ViewerToClipboard")
        source = "temp"
    end

    local folder = pathJoin(root, "clipboard")
    if not ensureDir(folder) then
        folder = activeComp:MapPath("Temp:/ViewerToClipboard/clipboard")
        source = "temp"
        ensureDir(activeComp:MapPath("Temp:/ViewerToClipboard"))
        ensureDir(folder)
    end

    local filename = string.format("%s_image_%s.png", os.date("%Y%m%d_%H%M%S"), getFrameName(activeComp))
    local path = uniquePath(pathJoin(folder, filename))
    trace("Output image path source=" .. tostring(source) .. " path=" .. tostring(path))
    return path
end

local function getPastedImagePath(activeComp)
    local outputPath = getOutputImagePath(activeComp)
    if outputPath == nil then
        return nil
    end

    local stem, ext = outputPath:match("^(.*)(%.[^%.\\/]+)$")
    if stem == nil then
        return outputPath
    end

    return uniquePath(stem:gsub("_image_", "_pasted_") .. ext)
end

local function getPastedMediaPath(activeComp, extension)
    extension = tostring(extension or "png"):gsub("^%.", "")

    local imagePath = getPastedImagePath(activeComp)
    if imagePath == nil then
        return nil
    end

    local stem = imagePath:match("^(.*)%.[^%.\\/]+$")
    if stem == nil then
        return imagePath .. "." .. extension
    end

    return uniquePath(stem .. "." .. extension)
end

local function currentComp()
    if comp ~= nil then
        return comp
    end

    local f = getFusion()
    if f ~= nil then
        return safe(function()
            return f.CurrentComp
        end, "fusion.CurrentComp")
    end

    return nil
end

local function normalizeViewer(candidate, viewHint)
    if candidate == nil then
        return nil, viewHint
    end

    local currentViewer = safe(function()
        return candidate.CurrentViewer
    end)

    if currentViewer ~= nil then
        return currentViewer, candidate
    end

    return candidate, viewHint
end

local function addCandidate(candidates, seen, label, candidate, viewHint)
    trace("Inspecting candidate source " .. tostring(label) ..
        ": candidate={" .. describeObject(candidate) ..
        "} viewHint={" .. describeObject(viewHint) .. "}")

    local viewer, view = normalizeViewer(candidate, viewHint)
    if viewer == nil then
        trace("Skipping " .. tostring(label) .. ": no viewer object")
        return
    end

    local key = tostring(viewer)
    if seen[key] then
        trace("Skipping duplicate " .. tostring(label) .. ": " .. key)
        return
    end

    seen[key] = true
    table.insert(candidates, {
        label = label,
        viewer = viewer,
        view = view,
    })
    trace("Added candidate #" .. tostring(#candidates) .. " " .. tostring(label) ..
        ": viewer={" .. describeObject(viewer) ..
        "} view={" .. describeObject(view) .. "}")
end

local function addPreviewList(candidates, seen, label, previewList, activeComp)
    if previewList == nil then
        trace(tostring(label) .. " list is nil")
        return
    end

    local previewCount = 0
    for _ in pairs(previewList) do
        previewCount = previewCount + 1
    end
    trace(tostring(label) .. " list count=" .. tostring(previewCount))

    for name, preview in pairs(previewList) do
        local previewId = safe(function()
            return preview:GetID()
        end, label .. " " .. tostring(name) .. " GetID")
        trace(tostring(label) .. " entry name=" .. tostring(name) ..
            " previewId=" .. tostring(previewId) ..
            " preview={" .. describeObject(preview) .. "}")

        if previewId == nil or previewId == "GLPreview" then
            local view = safe(function()
                return preview.View
            end, label .. " " .. tostring(name) .. " preview.View")

            if view ~= nil then
                local viewComp = safe(function()
                    return view:Composition()
                end, label .. " " .. tostring(name) .. " Composition")
                trace(tostring(label) .. " entry name=" .. tostring(name) ..
                    " view={" .. describeObject(view) ..
                    "} viewComp={" .. describeObject(viewComp) ..
                    "} activeComp={" .. describeObject(activeComp) .. "}")

                if viewComp == nil or tostring(viewComp) == tostring(activeComp) then
                    addCandidate(candidates, seen, label .. " " .. tostring(name), safe(function()
                        return view.CurrentViewer
                    end, label .. " " .. tostring(name) .. " CurrentViewer"), view)

                    local viewerList = safe(function()
                        return view:GetViewerList()
                    end, label .. " " .. tostring(name) .. " GetViewerList")

                    if viewerList ~= nil then
                        for viewerName, viewer in pairs(viewerList) do
                            addCandidate(candidates, seen, label .. " " .. tostring(name) .. "/" .. tostring(viewerName), viewer, view)
                        end
                    end
                else
                    trace("Skipping " .. tostring(label) .. " " .. tostring(name) ..
                        ": preview belongs to a different composition")
                end
            else
                trace("Skipping " .. tostring(label) .. " " .. tostring(name) ..
                    ": preview has no View")
            end
        else
            trace("Skipping " .. tostring(label) .. " " .. tostring(name) ..
                ": previewId is not GLPreview")
        end
    end
end

local function getCandidates(activeComp, focusedOnly)
    local candidates = {}
    local seen = {}

    local target = rawget(_G, "ViewerToClipboardTarget")
    trace("Focused target at collection time: type=" .. type(target) ..
        " label=" .. tostring(type(target) == "table" and target.label or nil) ..
        " requestId=" .. tostring(type(target) == "table" and target.requestId or nil) ..
        " viewer={" .. describeObject(type(target) == "table" and target.viewer or nil) ..
        "} view={" .. describeObject(type(target) == "table" and target.view or nil) .. "}")
    if focusedOnly then
        log("Focus: label=" .. tostring(type(target) == "table" and target.label or "none") ..
            " viewer=" .. shortObject(type(target) == "table" and target.viewer or nil) ..
            " view=" .. shortObject(type(target) == "table" and target.view or nil))
    end
    if type(target) == "table" then
        addCandidate(candidates, seen, target.label or "Focused viewer", target.viewer or target.view, target.view)
    end

    if focusedOnly then
        return candidates
    end

    local frame = safe(function()
        return activeComp.CurrentFrame
    end, "CurrentFrame")

    if frame ~= nil then
        addCandidate(candidates, seen, "Active frame viewer", safe(function()
            return frame.CurrentViewer
        end, "frame.CurrentViewer"), nil)

        addPreviewList(candidates, seen, "Frame preview", safe(function()
            return frame:GetPreviewList()
        end, "frame:GetPreviewList"), activeComp)
    end

    addPreviewList(candidates, seen, "Comp preview", safe(function()
        return activeComp:GetPreviewList()
    end, "comp:GetPreviewList"), activeComp)

    local f = getFusion()
    if f ~= nil then
        addPreviewList(candidates, seen, "Fusion preview", safe(function()
            return f:GetPreviewList()
        end, "fusion:GetPreviewList"), activeComp)
    end

    return candidates
end

local clipboardApi = nil

local function loadClipboardApi()
    if clipboardApi ~= nil then
        return clipboardApi
    end

    local ok, ffi = pcall(require, "ffi")
    if not ok then
        return nil, "LuaJIT FFI is unavailable: " .. tostring(ffi)
    end

    ffi.cdef[[
        typedef void* HWND;
        typedef void* HANDLE;
        typedef void* HGLOBAL;
        typedef const char* LPCSTR;
        typedef const wchar_t* LPCWSTR;
        typedef unsigned int UINT;
        typedef int BOOL;
        typedef unsigned long DWORD;
        typedef long LONG;
        typedef unsigned short WORD;
        typedef uint64_t ULONG_PTR;
        typedef uintptr_t UINT_PTR;

        BOOL OpenClipboard(HWND hWndNewOwner);
        BOOL CloseClipboard(void);
        BOOL EmptyClipboard(void);
        BOOL IsClipboardFormatAvailable(UINT format);
        HANDLE GetClipboardData(UINT uFormat);
        HANDLE SetClipboardData(UINT uFormat, HANDLE hMem);
        UINT RegisterClipboardFormatA(LPCSTR lpszFormat);

        HGLOBAL GlobalAlloc(UINT uFlags, size_t dwBytes);
        void* GlobalLock(HGLOBAL hMem);
        BOOL GlobalUnlock(HGLOBAL hMem);
        HGLOBAL GlobalFree(HGLOBAL hMem);
        size_t GlobalSize(HGLOBAL hMem);
        UINT DragQueryFileA(HANDLE hDrop, UINT iFile, char* lpszFile, UINT cch);

        typedef struct {
            int32_t ciexyzX;
            int32_t ciexyzY;
            int32_t ciexyzZ;
        } CIEXYZ;

        typedef struct {
            CIEXYZ ciexyzRed;
            CIEXYZ ciexyzGreen;
            CIEXYZ ciexyzBlue;
        } CIEXYZTRIPLE;

        typedef struct {
            DWORD bV5Size;
            LONG bV5Width;
            LONG bV5Height;
            WORD bV5Planes;
            WORD bV5BitCount;
            DWORD bV5Compression;
            DWORD bV5SizeImage;
            LONG bV5XPelsPerMeter;
            LONG bV5YPelsPerMeter;
            DWORD bV5ClrUsed;
            DWORD bV5ClrImportant;
            DWORD bV5RedMask;
            DWORD bV5GreenMask;
            DWORD bV5BlueMask;
            DWORD bV5AlphaMask;
            DWORD bV5CSType;
            CIEXYZTRIPLE bV5Endpoints;
            DWORD bV5GammaRed;
            DWORD bV5GammaGreen;
            DWORD bV5GammaBlue;
            DWORD bV5Intent;
            DWORD bV5ProfileData;
            DWORD bV5ProfileSize;
            DWORD bV5Reserved;
        } BITMAPV5HEADER;

        typedef struct {
            uint32_t GdiplusVersion;
            void* DebugEventCallback;
            BOOL SuppressBackgroundThread;
            BOOL SuppressExternalCodecs;
        } GdiplusStartupInput;

        typedef struct {
            int X;
            int Y;
            int Width;
            int Height;
        } GpRect;

        typedef struct {
            UINT Width;
            UINT Height;
            int Stride;
            int PixelFormat;
            void* Scan0;
            UINT_PTR Reserved;
        } BitmapData;

        int GdiplusStartup(ULONG_PTR* token, const GdiplusStartupInput* input, void* output);
        void GdiplusShutdown(ULONG_PTR token);
        int GdipCreateBitmapFromFile(LPCWSTR filename, void** bitmap);
        int GdipDisposeImage(void* image);
        int GdipGetImageWidth(void* image, UINT* width);
        int GdipGetImageHeight(void* image, UINT* height);
        int GdipBitmapLockBits(void* bitmap, const GpRect* rect, UINT flags, int format, BitmapData* lockedBitmap);
        int GdipBitmapUnlockBits(void* bitmap, BitmapData* lockedBitmap);
    ]]

    local api = {
        ffi = ffi,
        user32 = ffi.load("user32"),
        kernel32 = ffi.load("kernel32"),
        gdiplus = ffi.load("gdiplus"),
        shell32 = ffi.load("shell32"),
        GMEM_MOVEABLE = 0x0002,
        GMEM_ZEROINIT = 0x0040,
        CF_DIB = 8,
        CF_HDROP = 15,
        CF_DIBV5 = 17,
        BI_BITFIELDS = 3,
        LCS_sRGB = 0x73524742,
        LCS_GM_IMAGES = 4,
        ImageLockModeRead = 1,
        PixelFormat32bppARGB = 0x0026200A,
    }

    clipboardApi = api
    return api
end

local function toWidePath(ffi, path)
    local wide = ffi.new("wchar_t[?]", #path + 1)
    for i = 1, #path do
        wide[i - 1] = path:byte(i)
    end
    wide[#path] = 0
    return wide
end

local function allocClipboardBytes(api, data)
    local ffi = api.ffi
    local size = #data
    local handle = api.kernel32.GlobalAlloc(api.GMEM_MOVEABLE + api.GMEM_ZEROINIT, size)
    if handle == nil then
        return nil
    end

    local ptr = api.kernel32.GlobalLock(handle)
    if ptr == nil then
        api.kernel32.GlobalFree(handle)
        return nil
    end

    ffi.copy(ptr, data, size)
    api.kernel32.GlobalUnlock(handle)
    return handle
end

local function createDibV5FromPng(api, imagePath)
    local ffi = api.ffi
    local token = ffi.new("ULONG_PTR[1]")
    local startup = ffi.new("GdiplusStartupInput")
    startup.GdiplusVersion = 1

    local status = api.gdiplus.GdiplusStartup(token, startup, nil)
    if status ~= 0 then
        return nil, "GdiplusStartup failed: " .. tostring(status)
    end

    local bitmap = ffi.new("void*[1]")
    status = api.gdiplus.GdipCreateBitmapFromFile(toWidePath(ffi, imagePath), bitmap)
    if status ~= 0 then
        api.gdiplus.GdiplusShutdown(token[0])
        return nil, "GdipCreateBitmapFromFile failed: " .. tostring(status)
    end

    local widthPtr = ffi.new("UINT[1]")
    local heightPtr = ffi.new("UINT[1]")
    status = api.gdiplus.GdipGetImageWidth(bitmap[0], widthPtr)
    if status == 0 then
        status = api.gdiplus.GdipGetImageHeight(bitmap[0], heightPtr)
    end

    local width = tonumber(widthPtr[0])
    local height = tonumber(heightPtr[0])

    if status ~= 0 or width == nil or height == nil or width <= 0 or height <= 0 then
        api.gdiplus.GdipDisposeImage(bitmap[0])
        api.gdiplus.GdiplusShutdown(token[0])
        return nil, "Could not read image dimensions"
    end

    local rect = ffi.new("GpRect")
    rect.X = 0
    rect.Y = 0
    rect.Width = width
    rect.Height = height

    local data = ffi.new("BitmapData")
    status = api.gdiplus.GdipBitmapLockBits(bitmap[0], rect, api.ImageLockModeRead, api.PixelFormat32bppARGB, data)
    if status ~= 0 then
        api.gdiplus.GdipDisposeImage(bitmap[0])
        api.gdiplus.GdiplusShutdown(token[0])
        return nil, "GdipBitmapLockBits failed: " .. tostring(status)
    end

    local headerSize = tonumber(ffi.sizeof("BITMAPV5HEADER"))
    local rowBytes = width * 4
    local pixelBytes = rowBytes * height
    local totalBytes = headerSize + pixelBytes
    local handle = api.kernel32.GlobalAlloc(api.GMEM_MOVEABLE + api.GMEM_ZEROINIT, totalBytes)

    if handle == nil then
        api.gdiplus.GdipBitmapUnlockBits(bitmap[0], data)
        api.gdiplus.GdipDisposeImage(bitmap[0])
        api.gdiplus.GdiplusShutdown(token[0])
        return nil, "GlobalAlloc failed for DIBV5"
    end

    local mem = api.kernel32.GlobalLock(handle)
    if mem == nil then
        api.kernel32.GlobalFree(handle)
        api.gdiplus.GdipBitmapUnlockBits(bitmap[0], data)
        api.gdiplus.GdipDisposeImage(bitmap[0])
        api.gdiplus.GdiplusShutdown(token[0])
        return nil, "GlobalLock failed for DIBV5"
    end

    local header = ffi.cast("BITMAPV5HEADER*", mem)
    header.bV5Size = headerSize
    header.bV5Width = width
    header.bV5Height = height
    header.bV5Planes = 1
    header.bV5BitCount = 32
    header.bV5Compression = api.BI_BITFIELDS
    header.bV5SizeImage = pixelBytes
    header.bV5XPelsPerMeter = 2835
    header.bV5YPelsPerMeter = 2835
    header.bV5RedMask = 0x00FF0000
    header.bV5GreenMask = 0x0000FF00
    header.bV5BlueMask = 0x000000FF
    header.bV5AlphaMask = 0xFF000000
    header.bV5CSType = api.LCS_sRGB
    header.bV5Intent = api.LCS_GM_IMAGES

    local sourceBase = ffi.cast("uint8_t*", data.Scan0)
    local destBase = ffi.cast("uint8_t*", mem) + headerSize
    local stride = tonumber(data.Stride)
    local strideAbs = math.abs(stride)

    for y = 0, height - 1 do
        local sourceY = y
        if stride < 0 then
            sourceY = height - 1 - y
        end

        local sourceRow = sourceBase + (sourceY * strideAbs)
        local destRow = destBase + ((height - 1 - y) * rowBytes)
        ffi.copy(destRow, sourceRow, rowBytes)
    end

    api.kernel32.GlobalUnlock(handle)
    api.gdiplus.GdipBitmapUnlockBits(bitmap[0], data)
    api.gdiplus.GdipDisposeImage(bitmap[0])
    api.gdiplus.GdiplusShutdown(token[0])

    return handle, nil, width, height
end

local function openClipboard(api)
    for _ = 1, 10 do
        if api.user32.OpenClipboard(nil) ~= 0 then
            return true
        end

        if bmd ~= nil and bmd.wait ~= nil then
            bmd.wait(0.01)
        end
    end

    return false
end

local function setImageClipboard(imagePath)
    local totalStarted = nowSeconds()

    local apiStarted = nowSeconds()
    local api, err = loadClipboardApi()
    local apiMilliseconds = elapsedMilliseconds(apiStarted)
    if api == nil then
        return false, err, elapsedMilliseconds(totalStarted)
    end

    local readStarted = nowSeconds()
    local pngData = readFile(imagePath)
    local readMilliseconds = elapsedMilliseconds(readStarted)
    if pngData == nil or #pngData == 0 then
        return false, "Could not read saved PNG", elapsedMilliseconds(totalStarted)
    end

    local pngFormat = api.user32.RegisterClipboardFormatA("PNG")
    local imagePngFormat = api.user32.RegisterClipboardFormatA("image/png")

    local pngCopiesStarted = nowSeconds()
    local pngHandle = allocClipboardBytes(api, pngData)
    local imagePngHandle = allocClipboardBytes(api, pngData)
    local pngCopiesMilliseconds = elapsedMilliseconds(pngCopiesStarted)

    local dibStarted = nowSeconds()
    local dibHandle, dibErr, width, height = createDibV5FromPng(api, imagePath)
    local dibMilliseconds = elapsedMilliseconds(dibStarted)

    if pngHandle == nil and imagePngHandle == nil and dibHandle == nil then
        return false, dibErr or "Could not allocate clipboard data", elapsedMilliseconds(totalStarted)
    end

    local openStarted = nowSeconds()
    if not openClipboard(api) then
        if pngHandle ~= nil then api.kernel32.GlobalFree(pngHandle) end
        if imagePngHandle ~= nil then api.kernel32.GlobalFree(imagePngHandle) end
        if dibHandle ~= nil then api.kernel32.GlobalFree(dibHandle) end
        return false, "Could not open Windows clipboard", elapsedMilliseconds(totalStarted)
    end
    local openMilliseconds = elapsedMilliseconds(openStarted)

    local setStarted = nowSeconds()
    api.user32.EmptyClipboard()

    local setCount = 0
    if pngHandle ~= nil and pngFormat ~= 0 and api.user32.SetClipboardData(pngFormat, pngHandle) ~= nil then
        pngHandle = nil
        setCount = setCount + 1
    end

    if imagePngHandle ~= nil and imagePngFormat ~= 0 and api.user32.SetClipboardData(imagePngFormat, imagePngHandle) ~= nil then
        imagePngHandle = nil
        setCount = setCount + 1
    end

    if dibHandle ~= nil and api.user32.SetClipboardData(api.CF_DIBV5, dibHandle) ~= nil then
        dibHandle = nil
        setCount = setCount + 1
    end

    api.user32.CloseClipboard()

    if pngHandle ~= nil then api.kernel32.GlobalFree(pngHandle) end
    if imagePngHandle ~= nil then api.kernel32.GlobalFree(imagePngHandle) end
    if dibHandle ~= nil then api.kernel32.GlobalFree(dibHandle) end

    local setMilliseconds = elapsedMilliseconds(setStarted)
    local totalMilliseconds = elapsedMilliseconds(totalStarted)
    log("Clipboard: time=" .. formatDuration(totalMilliseconds) ..
        " [api=" .. formatDuration(apiMilliseconds) ..
        " read=" .. formatDuration(readMilliseconds) ..
        " pngCopies=" .. formatDuration(pngCopiesMilliseconds) ..
        " dib=" .. formatDuration(dibMilliseconds) ..
        " open=" .. formatDuration(openMilliseconds) ..
        " set=" .. formatDuration(setMilliseconds) .. "]" ..
        " formats=" .. tostring(setCount) ..
        " dims=" .. tostring(width) .. "x" .. tostring(height) ..
        " bytes=" .. tostring(#pngData) ..
        (dibErr ~= nil and " dibError=" .. tostring(dibErr) or ""))
    return setCount > 0, setCount > 0 and nil or "SetClipboardData failed", totalMilliseconds
end

local function quoteWindowsArg(value)
    value = tostring(value or "")
    return '"' .. value:gsub('"', '\\"') .. '"'
end

local function isSupportedMediaPath(path)
    if type(path) ~= "string" or path == "" then
        return false
    end

    local ext = path:match("%.([^%.\\/]+)$")
    if ext == nil then
        return false
    end

    ext = ext:lower()
    return ext == "png" or
        ext == "jpg" or
        ext == "jpeg" or
        ext == "tif" or
        ext == "tiff" or
        ext == "bmp" or
        ext == "exr" or
        ext == "tga" or
        ext == "dpx" or
        ext == "gif" or
        ext == "webp" or
        ext == "mov" or
        ext == "mp4" or
        ext == "avi" or
        ext == "mxf" or
        ext == "mkv"
end

local function le16(value)
    value = tonumber(value) or 0
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function le32(value)
    value = tonumber(value) or 0
    local b1 = value % 256
    local b2 = math.floor(value / 256) % 256
    local b3 = math.floor(value / 65536) % 256
    local b4 = math.floor(value / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

local function readLe16(data, offset)
    local b1, b2 = data:byte(offset, offset + 1)
    if b1 == nil or b2 == nil then
        return 0
    end

    return b1 + b2 * 256
end

local function readLe32(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    if b1 == nil or b2 == nil or b3 == nil or b4 == nil then
        return 0
    end

    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function dibToBmpData(dibData)
    if type(dibData) ~= "string" or #dibData < 16 then
        return nil
    end

    local headerSize = readLe32(dibData, 1)
    if headerSize <= 0 or headerSize > #dibData then
        return nil
    end

    local bitCount = 0
    local compression = 0
    local colorCount = 0
    local extraMaskBytes = 0

    if headerSize == 12 then
        bitCount = readLe16(dibData, 11)
        if bitCount > 0 and bitCount <= 8 then
            colorCount = 2 ^ bitCount
        end
    else
        bitCount = readLe16(dibData, 15)
        compression = readLe32(dibData, 17)
        colorCount = readLe32(dibData, 33)
        if colorCount == 0 and bitCount > 0 and bitCount <= 8 then
            colorCount = 2 ^ bitCount
        end

        if headerSize == 40 and (compression == 3 or compression == 6) then
            extraMaskBytes = 12
        end
    end

    local paletteBytes = colorCount * (headerSize == 12 and 3 or 4)
    local pixelOffset = 14 + headerSize + extraMaskBytes + paletteBytes
    if pixelOffset > #dibData + 14 then
        pixelOffset = 14 + headerSize
    end

    return "BM" ..
        le32(#dibData + 14) ..
        le16(0) ..
        le16(0) ..
        le32(pixelOffset) ..
        dibData
end

local function getClipboardBytes(api, format)
    if api.user32.IsClipboardFormatAvailable(format) == 0 then
        return nil
    end

    local handle = api.user32.GetClipboardData(format)
    if handle == nil then
        return nil
    end

    local size = tonumber(api.kernel32.GlobalSize(handle)) or 0
    if size <= 0 then
        return nil
    end

    local ptr = api.kernel32.GlobalLock(handle)
    if ptr == nil then
        return nil
    end

    local data = api.ffi.string(ptr, size)
    api.kernel32.GlobalUnlock(handle)
    return data
end

local function getClipboardFileDrop(api)
    if api.user32.IsClipboardFormatAvailable(api.CF_HDROP) == 0 then
        return nil
    end

    local handle = api.user32.GetClipboardData(api.CF_HDROP)
    if handle == nil then
        return nil
    end

    local count = tonumber(api.shell32.DragQueryFileA(handle, 0xFFFFFFFF, nil, 0)) or 0
    for index = 0, count - 1 do
        local length = tonumber(api.shell32.DragQueryFileA(handle, index, nil, 0)) or 0
        if length > 0 then
            local buffer = api.ffi.new("char[?]", length + 1)
            api.shell32.DragQueryFileA(handle, index, buffer, length + 1)

            local path = api.ffi.string(buffer)
            if isSupportedMediaPath(path) then
                return path
            end
        end
    end

    return nil
end

local function getClipboardImageOrFileFast(activeComp)
    local api, apiErr = loadClipboardApi()
    if api == nil then
        return nil, nil, apiErr or "Clipboard FFI unavailable"
    end

    if not openClipboard(api) then
        return nil, nil, "Could not open Windows clipboard"
    end

    local kind = nil
    local clipPath = nil
    local err = nil

    local ok, runErr = pcall(function()
        local filePath = getClipboardFileDrop(api)
        if filePath ~= nil then
            kind = "file"
            clipPath = filePath
            return
        end

        local pngFormat = api.user32.RegisterClipboardFormatA("PNG")
        local imagePngFormat = api.user32.RegisterClipboardFormatA("image/png")
        local pngData = nil
        if pngFormat ~= 0 then
            pngData = getClipboardBytes(api, pngFormat)
        end

        if pngData == nil and imagePngFormat ~= 0 then
            pngData = getClipboardBytes(api, imagePngFormat)
        end

        if pngData ~= nil then
            local path = getPastedMediaPath(activeComp, "png")
            if path == nil then
                err = "Could not resolve pasted PNG path"
                return
            end

            os.remove(path)
            if writeFile(path, pngData) and fileSize(path) > 0 then
                kind = "image"
                clipPath = path
                return
            end

            err = "Could not write pasted PNG"
            return
        end

        local dibData = getClipboardBytes(api, api.CF_DIBV5) or getClipboardBytes(api, api.CF_DIB)
        if dibData ~= nil then
            local bmpData = dibToBmpData(dibData)
            if bmpData == nil then
                err = "Could not convert clipboard bitmap"
                return
            end

            local path = getPastedMediaPath(activeComp, "bmp")
            if path == nil then
                err = "Could not resolve pasted BMP path"
                return
            end

            os.remove(path)
            if writeFile(path, bmpData) and fileSize(path) > 0 then
                kind = "image"
                clipPath = path
                return
            end

            err = "Could not write pasted BMP"
            return
        end

        kind = "empty"
    end)

    api.user32.CloseClipboard()

    if not ok then
        return nil, nil, tostring(runErr)
    end

    return kind, clipPath, err
end

local function clipboardPowerShellScript()
    return [[
param(
    [Parameter(Mandatory = $true)][string]$OutPath,
    [Parameter(Mandatory = $true)][string]$MetaPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Write-ClipboardMeta([string]$Kind, [string]$Value) {
    Set-Content -LiteralPath $MetaPath -Encoding UTF8 -Value @($Kind, $Value)
}

try {
    if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
        $image = [System.Windows.Forms.Clipboard]::GetImage()
        if ($null -ne $image) {
            $image.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $image.Dispose()
            Write-ClipboardMeta 'image' $OutPath
            exit 0
        }
    }

    if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
        $extensions = @(
            '.png', '.jpg', '.jpeg', '.tif', '.tiff', '.bmp', '.exr', '.tga',
            '.dpx', '.gif', '.webp', '.mov', '.mp4', '.avi', '.mxf', '.mkv'
        )

        foreach ($file in [System.Windows.Forms.Clipboard]::GetFileDropList()) {
            if ($extensions -contains [System.IO.Path]::GetExtension($file).ToLowerInvariant()) {
                Write-ClipboardMeta 'file' $file
                exit 0
            }
        }
    }

    Write-ClipboardMeta 'empty' ''
    exit 2
}
catch {
    Write-ClipboardMeta 'error' $_.Exception.Message
    exit 1
}
]]
end

local function readClipboardMeta(metaPath)
    local meta = readFile(metaPath)
    if meta == nil then
        return nil, nil
    end

    meta = meta:gsub("^\239\187\191", "")
    meta = meta:gsub("\r\n", "\n")

    local kind, value = meta:match("^([^\n]*)\n?(.*)$")
    value = value or ""
    value = value:gsub("\n+$", "")
    return kind, value
end

local function getClipboardImageOrFile(activeComp)
    local fastKind, fastPath, fastErr = getClipboardImageOrFileFast(activeComp)
    if fastKind ~= nil then
        log("Fast clipboard result kind=" .. tostring(fastKind) .. " path=" .. tostring(fastPath))
        return fastKind, fastPath, fastErr
    end

    log("Fast clipboard path failed; falling back to PowerShell: " .. tostring(fastErr))

    local imagePath = getPastedImagePath(activeComp)
    if imagePath == nil then
        return nil, nil, "Could not resolve pasted image path"
    end

    local tempRoot = activeComp:MapPath("Temp:/ViewerToClipboard")
    if tempRoot == nil or tempRoot == "" then
        return nil, nil, "Could not resolve Fusion temp path"
    end

    ensureDir(tempRoot)

    local scriptPath = pathJoin(tempRoot, "read_clipboard_image.ps1")
    local metaPath = pathJoin(tempRoot, "read_clipboard_image.txt")
    os.remove(imagePath)
    os.remove(metaPath)

    if not writeFile(scriptPath, clipboardPowerShellScript()) then
        return nil, nil, "Could not write clipboard helper script"
    end

    local command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File " ..
        quoteWindowsArg(scriptPath) ..
        " -OutPath " .. quoteWindowsArg(imagePath) ..
        " -MetaPath " .. quoteWindowsArg(metaPath)

    log("Running clipboard helper: " .. command)
    os.execute(command)

    local kind, value = readClipboardMeta(metaPath)
    log("Clipboard helper result kind=" .. tostring(kind) .. " value=" .. tostring(value))

    if kind == "image" and fileSize(value) > 0 then
        return "image", value, nil
    end

    if kind == "file" and isSupportedMediaPath(value) then
        return "file", value, nil
    end

    if kind == "empty" then
        return "empty", nil, nil
    end

    return nil, nil, value or "Clipboard helper did not return image data"
end

local function setLoaderLoop(loader)
    safe(function()
        loader.Loop[1] = 1
    end, "loader.Loop[1]")

    safe(function()
        loader.Loop = 1
    end, "loader.Loop")
end

local function createLoaderFromPath(activeComp, clipPath)
    local loader = nil

    safe(function()
        activeComp:StartUndo("Paste Clipboard Image as Loader")
    end, "comp:StartUndo paste")

    safe(function()
        activeComp:Lock()
    end, "comp:Lock paste")

    local ok, err = pcall(function()
        safe(function()
            activeComp:SetActiveTool(nil)
        end, "comp:SetActiveTool nil")

        loader = activeComp:AddTool("Loader", -32768, -32768)
        if loader ~= nil then
            loader.Clip[1] = clipPath
            setLoaderLoop(loader)

            safe(function()
                activeComp:SetActiveTool(loader)
            end, "comp:SetActiveTool loader")
        end
    end)

    safe(function()
        activeComp:Unlock()
    end, "comp:Unlock paste")

    safe(function()
        activeComp:EndUndo()
    end, "comp:EndUndo paste")

    if not ok then
        return nil, err
    end

    if loader == nil then
        return nil, "Could not create Loader"
    end

    return loader, nil
end

local function defaultPaste(activeComp)
    if activeComp == nil then
        return false
    end

    return safe(function()
        activeComp:Paste()
        return true
    end, "comp:Paste") == true
end

local function refreshCandidate(candidate)
    safe(function()
        if candidate.viewer ~= nil and candidate.viewer.Redraw ~= nil then
            candidate.viewer:Redraw()
        end
    end, tostring(candidate.label) .. " viewer:Redraw")

    safe(function()
        if candidate.view ~= nil and candidate.view.Refresh ~= nil then
            candidate.view:Refresh()
        end
    end, tostring(candidate.label) .. " view:Refresh")
end

local function saveViewerImage(candidate, imagePath)
    os.remove(imagePath)

    local saveFileStarted = nowSeconds()
    local saved = safe(function()
        return candidate.viewer:SaveFile(imagePath)
    end, tostring(candidate.label) .. " SaveFile")
    local saveFileMilliseconds = elapsedMilliseconds(saveFileStarted)

    local size = fileSize(imagePath)
    trace("SaveFile " .. tostring(candidate.label) ..
        ": time=" .. formatDuration(saveFileMilliseconds) ..
        " saved=" .. tostring(saved) ..
        " size=" .. tostring(size))

    if saved ~= true or size <= 0 then
        return false, saveFileMilliseconds
    end

    local bitDepth, colorType = pngBitDepth(imagePath)
    trace("PNG depth for " .. tostring(candidate.label) .. ": bitDepth=" .. tostring(bitDepth) .. " colorType=" .. tostring(colorType))

    if bitDepth ~= 16 then
        log("Warning: saved PNG is not 16-bit")
    end

    return true, saveFileMilliseconds
end

local function saveAnyViewerImage(candidates, imagePath, retryCount)
    retryCount = retryCount or SAVE_RETRY_COUNT
    local totalStarted = nowSeconds()

    for attempt = 1, retryCount do
        trace("Save attempt " .. tostring(attempt) .. "/" .. tostring(retryCount) ..
            " candidateCount=" .. tostring(#candidates))

        for candidateIndex, candidate in ipairs(candidates) do
            trace("Trying candidate #" .. tostring(candidateIndex) ..
                " label=" .. tostring(candidate.label) ..
                " viewer={" .. describeObject(candidate.viewer) ..
                "} view={" .. describeObject(candidate.view) .. "}")

            if attempt > 1 then
                refreshCandidate(candidate)
            end

            local saved, saveFileMilliseconds = saveViewerImage(candidate, imagePath)
            if saved then
                local totalMilliseconds = elapsedMilliseconds(totalStarted)
                log("Saved: time=" .. formatDuration(totalMilliseconds) ..
                    " saveFile=" .. formatDuration(saveFileMilliseconds) ..
                    " attempt=" .. tostring(attempt) ..
                    " candidate=#" .. tostring(candidateIndex) ..
                    " label=" .. tostring(candidate.label) ..
                    " viewer=" .. shortObject(candidate.viewer) ..
                    " bytes=" .. tostring(fileSize(imagePath)))

                return candidate, totalMilliseconds
            end
        end

        if attempt < retryCount then
            waitSeconds(SAVE_RETRY_DELAY)
        end
    end

    return nil, elapsedMilliseconds(totalStarted)
end

local function summarizeCandidates(candidates)
    local summary = {}
    for index, candidate in ipairs(candidates) do
        table.insert(summary,
            "#" .. tostring(index) .. " " .. tostring(candidate.label) ..
            " " .. shortObject(candidate.viewer))
        trace("Candidate order #" .. tostring(index) ..
            " label=" .. tostring(candidate.label) ..
            " viewer={" .. describeObject(candidate.viewer) ..
            "} view={" .. describeObject(candidate.view) .. "}")
    end

    return #summary > 0 and " [" .. table.concat(summary, "; ") .. "]" or ""
end

local function mainCopy()
    local scriptStarted = type(INITIAL_TARGET) == "table" and
        tonumber(INITIAL_TARGET.scriptStartedAt) or nil
    if scriptStarted == nil then
        scriptStarted = nowSeconds()
    end

    local totalStarted = type(INITIAL_TARGET) == "table" and
        tonumber(INITIAL_TARGET.actionStartedAt) or nil
    if totalStarted == nil then
        totalStarted = scriptStarted
    end

    local loadMilliseconds = math.max(0, (scriptStarted - totalStarted) * 1000)
    local activeComp = currentComp()
    if activeComp == nil then
        log("No active composition")
        notify("Shift+Ctrl+C was received, but there is no active composition.")
        return false
    end

    log("=== COPY START === comp=" .. compositionSummary(activeComp))
    trace("Compact log path=" .. tostring(logPath()) ..
        " trace log path=" .. tostring(traceLogPath()))
    trace("Active composition: {" .. describeObject(activeComp) .. "}")

    local imagePath = getOutputImagePath(activeComp)
    if imagePath == nil then
        log("Could not resolve output image path")
        notify("Shift+Ctrl+C was received, but no output path could be resolved.")
        return false
    end

    local setupMilliseconds = elapsedMilliseconds(scriptStarted)

    local focusedDiscoveryStarted = nowSeconds()
    local candidates = getCandidates(activeComp, true)
    local discoveryMilliseconds = elapsedMilliseconds(focusedDiscoveryStarted)
    log("Candidates: discovery=" .. formatDuration(discoveryMilliseconds) ..
        " count=" .. tostring(#candidates) .. summarizeCandidates(candidates))

    local savedCandidate = nil
    local saveMilliseconds = 0
    local fallbackReason = nil
    if #candidates > 0 then
        savedCandidate, saveMilliseconds = saveAnyViewerImage(candidates, imagePath, 1)
        if savedCandidate == nil then
            fallbackReason = "focused SaveFile failed"
        end
    else
        fallbackReason = "no focused candidate"
    end

    if savedCandidate == nil then
        local fallbackDiscoveryStarted = nowSeconds()
        candidates = getCandidates(activeComp, false)
        local fallbackDiscoveryMilliseconds = elapsedMilliseconds(fallbackDiscoveryStarted)
        discoveryMilliseconds = discoveryMilliseconds + fallbackDiscoveryMilliseconds
        log("Fallback: reason=" .. tostring(fallbackReason) ..
            " discovery=" .. formatDuration(fallbackDiscoveryMilliseconds) ..
            " count=" .. tostring(#candidates) .. summarizeCandidates(candidates))

        if #candidates == 0 then
            log("=== COPY FAILED: no candidates === total=" ..
                formatDuration(elapsedMilliseconds(totalStarted)))
            notify("Shift+Ctrl+C was received, but no focused 2D viewer was found. Click inside the viewer image area and try again.")
            return false
        end

        local fallbackSaveMilliseconds = 0
        savedCandidate, fallbackSaveMilliseconds =
            saveAnyViewerImage(candidates, imagePath, SAVE_RETRY_COUNT)
        saveMilliseconds = saveMilliseconds + fallbackSaveMilliseconds
    end

    if savedCandidate ~= nil then
        trace("Selected saved candidate label=" .. tostring(savedCandidate.label) ..
            " viewer={" .. describeObject(savedCandidate.viewer) ..
            "} imagePath=" .. tostring(imagePath) ..
            " imageSize=" .. tostring(fileSize(imagePath)))
        local copied, err, clipboardMilliseconds = setImageClipboard(imagePath)
        if copied then
            log("=== COPY SUCCESS === total=" ..
                formatDuration(elapsedMilliseconds(totalStarted)) ..
                " [load=" .. formatDuration(loadMilliseconds) ..
                " setup=" .. formatDuration(setupMilliseconds) ..
                " discovery=" .. formatDuration(discoveryMilliseconds) ..
                " save=" .. formatDuration(saveMilliseconds) ..
                " clipboard=" .. formatDuration(clipboardMilliseconds) .. "]" ..
                " candidate=" .. tostring(savedCandidate.label) ..
                " viewer=" .. shortObject(savedCandidate.viewer))
            return true
        end

        log("=== COPY FAILED: clipboard === error=" .. tostring(err) ..
            " total=" .. formatDuration(elapsedMilliseconds(totalStarted)) ..
            " candidate=" .. tostring(savedCandidate.label))
        trace("Clipboard failure imagePath=" .. tostring(imagePath) ..
            " imageSize=" .. tostring(fileSize(imagePath)))
        notify("Viewer image was saved, but copying to the clipboard failed: " .. tostring(err))
        return false
    end

    log("=== COPY FAILED: no viewer saved === attempts=" .. tostring(SAVE_RETRY_COUNT) ..
        " candidateCount=" .. tostring(#candidates) ..
        " total=" .. formatDuration(elapsedMilliseconds(totalStarted)) ..
        " discovery=" .. formatDuration(discoveryMilliseconds) ..
        " save=" .. formatDuration(saveMilliseconds))
    trace("No viewer saved imagePath=" .. tostring(imagePath) ..
        " finalImageSize=" .. tostring(fileSize(imagePath)))
    notify("Shift+Ctrl+C was received, but the viewer was not ready to save yet. Wait a moment after render completion or click directly inside the viewer image area and try again.")
    return false
end

local function mainPaste()
    local activeComp = currentComp()
    if activeComp == nil then
        log("No active composition")
        notify("Ctrl+V was received, but there is no active composition.")
        return false
    end

    local kind, clipPath, err = getClipboardImageOrFile(activeComp)
    if kind == "empty" then
        log("Clipboard does not contain image media; falling back to comp:Paste")
        return defaultPaste(activeComp)
    end

    if clipPath == nil then
        log("Clipboard image read failed: " .. tostring(err))
        return defaultPaste(activeComp)
    end

    local loader, loaderErr = createLoaderFromPath(activeComp, clipPath)
    if loader == nil then
        notify("Ctrl+V found clipboard image media, but creating the Loader failed: " .. tostring(loaderErr))
        return false
    end

    log("Pasted clipboard " .. tostring(kind) .. " as Loader path=" .. tostring(clipPath))
    return true
end

if rawget(_G, "ViewerToClipboardMode") == "paste" then
    mainPaste()
else
    mainCopy()
end
