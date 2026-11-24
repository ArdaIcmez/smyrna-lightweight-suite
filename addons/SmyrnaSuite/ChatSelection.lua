local _,Suite=...
local Chat=Suite.Modules.SmyrnaChat
if not Chat then return end
local frames=setmetatable({},{__mode='k'})
local hoveredLinkFrame
function Chat.HistoryRetention()
 local db=Chat.GetDB()
 local value=db and db.historyRetention
 return (value==50 or value==100 or value==1000) and value or 10
end
-- Native PackageEntry + CircularBuffer benchmark: 80-400 byte unique messages,
-- three numeric extra arguments. Rounded full-buffer range; not live RAM telemetry.
function Chat.HistoryMemoryEstimate(value,frame)
 local baseline,windows=0,0
 if frame and type(frames[frame])=='number' then baseline=frames[frame];windows=1
 else for _,limit in pairs(frames) do if type(limit)=='number' then baseline=baseline+limit;windows=windows+1 end end end
 if baseline==0 then return end
 local messages=baseline*value
 return messages*700/1048576,messages*1050/1048576,messages,windows
end
local function MemoryText(value)
 local low,high,messages,windows=Chat.HistoryMemoryEstimate(value)
 if not low then return 'Memory estimate appears once chat finishes loading.' end
 return string.format('Estimated max memory when full: ~%.1f-%.1f MB across %d chat tabs (%d lines).',low,high,windows,messages)
end
local function ApplyRetention(frame)
 if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
 local base=frames[frame];local value=Chat.HistoryRetention()
 if type(base)=='number' and frame.SetMaxLines then
  local target=base*value
  local current=frame.GetMaxLines and frame:GetMaxLines()
  if (issecretvalue and issecretvalue(current)) or current~=target then frame:SetMaxLines(target) end
 end
 local button=Chat.CopyButtons and Chat.CopyButtons[frame]
 if button then button:SetText('History');button:SetWidth(55) end
end
function Chat.SetHistoryRetention(value)
 local db=Chat.GetDB()
 if not db or (value~=10 and value~=50 and value~=100 and value~=1000) then return false end
 db.historyRetention=value
 for frame in pairs(frames) do ApplyRetention(frame) end
 if Chat.RefreshHistorySettings then Chat.RefreshHistorySettings() end
 return true
end
function Chat.BuildHistorySettings(parent)
 local title=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');title:SetPoint('TOPLEFT',365,-126);title:SetText('History retention')
 local buttons={}
 local estimate=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');estimate:SetPoint('TOPLEFT',20,-220);estimate:SetWidth(520);estimate:SetJustifyH('LEFT')
 local function Refresh()
  local cur=Chat.HistoryRetention()
  estimate:SetText(MemoryText(cur))
  for value,b in pairs(buttons) do b:SetText((cur==value and '|cff78d49b' or '')..value..'x'..(cur==value and '|r' or '')) end
 end
 Chat.RefreshHistorySettings=Refresh
 local x=365
 for _,entry in ipairs({{10,38},{50,38},{100,44},{1000,52}}) do
  local value,width=entry[1],entry[2]
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(width,25);b:SetPoint('TOPLEFT',x,-145);buttons[value]=b;x=x+width+4
  b:SetScript('OnClick',function() Chat.SetHistoryRetention(value);Refresh() end)
  b:SetScript('OnEnter',function(self)
   if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
   GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(value..'x chat scrollback');GameTooltip:AddLine(MemoryText(value),.6,.83,1,true);GameTooltip:AddLine('Keeps '..value..'x more chat history in each tab during this session. Higher values use slightly more memory; lowering it may trim older messages.',1,1,1,true);GameTooltip:Show()
  end)
  b:SetScript('OnLeave',function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end);Suite.StyleButton(b)
 end
 parent:HookScript('OnShow',Refresh);Refresh()
