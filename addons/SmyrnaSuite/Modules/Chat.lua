local _,Suite=...
local name="SmyrnaChat"
Suite.Versions[name]="0.6.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

-- Internal module source: Core.lua
do local function chunk(...)
local _, NS = ...
local Core = {}
NS.Core = Core

-- Curated internet spellings/inflections; not a popularity ranking.
function Core.Readable(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "string"
end

function Core.Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Core.Key(name)
    return string.lower((name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")))
end

function Core.Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text
end

function Core.TimestampColor(options)
    local hex=options and options.timestampColor
    return type(hex)=="string" and #hex==6 and hex:match("^%x+$") and string.lower(hex) or "888888"
end
function Core.RGBHex(r,g,b)
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return end
    if type(r)~="number" or type(g)~="number" or type(b)~="number" or r~=r or g~=g or b~=b then return end
    return string.format("%02x%02x%02x",math.floor(math.max(0,math.min(1,r))*255+.5),math.floor(math.max(0,math.min(1,g))*255+.5),math.floor(math.max(0,math.min(1,b))*255+.5))
end
function Core.ColorRGB(hex)
    return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
end


end chunk(name,Module) end

-- Internal module source: SmyrnaChat.lua
do local function chunk(...)
local addonName, NS = ...
local Core = NS.Core
local DB, copyWindow
local stamp, stampSecond
local refreshPending
local hooked = setmetatable({}, { __mode = "k" })
local driver = CreateFrame("Frame")

local function Say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffedbd72Smyrna Chat:|r " .. text)
end

local function ValidLabel(text)
    return text ~= "" and #text <= 48 and not text:find("[%c|%[%]]")
end

local function HookFrame(frame)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    local copy=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    copy:SetSize(42,18);copy:SetPoint("BOTTOMRIGHT",frame,"TOPRIGHT",-50,6)
    copy:SetText("History");copy:SetWidth(55);copy:SetAlpha(.65)
    copy:SetScript("OnEnter",function(self)
        self:SetAlpha(1);GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Chat history")
        GameTooltip:AddLine(NS.HistoryRetention().."x retention. Change: Chat > History retention.",1,1,1,true);GameTooltip:Show()
    end)
    copy:SetScript("OnLeave",function(self) self:SetAlpha(.65);GameTooltip:Hide() end)
    copy:SetScript("OnClick",function() NS.CopyFrame(frame) end)
    frame.smyrnaCopyButton=copy
    if NS.InstallDirectSelection then NS.InstallDirectSelection(frame,copy) end
    local original = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if DB and Core.Readable(text) then
            -- A CVar can be nonempty without the client actually prefixing this line.
            -- Inspect the real prefix instead; no temporary strings or roster work.
            local timed=DB.timestamps and (text:match("^%[?%d%d?:%d%d") or text:match("^|c%x%x%x%x%x%x%x%x%[?%d%d?:%d%d"))
            if DB.timestamps and not timed then
                local second = math.floor(GetTime())
                if stampSecond ~= second then
                    stamp = "|cff"..Core.TimestampColor(DB).."[" .. date(DB.seconds and "%H:%M:%S" or "%H:%M") .. "]|r "
                    stampSecond = second
                end
                text = stamp .. text
            end
        end
        return original(self, text, ...)
    end
    -- Fallback for a modern client build before the public pre-send event.
    local box = frame.editBox
    if not EventRegistry and box and type(box.OnPreSendText) == "function" then
        hooksecurefunc(box, "OnPreSendText", function(self) PreSend(nil, self) end)
    end
end

local function HookFrames()
    for _, name in ipairs(CHAT_FRAMES or {}) do HookFrame(_G[name]) end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do HookFrame(_G["ChatFrame" .. i]) end
end

local function CreateCopyWindow()
    local frame = CreateFrame("Frame", "SmyrnaChatCopyWindow", UIParent, "BackdropTemplate")
    frame:SetSize(650, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG");frame:SetFrameLevel(150)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    local drag=CreateFrame("Button",nil,frame);drag:SetPoint("TOPLEFT",0,0);drag:SetSize(260,32);drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() frame:StartMoving() end)
    drag:SetScript("OnDragStop",function() frame:StopMovingOrSizing() end)
    Suite.StylePanel(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14);title:SetWidth(260);title:SetMaxLines(1)
    title:SetText("Chat history")
    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -40)
    help:SetText("Select text, then Ctrl+C. Ctrl+A selects this page. Escape closes.")
    frame.close=Suite.CloseButton(frame)
    local scroll,edit = Suite.CreateChatTextViewport(frame)
    scroll:SetPoint("TOPLEFT", 16, -65)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local measure=frame:CreateFontString(nil,"BACKGROUND","ChatFontNormal");measure:Hide()
    local function Reflow()
        local viewportWidth,viewportHeight=scroll:GetWidth(),scroll:GetHeight()
        local width=type(viewportWidth)=="number" and math.max(1,viewportWidth-2) or 595
        local minimum=type(viewportHeight)=="number" and math.max(1,viewportHeight) or 300
        edit:SetWidth(width)
        measure:SetWidth(math.max(1,width-4));measure:SetText(edit:GetText() or "")
        edit:SetHeight(math.max(minimum,measure:GetStringHeight()+12))
        scroll:UpdateScrollChildRect()
    end
    -- Native EditBox selection owns the mouse drag. Clicking only restores focus;
    -- re-highlighting here would destroy a partial or cross-message selection.
    -- Let the native EditBox own focus, caret and drag selection.
    edit:SetScript("OnEscapePressed",function() frame:Hide() end)
    edit:SetScript("OnTextChanged",Reflow)
    scroll:SetScript("OnSizeChanged",Reflow)
    local function Wheel(_,delta)
        local current,maximum=scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()
        if type(current)=="number" and type(maximum)=="number" and type(delta)=="number" then
            scroll:SetVerticalScroll(math.max(0,math.min(maximum,current-delta*42)))
        end
    end
    scroll:EnableMouseWheel(true);edit:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",Wheel);edit:SetScript("OnMouseWheel",Wheel)
    edit:SetScript("OnCursorChanged",function(_,_,y,_,height)
        local offset=scroll:GetVerticalScroll()
        if type(offset)~="number" or type(y)~="number" or type(height)~="number" then return end
        local position=-y;local visible=scroll:GetHeight()
        if position<offset then scroll:SetVerticalScroll(math.max(0,position))
        elseif type(visible)=="number" and position+height>offset+visible then
            scroll:SetVerticalScroll(position+height-visible)
        end
    end)
    frame:SetScript("OnHide",function()
        edit:ClearFocus();edit:SetText("");measure:SetText("")
        frame.source=nil;frame.offset=nil
    end)
    frame.edit,frame.scroll,frame.title,frame.Reflow=edit,scroll,title,Reflow
    UISpecialFrames[#UISpecialFrames+1]="SmyrnaChatCopyWindow"
    return frame
end

function NS.CloseHistory()
    if copyWindow then copyWindow:Hide() end
end

local function Performance()
    local api = C_AddOns or {}
    local updateMemory = api.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage
    local getMemory = api.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    if updateMemory and getMemory then
        updateMemory()
        Say(string.format("Memory: %.1f KB (WoW attribution; includes reusable Lua allocations).", getMemory(addonName)))
    end
    local updateCPU = api.UpdateAddOnCPUUsage or UpdateAddOnCPUUsage
    local getCPU = api.GetAddOnCPUUsage or GetAddOnCPUUsage
    if GetCVar("scriptProfile") == "1" and updateCPU and getCPU then
        updateCPU()
        Say(string.format("CPU: %.2f ms cumulative since profiling reset/login.", getCPU(addonName)))
    else Say("CPU profiling is off. See PERFORMANCE.md for a controlled in-game measurement.") end
end

local function Copy(index,sourceFrame,offset)
    local source = sourceFrame or (index and _G["ChatFrame" .. index]) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if not source or not source.GetNumMessages then Say("No chat window with that number."); return end
    local lines = {}
    local count = source:GetNumMessages()
    if (issecretvalue and issecretvalue(count)) or type(count)~="number" then return end
    offset=math.max(0,math.min(offset or 0,math.max(0,count-1)))
    local last=count-offset
    for i = math.max(1, last - 299), last do
        local text = source:GetMessageInfo(i)
        if Core.Readable(text) then lines[#lines + 1] = Core.Plain(text) end
    end
    if not copyWindow then copyWindow = CreateCopyWindow() end
    copyWindow.source=source;copyWindow.offset=offset
    if not rawget(copyWindow,"older") then
        local older=CreateFrame("Button",nil,copyWindow,"UIPanelButtonTemplate");older:SetSize(70,22);older:SetPoint("TOPRIGHT",-120,-12);older:SetText("Page up")
        older:SetScript("OnClick",function() Copy(nil,copyWindow.source,copyWindow.offset+300) end);copyWindow.older=older
        local newer=CreateFrame("Button",nil,copyWindow,"UIPanelButtonTemplate");newer:SetSize(70,22);newer:SetPoint("TOPRIGHT",-40,-12);newer:SetText("Page down")
        newer:SetScript("OnClick",function() Copy(nil,copyWindow.source,math.max(0,copyWindow.offset-300)) end);copyWindow.newer=newer
    end
    if not rawget(copyWindow,"topButton") then
        local top=CreateFrame("Button",nil,copyWindow,"UIPanelButtonTemplate");top:SetSize(55,22);top:SetPoint("TOPRIGHT",-260,-12);top:SetText("Top")
        top:SetScript("OnClick",function() local s=copyWindow.source;Copy(nil,s,math.max(0,s:GetNumMessages()-300)) end);copyWindow.topButton=top
        local bottom=CreateFrame("Button",nil,copyWindow,"UIPanelButtonTemplate");bottom:SetSize(65,22);bottom:SetPoint("TOPRIGHT",-190,-12);bottom:SetText("Bottom")
        bottom:SetScript("OnClick",function() local s=copyWindow.source;Copy(nil,s,0);copyWindow.scroll:SetVerticalScroll(copyWindow.scroll:GetVerticalScrollRange()) end);copyWindow.bottomButton=bottom
    end
    copyWindow.older:SetEnabled(last>300);copyWindow.newer:SetEnabled(offset>0)
    copyWindow.title:SetText(count==0 and "Chat history - empty" or ("Chat history - "..math.max(1,last-299).."-"..last.." / "..count))
    if NS.MessageEditor then NS.MessageEditor:Hide() end
    copyWindow:Show()
    copyWindow.edit:SetText(table.concat(lines,"\n"))
    copyWindow.Reflow()
    copyWindow.edit:SetFocus()
    -- No automatic selection: native mouse drag and Ctrl+A own highlighting.
    -- Focusing can move the native caret; open the page at the top.
    copyWindow.scroll:SetVerticalScroll(0)

end

NS.CopyFrame=function(frame) Copy(nil,frame) end

local function Toggle(field, value)
    value = string.lower(Core.Trim(value))
    if value == "on" then DB[field] = true
    elseif value == "off" then DB[field] = false
    elseif value == "" then DB[field] = not DB[field]
    else Say("Use on or off."); return end
    stampSecond = nil
    if NS.SyncSettings then NS.SyncSettings() end
    Say(field .. ": " .. (DB[field] and "on" or "off") .. ".")
end

local function Command(input)
    if not DB then return end
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd)
    if cmd == "options" or cmd == "settings" then
        NS.OpenSettings()
    elseif cmd == "copy" then
        local number = rest ~= "" and tonumber(rest) or nil
        if rest ~= "" and (not number or number < 1 or number > 100 or number % 1 ~= 0) then
            Say("Use /sc copy or /sc copy 1."); return
        end
        Copy(number)
    elseif cmd == "perf" then Performance()
    elseif cmd == "time" then Toggle("timestamps", rest)
    elseif cmd == "seconds" then Toggle("seconds", rest)
    elseif cmd == "status" then
        Say("Timestamps " .. (DB.timestamps and "on" or "off") .. "; seconds " .. (DB.seconds and "on" or "off") .. ".")
    else
        Say("/sc options - open settings")
        Say("/sc copy [window number]")
        Say("/sc time on/off | seconds on/off | status")
        Say("/sc copy | time | seconds | perf")
    end
end

NS.Command = Command
NS.GetDB = function() return DB end
function NS.SetTimestampColor(hex)
    if not DB or type(hex)~="string" or #hex~=6 or not hex:match("^%x+$") then return false end
    DB.timestampColor=string.lower(hex);stampSecond=nil
    if NS.SyncTimestampColor then NS.SyncTimestampColor() end
    return true
end
function NS.OpenTimestampColor()
    local picker=ColorPickerFrame
    if not picker or not picker.GetColorRGB then Say("The game's color picker is unavailable.");return false end
    local original=Core.TimestampColor(DB)
    local r,g,b=Core.ColorRGB(original)
    local function Update()
        local red,green,blue=picker:GetColorRGB()
        local hex=Core.RGBHex(red,green,blue)
        if hex then NS.SetTimestampColor(hex) end
    end
    local function Cancel() NS.SetTimestampColor(original) end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({r=r,g=g,b=b,hasOpacity=false,swatchFunc=Update,cancelFunc=Cancel})
    elseif picker.SetColorRGB then
        picker:Hide();picker.func=nil;picker.cancelFunc=nil;picker:SetColorRGB(r,g,b)
        picker.hasOpacity=false;picker.func=Update;picker.cancelFunc=Cancel;picker:Show()
    else return false end
    return true
end
NS.ValidLabel = ValidLabel

SLASH_SMYRNACHAT1 = "/smyrnachat"
SLASH_SMYRNACHAT2 = "/sc"
SlashCmdList.SMYRNACHAT = Command

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name=="SmyrnaSuite" then
        if type(SmyrnaChatDB) ~= "table" then SmyrnaChatDB = {} end
        DB = SmyrnaChatDB
        DB.nicknames=nil;DB.nicknameDisabled=nil;DB.aliases=nil
        for _,key in ipairs({"people","muted","notes","showNotes","class","guild","location","level","details","professions"}) do DB[key]=nil end
        if DB.timestamps == nil then DB.timestamps = true end
        DB.timestampColor=Core.TimestampColor(DB)
        if DB.seconds == nil then DB.seconds = false end
        if DB.directCopy==nil then DB.directCopy=true end
        DB.speak=nil
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if NS.ConfigureMinimap then NS.ConfigureMinimap() end
        HookFrames()
        if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", HookFrames) end
        if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", HookFrames) end
        self:UnregisterEvent("PLAYER_LOGIN")
        Say("Ready. /sc options for settings.")
    end
end)

end chunk(name,Module) end

-- Internal module source: Settings.lua
do local function chunk(...)
local _, NS = ...
local window

local function Build()
    local frame = CreateFrame("Frame", "SmyrnaChatSettingsWindow", UIParent, "BackdropTemplate")
    frame:SetSize(920, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2);frame.SuiteCloseButton=close
    local function Label(text, x, y, font)
        local label = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetText(text)
        return label
    end
    Label("Smyrna Chat - Settings", 20, -18, "GameFontNormalLarge")
    Label("Changes apply immediately. No reload needed.", 20, -44)
    local checks = {}
    local function Check(field, command, text, x, y)
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", x, y)
        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(text)
        check:SetScript("OnClick", function(self)
            NS.Command(command .. (self:GetChecked() and " on" or " off"))
        end)
        checks[field] = check
    end
    Check("timestamps", "time", "Timestamps", 18, -68)
    Check("seconds", "seconds", "Include seconds", 280, -68)
    local direct=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate");direct:SetPoint("TOPLEFT",18,-98)
    local directLabel=direct:CreateFontString(nil,"OVERLAY","GameFontHighlight");directLabel:SetPoint("LEFT",direct,"RIGHT",2,0);directLabel:SetText("Enable message selection and copying")
    direct:SetScript("OnClick",function(self) NS.SetDirectCopy(self:GetChecked()) end);checks.directCopy=direct
    local function Button(text, x, y, action)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(150,25);button:SetPoint("TOPLEFT",x,y);button:SetText(text);button:SetScript("OnClick",action)
        return button
    end
    local timestampColor=Button("Color",170,-74,function() NS.OpenTimestampColor() end);timestampColor:SetSize(90,25)
    local swatch=timestampColor:CreateTexture(nil,"ARTWORK");swatch:SetSize(12,12);swatch:SetPoint("LEFT",6,0)
    local resetColor=Button("Reset",445,-74,function() NS.SetTimestampColor("888888") end);resetColor:SetSize(70,25)
    Button("History", 20, -145, function() NS.Command("copy") end)
    Button("Report memory / CPU", 195, -145, function() NS.Command("perf") end)
    Label("Right-click a message, select text, then Ctrl+C. History browses older messages.",20,-190)
    Label("Chat preview", 560, -68, "GameFontNormalLarge")
    Label("Sample data only. Nothing is sent to chat.", 560, -96)
    local preview = Label("", 560, -126, "ChatFontNormal")
    preview:SetWidth(330)
    preview:SetJustifyH("LEFT")
    local function UpdatePreview()
        preview:SetText(NS.BuildPreview(NS.GetDB()))
    end
    NS.SyncTimestampColor=function()
        local r,g,b=NS.Core.ColorRGB(NS.Core.TimestampColor(NS.GetDB()));swatch:SetColorTexture(r,g,b,1);UpdatePreview()
    end
    frame:SetScript("OnShow", function()
        local db = NS.GetDB()
        for field, check in pairs(checks) do check:SetChecked(db[field] and true or false) end
        local r,g,b=NS.Core.ColorRGB(NS.Core.TimestampColor(db));swatch:SetColorTexture(r,g,b,1)
        UpdatePreview()
    end)
    frame:SetScript("OnHide", function()
    end)
    if NS.BuildHistorySettings then NS.BuildHistorySettings(frame) end
    if NS.BuildTimeZones then NS.BuildTimeZones(frame) end
    UISpecialFrames[#UISpecialFrames + 1] = "SmyrnaChatSettingsWindow"
    return frame
end

function NS.SyncSettings()
    if window and window:IsShown() then
        local script = window:GetScript("OnShow")
        if script then script(window) end
    end
end

function NS.OpenSettings()
    if not window then window = Build() end
    if UIParent and UIParent.GetHeight then
        window:SetScale(math.min(1, (UIParent:GetHeight() - 40) / 740, (UIParent:GetWidth() - 40) / 920))
    end
    window:Show()
    -- A newly created frame may already be shown before OnShow is installed.
    local script = window:GetScript("OnShow")
    if script then script(window) end
    return window
end

end chunk(name,Module) end

-- Internal module source: Preview.lua
do local function chunk(...)
local _, NS = ...
local samples={
    {"Jaina","MAGE","Portals are ready."},
    {"Tyrande","PRIEST","Elune guide us."},
    {"Illidan","DEMONHUNTER","You are not prepared!"},
    {"Malfurion","DRUID","The forest calls."},
    {"Garrosh","WARRIOR","For the Horde!"},
    {"Thrall","SHAMAN","The elements are with us."},
    {"Gul'dan","WARLOCK","Power has a price."},
    {"Rexxar","HUNTER","The hunt begins."},
    {"Tirion","PALADIN","Stand with the Light."},
}
function NS.BuildPreview(options)
    options=options or {}
    local prefix=options.timestamps and ("|cff"..NS.Core.TimestampColor(options)..(options.seconds and "[12:34:56]" or "[12:34]").."|r ") or ""
    local lines={}
    for _,sample in ipairs(samples) do
        local color=C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(sample[2])
        color=color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[sample[2]])
        local hex=sample[2]=="DEMONHUNTER" and "a330c9" or (color and NS.Core.RGBHex(color.r,color.g,color.b) or "ffffff")
        lines[#lines+1]=prefix.."|cff"..hex.."|Hplayer:"..sample[1].."-Preview:1|h["..sample[1].."]|h|r: "..sample[3]
    end
    return table.concat(lines,"\n")
end

end chunk(name,Module) end


-- Internal module source: ChatMinimap.lua
do local function chunk(...)
local _,NS=...
local icon
function NS.ConfigureMinimap()
end

end chunk(name,Module) end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
