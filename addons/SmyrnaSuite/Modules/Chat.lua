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
    text = text:gsub("|K.-|k", "[Battle.net]")
    text = text:gsub("|cn[^:]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|W.-|w", "")
    return text
end

function Core.MessageBody(raw)
    if not Core.Readable(raw) then return "" end
    local plain = Core.Plain(raw)
    local noTime = plain:gsub("^%s*%[?%d%d?:%d%d:%d%d%]?%s*", "", 1)
    if noTime == plain then noTime = plain:gsub("^%s*%[?%d%d?:%d%d%]?%s*", "", 1) end
    local s, e = raw:find("|HBN?player:.-|h.-|h")
    if s then
        local before = Core.Plain(raw:sub(1, s - 1))
        local stripped = before:gsub("^%s*%[?%d%d?:%d%d:%d%d%]?%s*", "", 1)
        if stripped == before then stripped = before:gsub("^%s*%[?%d%d?:%d%d%]?%s*", "", 1) end
        before = stripped
        while before:match("^%s*%b[]") do before = before:gsub("^%s*%b[]%s*", "", 1) end
        before = before:gsub("^%s*[Tt]o%s+", "", 1):gsub("^%s+", "")
        if before == "" then
            local after = raw:sub(e + 1):gsub("^|r", "")
            local body = after:match("^%s*:%s*(.+)$")
                or after:match("^%s+says:%s*(.+)$")
                or after:match("^%s+yells:%s*(.+)$")
                or after:match("^%s+whispers:%s*(.+)$")
            if body then
                local clean = Core.Trim(Core.Plain(body))
                if clean ~= "" then return clean end
            end
        end
    end
    local body = noTime:match("^%s*To%s+%b[]%s*:%s*(.+)$")
    if not body then
        local stripped = noTime
        while stripped:match("^%s*%b[]%s*%b[]") do
            stripped = stripped:gsub("^%s*%b[]%s*", "", 1)
        end
        body = stripped:match("^%s*%b[]%s*:%s*(.+)$")
    end
    if not body then
        body = noTime:match("^%s*[^:%[%]]+%s+says:%s*(.+)$")
            or noTime:match("^%s*[^:%[%]]+%s+yells:%s*(.+)$")
            or noTime:match("^%s*[^:%[%]]+%s+whispers:%s*(.+)$")
            or noTime:match("^%s*To%s+[^:%[%]]+%s*:%s*(.+)$")
    end
    if body then
        local clean = Core.Trim(body)
        if clean ~= "" then return clean end
    end
    local fallback = Core.Trim(noTime)
    return fallback ~= "" and fallback or plain
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
function Core.TimestampStamp(options,clockText)
    local hex=Core.TimestampColor(options)
    if options and options.timestampOutline~=false then
        local r,g,b=Core.ColorRGB(hex)
        local lum=0.299*r+0.587*g+0.114*b
        if lum<0.48 then
            local lift=(0.48-lum)*0.75
            hex=Core.RGBHex(r+(1-r)*lift,g+(1-g)*lift,b+(1-b)*lift) or hex
        end
        return "|cffffffff[|r|cff"..hex..clockText.."|r|cffffffff]|r "
    end
    return "|cff"..hex.."["..clockText.."]|r "
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
local linePills = setmetatable({}, { __mode = "k" })
local pendingFrames = setmetatable({}, { __mode = "k" })
local copyButtons = setmetatable({}, { __mode = "k" })
NS.CopyButtons = copyButtons
local driver = CreateFrame("Frame")

local function Say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffedbd72Smyrna Chat:|r " .. text)
end

local function ValidLabel(text)
    return text ~= "" and #text <= 48 and not text:find("[%c|%[%]]")
end