end
local pendingFrame,pendingX,pendingY,pendingAt
local mouseDriver=CreateFrame('Frame')
local function TopMouseBlocked(chatFrame)
 local top
 if GetMouseFoci then
  local ok,foci=pcall(GetMouseFoci)
  if ok and type(foci)=='table' then top=foci[1] end
 elseif GetMouseFocus then
  local ok,focus=pcall(GetMouseFocus)
  if ok then top=focus end
 end
 if not top or top==WorldFrame or top==chatFrame then return false end
 if top.IsForbidden and top:IsForbidden() then return true end
 local chatName=chatFrame.GetName and chatFrame:GetName()
 local topName=top.GetName and top:GetName()
 if Suite.Public(chatName) and Suite.Public(topName) and type(chatName)=='string' and type(topName)=='string' and topName:sub(1,#chatName)==chatName then return false end
 local p=top
 for _=1,8 do
  if not p or (p.IsForbidden and p:IsForbidden()) then break end
  if p==chatFrame then return false end
  p=p.GetParent and p:GetParent()
 end
 return true
end
local function HoveredChatFrame()
 if SELECTED_CHAT_FRAME and frames[SELECTED_CHAT_FRAME]~=nil and not (SELECTED_CHAT_FRAME.IsForbidden and SELECTED_CHAT_FRAME:IsForbidden()) and SELECTED_CHAT_FRAME:IsShown() and SELECTED_CHAT_FRAME:IsVisible() and SELECTED_CHAT_FRAME:IsMouseOver() then
  return SELECTED_CHAT_FRAME
 end
 for frame in pairs(frames) do
  if not (frame.IsForbidden and frame:IsForbidden()) and frame:IsShown() and frame:IsVisible() and frame:IsMouseOver() then return frame end
 end
end
local function UpdateMouseDriver()
 local db=Chat.GetDB()
 if db and db.directCopy~=false then
  pcall(mouseDriver.RegisterEvent,mouseDriver,'GLOBAL_MOUSE_DOWN')
  pcall(mouseDriver.RegisterEvent,mouseDriver,'GLOBAL_MOUSE_UP')
 else
  pendingFrame=nil
  mouseDriver:UnregisterEvent('GLOBAL_MOUSE_DOWN')
  mouseDriver:UnregisterEvent('GLOBAL_MOUSE_UP')
 end
end
mouseDriver:SetScript('OnEvent',function(_,event,mouse)
 if (issecretvalue and issecretvalue(mouse)) or mouse~='RightButton' then return end
 local db=Chat.GetDB()
 if not db or db.directCopy==false then pendingFrame=nil;return end
 if event=='GLOBAL_MOUSE_DOWN' then
  pendingFrame=nil
  if hoveredLinkFrame then return end
  local target=HoveredChatFrame()
  if not target or TopMouseBlocked(target) then return end
  if UnitExists and UnitExists('mouseover') then return end
  local x,y=GetCursorPosition()
  if not Suite.Public(x) or not Suite.Public(y) or type(x)~='number' or type(y)~='number' then return end
  pendingFrame,pendingX,pendingY,pendingAt=target,x,y,GetTime()
 elseif event=='GLOBAL_MOUSE_UP' then
  local target=pendingFrame;pendingFrame=nil
  if not target or hoveredLinkFrame then return end
  if GetTime()-pendingAt>.35 or (IsMouselooking and IsMouselooking()) then return end
  local x,y=GetCursorPosition()
  if not Suite.Public(x) or not Suite.Public(y) or type(x)~='number' or type(y)~='number' then return end
  if math.abs(x-pendingX)>6 or math.abs(y-pendingY)>6 then return end
  if (target.IsForbidden and target:IsForbidden()) or not target:IsShown() or not target:IsVisible() or not target:IsMouseOver() or TopMouseBlocked(target) then return end
  if UnitExists and UnitExists('mouseover') then return end
  if not target.GetScaledCursorPosition or not target.FindCharacterAndLineIndexAtCoordinate then return end
  local cx,cy=target:GetScaledCursorPosition()
  if not Suite.Public(cx) or not Suite.Public(cy) or type(cx)~='number' or type(cy)~='number' then return end
  local _,index=target:FindCharacterAndLineIndexAtCoordinate(cx,cy)
  if (issecretvalue and issecretvalue(index)) or type(index)~='number' then return end
  local lines=rawget(target,'visibleLines');local line=type(lines)=='table' and lines[index]
  if not line or (line.IsShown and not line:IsShown()) then return end
  local alpha=line.GetAlpha and line:GetAlpha()
  if Suite.Public(alpha) and type(alpha)=='number' and alpha<=.05 then return end
  local text=line.GetText and line:GetText()
  if Chat.Core.Readable(text) and text~='' then Chat.OpenMessageEditor(target,text) end
 end
end)
function Chat.SetDirectCopy(enabled)
 local db=Chat.GetDB()
 if not db then return end
 db.directCopy=not not enabled
 for frame in pairs(frames) do if frame.SetTextCopyable then frame:SetTextCopyable(false) end end
 if not enabled and Chat.MessageEditor then Chat.MessageEditor:Hide() end
 UpdateMouseDriver()
end
function Chat.InstallDirectSelection(frame,history)
 if not frame or frames[frame]~=nil or (frame.IsForbidden and frame:IsForbidden()) then return end
 -- Disable automatic native clipboard path; copying is performed by Ctrl+C in
 -- a standard edit box. Addon code must never write to the system clipboard.
 -- Never force EnableMouse/EnableMouseClicks on Blizzard ChatFrames: keeping
 -- them click-through lets right-click-hold camera turning work everywhere.
 if frame.SetTextCopyable then frame:SetTextCopyable(false) end
 frames[frame]=false
 UpdateMouseDriver()
 frame:HookScript('OnHyperlinkEnter',function(self) hoveredLinkFrame=self end)
 frame:HookScript('OnHyperlinkLeave',function(self) if hoveredLinkFrame==self then hoveredLinkFrame=nil end end)
 local maximum=frame.GetMaxLines and frame:GetMaxLines()
 if (not issecretvalue or not issecretvalue(maximum)) and type(maximum)=='number' and maximum>0 then frames[frame]=maximum end
 ApplyRetention(frame)
 frame:SetResizable(true)
 if frame.SetResizeBounds then frame:SetResizeBounds(250,100,1400,1000) end
 local function SyncResizedChat()
  if not (InCombatLockdown and InCombatLockdown()) then
   local w,h=frame:GetSize()
   if Suite.Public(w) and Suite.Public(h) and type(w)=='number' and type(h)=='number' and w>0 and h>0 then
    local dock=GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    if type(dock)=='table' then
     local isDocked=false
     for _,df in ipairs(dock) do if df==frame then isDocked=true; break end end
     if isDocked then
      for _,df in ipairs(dock) do
       if df and df~=frame and not (df.IsForbidden and df:IsForbidden()) and df.SetSize then df:SetSize(w,h) end
      end
     end
    end
    if frame.UpdateLayout then pcall(frame.UpdateLayout,frame) end
   end
   if FCF_DockUpdate then pcall(FCF_DockUpdate) end
   if FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions,frame) end
  end
  if Chat.RefreshTimestampMarkers then Chat.RefreshTimestampMarkers() end
 end
 local resize=CreateFrame('Button',nil,frame);resize:SetSize(18,18);resize:SetPoint('BOTTOMRIGHT',frame,'TOPRIGHT',0,6);resize:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up');resize:RegisterForDrag('LeftButton')
 if history then history:ClearAllPoints();history:SetPoint('RIGHT',resize,'LEFT',-4,0) end
 resize:SetScript('OnDragStart',function()
  if InCombatLockdown and InCombatLockdown() then return end
  if FCF_StartSizing then pcall(FCF_StartSizing,frame,'TOPRIGHT')
  else frame:StartSizing('TOPRIGHT') end
 end)
 resize:SetScript('OnDragStop',function()
  frame:StopMovingOrSizing()
  SyncResizedChat()
 end)
 frame:HookScript('OnSizeChanged',function()
  if Chat.RefreshTimestampMarkers then Chat.RefreshTimestampMarkers() end
 end)
end
