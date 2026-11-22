local _,Suite=...
local Chat=Suite.Modules.SmyrnaChat
if not Chat then return end
local frames={}
function Chat.HistoryRetention()
 local value=Chat.GetDB().historyRetention
 return (value==10 or value==100 or value==1000) and value or 50
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
 if not low then return 'Memory estimate available after chat initializes.' end
 return string.format('When full: about %.1f-%.1f MiB across %d chat windows (%d messages).',low,high,windows,messages)
end
local function ApplyRetention(frame)
 local base=frames[frame];local value=Chat.HistoryRetention()
 if type(base)=='number' and frame.SetMaxLines then frame:SetMaxLines(base*value) end
 local button=rawget(frame,'smyrnaCopyButton')
 if button then button:SetText('History');button:SetWidth(55) end
end
function Chat.SetHistoryRetention(value)
 if value~=10 and value~=50 and value~=100 and value~=1000 then return false end
 Chat.GetDB().historyRetention=value
 for frame in pairs(frames) do ApplyRetention(frame) end
 if Chat.RefreshHistorySettings then Chat.RefreshHistorySettings() end
 return true
end
function Chat.BuildHistorySettings(parent)
 local title=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');title:SetPoint('TOPLEFT',365,-126);title:SetText('History retention')
 local buttons={}
 local estimate=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');estimate:SetPoint('TOPLEFT',20,-209);estimate:SetWidth(870);estimate:SetJustifyH('LEFT')
 local function Refresh()
  estimate:SetText(MemoryText(Chat.HistoryRetention()))
  for value,b in pairs(buttons) do b:SetText((Chat.HistoryRetention()==value and '|cff78d49b' or '')..value..'x'..(Chat.HistoryRetention()==value and '|r' or '')) end
 end
 Chat.RefreshHistorySettings=Refresh
 for i,value in ipairs({10,50,100,1000}) do
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(38,25);b:SetPoint('TOPLEFT',365+(i-1)*40,-145);buttons[value]=b
  b:SetScript('OnClick',function() Chat.SetHistoryRetention(value);Refresh() end)
  b:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(value..'x chat history');GameTooltip:AddLine(MemoryText(value),.6,.83,1,true);GameTooltip:AddLine('Lua benchmark estimate for 80-400 byte messages. Usage grows as messages arrive; long links and client overhead can increase it.',.7,.7,.7,true);GameTooltip:AddLine("Retain "..value.." times each chat window's original message limit for this session. More messages use more memory. Reducing this can discard older messages.",1,1,1,true);GameTooltip:Show() end)
  b:SetScript('OnLeave',function() GameTooltip:Hide() end);Suite.StyleButton(b)
 end
 parent:HookScript('OnShow',Refresh);Refresh()
end
function Chat.SetDirectCopy(enabled)
 Chat.GetDB().directCopy=not not enabled
 for frame in pairs(frames) do frame.smyrnaSelecting=false;if frame.SetTextCopyable then frame:SetTextCopyable(false) end end
 if not enabled and Chat.MessageEditor then Chat.MessageEditor:Hide() end
end
function Chat.InstallDirectSelection(frame,history)
 if frames[frame]~=nil then return end
 -- Disable automatic native clipboard path; copying is performed by Ctrl+C in
 -- a standard edit box. Addon code must never write to the system clipboard.
 if frame.SetTextCopyable then frame:SetTextCopyable(false) end
 frame:EnableMouse(true)
 if frame.EnableMouseClicks then frame:EnableMouseClicks(true) end
 if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
 frames[frame]=false
 frame.smyrnaSelecting=false
 frame:HookScript('OnMouseUp',function(self,mouse)
  if Chat.GetDB().directCopy==false or mouse~='RightButton' then return end
  if not self.GetScaledCursorPosition or not self.FindCharacterAndLineIndexAtCoordinate then return end
  local x,y=self:GetScaledCursorPosition();local _,index=self:FindCharacterAndLineIndexAtCoordinate(x,y)
  if (issecretvalue and issecretvalue(index)) or type(index)~='number' then return end
  local lines=rawget(self,'visibleLines');local line=type(lines)=='table' and lines[index]
  local text=line and line:GetText()
  if Chat.Core.Readable(text) and text~='' then Chat.OpenMessageEditor(self,text) end
 end)
 local maximum=frame.GetMaxLines and frame:GetMaxLines()
 if (not issecretvalue or not issecretvalue(maximum)) and type(maximum)=='number' and maximum>0 then frames[frame]=maximum end
 ApplyRetention(frame)
 frame:SetResizable(true)
 if frame.SetResizeBounds then frame:SetResizeBounds(250,100,1400,1000) end
 local function save() if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(frame) end end
 local resize=CreateFrame('Button',nil,frame);resize:SetSize(18,18);resize:SetPoint('BOTTOMRIGHT',frame,'TOPRIGHT',0,6);resize:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up');resize:RegisterForDrag('LeftButton')
 if history then history:ClearAllPoints();history:SetPoint('RIGHT',resize,'LEFT',-4,0) end
 resize:SetScript('OnDragStart',function() if not InCombatLockdown() then frame:StartSizing('TOPRIGHT') end end);resize:SetScript('OnDragStop',function() frame:StopMovingOrSizing();save() end)
end