local function UpdateTimestampMarkers(frame)
    if not frame or not DB or (frame.IsForbidden and frame:IsForbidden()) then return end
    local visible=rawget(frame,"visibleLines")
    if type(visible)~="table" then return end
    local show=DB.timestamps and DB.timestampOutline~=false
    local pillW=DB.seconds and 66 or 48
    local host=(frame.FontStringContainer and frame.FontStringContainer.CreateTexture) and frame.FontStringContainer or frame
    local fTop=frame.GetTop and frame:GetTop()
    local fBot=frame.GetBottom and frame:GetBottom()
    if issecretvalue and (issecretvalue(fTop) or issecretvalue(fBot)) then fTop,fBot=nil,nil end
    if type(fTop)~="number" then fTop=nil end
    if type(fBot)~="number" then fBot=nil end
    for i=1,#visible do
        local line=visible[i]
        if line then
            local pill=linePills[line]
            if show then
                if not pill then
                    pill=host:CreateTexture(nil,"BACKGROUND",nil,1)
                    pill:SetPoint("TOPLEFT",line,"TOPLEFT",-2,1)
                    pill:SetPoint("BOTTOMLEFT",line,"BOTTOMLEFT",-2,-1)
                    Suite.ApplyGradient(pill,"HORIZONTAL",0.02,0.02,0.04,0.68,0.02,0.02,0.04,0.12)
                    linePills[line]=pill
                    if hooksecurefunc then
                        hooksecurefunc(line,"SetAlpha",function(_,a) if pill and Suite.Public(a) and type(a)=="number" then pill:SetAlpha(a) end end)
                        hooksecurefunc(line,"Hide",function() if pill then pill:Hide() end end)
                    end
                end
                local txt=line.GetText and line:GetText()
                local isShown=line.IsShown and line:IsShown()
                local lTop=line.GetTop and line:GetTop()
                local lBot=line.GetBottom and line:GetBottom()
                if issecretvalue and (issecretvalue(lTop) or issecretvalue(lBot)) then lTop,lBot=nil,nil end
                local inBounds=(not fTop or type(lTop)~="number" or lTop<=fTop+2) and (not fBot or type(lBot)~="number" or lBot>=fBot-2)
                local hasStamp=false
                if isShown and inBounds and Core.Readable(txt) and txt~="" then
                    local b1=txt:byte(1)
                    if b1==91 or b1==124 or (b1 and b1>=48 and b1<=57) then
                        hasStamp=(txt:match("^|c%x%x%x%x%x%x%x%x%[|r|c%x%x%x%x%x%x%x%x%d%d?:%d%d") or txt:match("^|c%x%x%x%x%x%x%x%x%[?%d%d?:%d%d") or txt:match("^%[?%d%d?:%d%d"))~=nil
                    end
                end
                if hasStamp then
                    pill:SetWidth(pillW)
                    local la=line.GetAlpha and line:GetAlpha() or 1
                    pill:SetAlpha((Suite.Public(la) and type(la)=="number") and la or 1)
                    pill:Show()
                else
                    pill:Hide()
                end
            elseif pill then
                pill:Hide()
            end
        end
    end
end
local function FlushPendingMarkers()
    refreshPending=false
    for frame in pairs(pendingFrames) do
        pendingFrames[frame]=nil
        UpdateTimestampMarkers(frame)
    end
end
local function QueueTimestampMarkers(frame)
    if not frame then return end
    pendingFrames[frame]=true
    if refreshPending then return end
    refreshPending=true
    if C_Timer and C_Timer.After then C_Timer.After(0,FlushPendingMarkers) else FlushPendingMarkers() end
end
local function RefreshAllMarkers()
    for frame in pairs(hooked) do QueueTimestampMarkers(frame) end
end
NS.RefreshTimestampMarkers=RefreshAllMarkers

local function HookFrame(frame)
    if not frame or hooked[frame] or (frame.IsForbidden and frame:IsForbidden()) then return end
    hooked[frame] = true
    if frame.SetShadowColor then frame:SetShadowColor(0,0,0,1) end
    if frame.SetShadowOffset then frame:SetShadowOffset(1.5,-1.5) end
    local copy=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    copy:SetSize(42,18);copy:SetPoint("BOTTOMRIGHT",frame,"TOPRIGHT",-50,6)
    copy:SetText("History");copy:SetWidth(55);copy:SetAlpha(.65)
    copy:SetScript("OnEnter",function(self)
        self:SetAlpha(1)
        if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Chat history")
        GameTooltip:AddLine(NS.HistoryRetention().."x retention. Change: Chat > History retention.",1,1,1,true);GameTooltip:Show()
    end)
    copy:SetScript("OnLeave",function(self)
        self:SetAlpha(.65)
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
    end)
    copy:SetScript("OnClick",function() NS.CopyFrame(frame) end)
    copyButtons[frame]=copy
    if NS.InstallDirectSelection then NS.InstallDirectSelection(frame,copy) end
    if hooksecurefunc then
        for _,fn in ipairs({"ScrollUp","ScrollDown","ScrollToBottom","SetScrollOffset","PageUp","PageDown"}) do
            if frame[fn] then hooksecurefunc(frame,fn,function() QueueTimestampMarkers(frame) end) end
        end
    end
    local original = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if DB and Core.Readable(text) then
            -- Fast byte check avoids regex matching on ~95% of incoming chat lines.
            if DB.timestamps then
                local b1=text:byte(1)
                local timed=(b1==91 or b1==124 or (b1 and b1>=48 and b1<=57)) and (text:match("^%[?%d%d?:%d%d") or text:match("^|c%x%x%x%x%x%x%x%x%[?%d%d?:%d%d") or text:match("^|c%x%x%x%x%x%x%x%x%[|r|c%x%x%x%x%x%x%x%x%d%d?:%d%d"))
                if not timed then
                    local second = math.floor(GetTime())
                    if stampSecond ~= second then
                        stamp = Core.TimestampStamp(DB, date(DB.seconds and "%H:%M:%S" or "%H:%M"))
                        stampSecond = second
                    end
                    text = stamp .. text
                end
            end
        end
        local res=original(self, text, ...)
        QueueTimestampMarkers(self)
        return res
    end
    QueueTimestampMarkers(frame)
end

local function HookFrames()
    for _, name in ipairs(CHAT_FRAMES or {}) do HookFrame(_G[name]) end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do HookFrame(_G["ChatFrame" .. i]) end
end

local PAGE_SIZE = 300

local function CreateCopyWindow()
    local frame=CreateFrame("Frame","SmyrnaChatCopyWindow",UIParent,"BackdropTemplate")
    frame:SetSize(660,468);frame:SetPoint("CENTER");frame:SetFrameStrata("FULLSCREEN_DIALOG");frame:SetFrameLevel(150);frame:SetClampedToScreen(true)
    frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
    frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    Suite.StylePanel(frame,true);Suite.HeaderStrip(frame,42);frame.close=Suite.CloseButton(frame)
    local title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-13);title:SetText("Smyrna Chat History");title:SetTextColor(1,.86,.48)
    local help=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");help:SetPoint("TOPLEFT",16,-48);help:SetText("Scroll, drag to select, Ctrl+C to copy  ·  Ctrl+A selects all  ·  Esc closes.");help:SetTextColor(.70,.75,.84)
    local boxCard=CreateFrame("Frame",nil,frame,"BackdropTemplate")
    boxCard:SetPoint("TOPLEFT",14,-68);boxCard:SetPoint("BOTTOMRIGHT",-14,48)
    Suite.StyleCard(boxCard,.055,.064,.088)
    -- Native configuration 4 from the user's successful five-way test. Keep
    -- native text sizing/cursor/scroll handling; do not install custom versions.
    local scroll=CreateFrame("ScrollFrame",nil,frame,"InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",22,-76);scroll:SetSize(592,332)
    scroll.hideCharCount=true;if scroll.CharCount then scroll.CharCount:Hide() end
    if InputScrollFrame_OnLoad then InputScrollFrame_OnLoad(scroll) end
    local edit=scroll.EditBox
    edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal);edit:SetMaxLetters(0);edit:SetWidth(572)
    -- Match the successful native selection test: the scroll child needs an
    -- explicit starting height and a visible top-left anchor before SetText.
    edit:SetHeight(332);edit:ClearAllPoints();edit:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,0)
    edit:SetTextColor(1,1,1,1);edit:SetAlpha(1);edit:Show()
    edit:EnableMouse(true)
    edit:SetScript("OnEscapePressed",function() frame:Hide() end)
    -- Preserve the template's OnTextChanged, OnCursorChanged and OnUpdate.
    -- Its ScrollBar controls the real native scroll-child offset.
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(_,delta)
        local current,maximum=scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()
        if type(current)=="number" and type(maximum)=="number" then scroll:SetVerticalScroll(math.max(0,math.min(maximum,current-delta*42))) end
    end)
    edit:EnableMouseWheel(true);edit:SetScript("OnMouseWheel",scroll:GetScript("OnMouseWheel"))
    local older=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");older:SetSize(76,24);older:SetPoint("BOTTOMLEFT",16,14);older:SetText("Older");Suite.StyleButton(older)
    local newer=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");newer:SetSize(76,24);newer:SetPoint("LEFT",older,"RIGHT",8,0);newer:SetText("Newer");Suite.StyleButton(newer)
    local pageInfo=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");pageInfo:SetPoint("LEFT",newer,"RIGHT",12,0);pageInfo:SetTextColor(.82,.86,.92)
    frame:SetScript("OnHide",function()
        frame.generation=(frame.generation or 0)+1
        edit.handleCursorChange=false;edit.cursorOffset=0
        edit:ClearFocus();edit:SetText("")
        scroll:SetVerticalScroll(0);frame.source=nil
    end)
    frame.edit,frame.scroll,frame.title,frame.older,frame.newer,frame.pageInfo=edit,scroll,title,older,newer,pageInfo
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
        Say(string.format("Memory: %.1f KB (WoW attribution; includes reusable Lua allocations).", getMemory("SmyrnaSuite") or 0))
    end
    local updateCPU = api.UpdateAddOnCPUUsage or UpdateAddOnCPUUsage
    local getCPU = api.GetAddOnCPUUsage or GetAddOnCPUUsage
    if GetCVar("scriptProfile") == "1" and updateCPU and getCPU then
        updateCPU()
        Say(string.format("CPU: %.2f ms cumulative since profiling reset/login.", getCPU("SmyrnaSuite") or 0))
    else Say("CPU profiling is off. See PERFORMANCE.md for a controlled in-game measurement.") end
end

local function MessageCount(frame)
    if not frame or not frame.GetNumMessages then return nil end
    local n=frame:GetNumMessages()
    if (issecretvalue and issecretvalue(n)) or type(n)~="number" then return nil end
    return n
end

local function Copy(index,sourceFrame,pageEnd)
    local source=sourceFrame or (index and _G["ChatFrame"..index]) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if not source or not source.GetNumMessages then Say("No chat window with that number.");return end
    local count=MessageCount(source)
    -- If opened generically (e.g. from Settings or /sc copy) while an empty tab
    -- or Combat Log is selected, fall back to the main chat window when it has messages.
    if not sourceFrame and not index and source~=DEFAULT_CHAT_FRAME and (not count or count==0) then
        local fallbackCount=MessageCount(DEFAULT_CHAT_FRAME)
        if fallbackCount and fallbackCount>0 then source=DEFAULT_CHAT_FRAME;count=fallbackCount end
    end
    if not count then Say("Chat history is temporarily restricted by the client.");return end
    if not copyWindow then copyWindow=CreateCopyWindow() end
    if NS.MessageEditor then NS.MessageEditor:Hide() end
    local window=copyWindow
    window.generation=(window.generation or 0)+1;local token=window.generation
    local finish=math.max(0,math.min(count,pageEnd or count))
    local start=finish>0 and math.max(1,finish-PAGE_SIZE+1) or 1
    window.source=source;window.pageStart=start;window.pageEnd=finish
    window.older:SetEnabled(start>1);window.newer:SetEnabled(finish<count)
    window.older:SetScript("OnClick",function() if window.source and window.pageStart>1 then Copy(nil,window.source,window.pageStart-1) end end)
    window.newer:SetScript("OnClick",function() if window.source then Copy(nil,window.source,window.pageEnd+PAGE_SIZE) end end)
    local lines={};local skipped=0
    if finish>=start then
        for i=start,finish do
            local text=source:GetMessageInfo(i)
            if Core.Readable(text) and text~="" then lines[#lines+1]=Core.Plain(text)
            elseif text~=nil then skipped=skipped+1 end
        end
    end
    -- Fallback to currently visible rendered lines if GetMessageInfo returned nothing readable.
    if #lines==0 and not pageEnd then
        local visible=rawget(source,"visibleLines")
        if type(visible)=="table" then
            for i=#visible,1,-1 do
                local line=visible[i]
                local text=line and line.GetText and line:GetText()
                if Core.Readable(text) and text~="" then lines[#lines+1]=Core.Plain(text) end
            end
        end
    end
    local total=#lines
    local body=table.concat(lines,"\n")
    window:Show()
    window.edit.handleCursorChange=false;window.edit.cursorOffset=0
    window.edit:SetHeight(math.max(324,window.scroll:GetHeight() or 324))
    window.edit:SetText(body)
    -- SetText moves the caret to the end and triggers InputScrollFrame's
    -- ScrollingEdit_OnUpdate on the next frame. Clear cursorOffset and re-pin
    -- scroll both immediately and after the next layout pass so text stays visible.
    window.edit:SetCursorPosition(0)
    window.edit.handleCursorChange=false;window.edit.cursorOffset=0
    window.title:SetText("Chat history - "..total.." messages")
    if total==0 and skipped>0 then
        window.pageInfo:SetText(skipped.." restricted messages hidden by client")
    elseif finish>0 then
        window.pageInfo:SetText("Showing "..start.."-"..finish.." of "..count..(skipped>0 and (" ("..skipped.." restricted)") or ""))
    else
        window.pageInfo:SetText("No messages in this chat window")
    end
    window.scroll:UpdateScrollChildRect()
    window.scroll:SetVerticalScroll(0)
    C_Timer.After(0,function()
        if not window:IsShown() or window.generation~=token then return end
        window.edit.handleCursorChange=false;window.edit.cursorOffset=0
        window.scroll:UpdateScrollChildRect()
        window.scroll:SetVerticalScroll(0)
    end)
end

NS.CopyFrame=function(frame) Copy(nil,frame) end

local function Toggle(field, value)
    value = string.lower(Core.Trim(value))
    if value == "on" then DB[field] = true
    elseif value == "off" then DB[field] = false
    elseif value == "" then DB[field] = not DB[field]
    else Say("Use on or off."); return end
    stampSecond = nil
    if NS.RefreshTimestampMarkers then NS.RefreshTimestampMarkers() end
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
    elseif cmd == "outline" then Toggle("timestampOutline", rest)
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
    if event == "ADDON_LOADED" then
        if not Suite.Public(name) or name~="SmyrnaSuite" then return end
        if type(SmyrnaChatDB) ~= "table" then SmyrnaChatDB = {} end
        DB = SmyrnaChatDB
        DB.nicknames=nil;DB.nicknameDisabled=nil;DB.aliases=nil
        for _,key in ipairs({"people","muted","notes","showNotes","class","guild","location","level","details","professions"}) do DB[key]=nil end
        if DB.timestamps == nil then DB.timestamps = true end
        DB.timestampColor=Core.TimestampColor(DB)
        if DB.seconds == nil then DB.seconds = false end
        if DB.timestampOutline == nil then DB.timestampOutline = true end
        if DB.directCopy==nil then DB.directCopy=true end
        DB.speak=nil
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        HookFrames()
        if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", HookFrames) end
        if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", HookFrames) end
        self:UnregisterEvent("PLAYER_LOGIN")
        self:SetScript("OnEvent", nil)
    end
end)

end chunk(name,Module) end

-- Internal module source: Settings.lua
do local function chunk(...)
local _, NS = ...
local window

local function Build()
    local frame = CreateFrame("Frame", "SmyrnaChatSettingsWindow", UIParent, "BackdropTemplate")
    frame:SetSize(920, 524)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Suite.StylePanel(frame, true)
    local close = Suite.CloseButton(frame); frame.SuiteCloseButton = close
    local function Label(text, x, y, font)
        local label = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetText(text)
        return label
    end
    local title = Label("Smyrna Chat - Settings", 20, -18, "GameFontNormalLarge")
    title:SetTextColor(1, .86, .48)
    Label("Changes apply immediately. No reload needed.", 20, -42)
    Suite.OptionSection(frame, "Display & Timestamps", 20, -56, 495)
    Suite.OptionSection(frame, "Channels & Filters", 20, -288, 870)
    local checks = {}
    local function Check(field, command, text, tipBody, x, y)
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", x, y)
        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(text)
        check:SetScript("OnClick", function(self)
            NS.Command(command .. (self:GetChecked() and " on" or " off"))
        end)
        Suite.AttachTooltip(check, text, tipBody, label)
        checks[field] = check
    end
    Check("timestamps", "time", "Timestamps", "Prefix incoming chat messages with local or world timestamps.", 18, -68)
    Check("seconds", "seconds", "Seconds", "Display HH:MM:SS instead of HH:MM in chat timestamps.", 280, -68)
    local direct=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate");direct:SetPoint("TOPLEFT",18,-98)
    local directLabel=direct:CreateFontString(nil,"OVERLAY","GameFontHighlight");directLabel:SetPoint("LEFT",direct,"RIGHT",2,0);directLabel:SetText("Right-click copy")
    direct:SetScript("OnClick",function(self) NS.SetDirectCopy(self:GetChecked()) end);checks.directCopy=direct
    Suite.AttachTooltip(direct,"Right-click copy","Right-click any chat message to open a pre-selected copy box (Ctrl+C copies and closes automatically).",directLabel)
    Check("timestampOutline", "outline", "Dark backing", "Adds a subtle dark backing strip and brackets behind timestamps so any color stays readable over bright terrain or water.", 280, -98)
    local function Button(text, x, y, action)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(150,25);button:SetPoint("TOPLEFT",x,y);button:SetText(text);button:SetScript("OnClick",action)
        return button
    end
    local timestampColor=Button("Color",170,-74,function() NS.OpenTimestampColor() end);timestampColor:SetSize(90,25)
    local swatchBorder=timestampColor:CreateTexture(nil,"OVERLAY",nil,1);swatchBorder:SetSize(14,14);swatchBorder:SetPoint("LEFT",5,0);swatchBorder:SetColorTexture(1,1,1,.92)
    local swatch=timestampColor:CreateTexture(nil,"OVERLAY",nil,2);swatch:SetSize(12,12);swatch:SetPoint("LEFT",6,0)
    local resetColor=Button("Reset",445,-74,function() NS.SetTimestampColor("888888") end);resetColor:SetSize(70,25)
    Button("History", 20, -145, function() NS.Command("copy") end)
    Button("Memory usage", 195, -145, function() NS.Command("perf") end)
    local copyHelp = Label("Right-click any chat message to select its text (Ctrl+C to copy). Click History to browse older chat.", 20, -184)
    copyHelp:SetWidth(520); copyHelp:SetJustifyH("LEFT")
    Label("Chat preview", 565, -68, "GameFontNormalLarge")
    Label("Live preview (nothing is sent to chat).", 565, -94)
    local preview = Label("", 565, -118, "ChatFontNormal")
    preview:SetWidth(335)
    preview:SetJustifyH("LEFT")
    local function UpdatePreview()
        local db = NS.GetDB()
        swatchBorder:SetShown(db and db.timestampOutline ~= false)
        preview:SetText(NS.BuildPreview(db))
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
    local created=false
    if not window then window = Build(); created = true end
    if UIParent and UIParent.GetHeight then
        local uw,uh=UIParent:GetWidth(),UIParent:GetHeight()
        if Suite.Public(uw) and Suite.Public(uh) and type(uw)=="number" and type(uh)=="number" and uw>60 and uh>60 then
            window:SetScale(math.min(1, (uh - 40) / 524, (uw - 40) / 920))
        end
    end
    local wasShown = window:IsShown()
    window:Show()
    if created or wasShown then
        local script = window:GetScript("OnShow")
        if script then script(window) end
    end
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
    local prefix=options.timestamps and NS.Core.TimestampStamp(options,options.seconds and "12:34:56" or "12:34") or ""
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


Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
