local _,Suite=...
local Chat=Suite.Modules.SmyrnaChat
if not Chat then return end
local editor,toast

-- Show a brief center-screen toast matching Blizzard's "Screen Captured" notice.
local function ShowCopiedNotice()
 if ActionStatus and ActionStatus.DisplayMessage then
  local ok=pcall(ActionStatus.DisplayMessage,ActionStatus,"Copied to clipboard")
  if ok then return end
 end
 if not toast then
  toast=CreateFrame("Frame",nil,UIParent)
  toast:SetSize(420,40);toast:SetPoint("CENTER",UIParent,"CENTER",0,110)
  toast:SetFrameStrata("FULLSCREEN_DIALOG");toast:SetFrameLevel(300)
  toast.text=toast:CreateFontString(nil,"OVERLAY","GameFontNormalHuge")
  toast.text:SetPoint("CENTER");toast.text:SetTextColor(1,1,1,1)
  local ag=toast:CreateAnimationGroup()
  local hold=ag:CreateAnimation("Alpha");hold:SetFromAlpha(1);hold:SetToAlpha(1);hold:SetDuration(.9);hold:SetOrder(1)
  local fade=ag:CreateAnimation("Alpha");fade:SetFromAlpha(1);fade:SetToAlpha(0);fade:SetDuration(.7);fade:SetOrder(2)
  ag:SetScript("OnFinished",function() toast:Hide() end)
  toast.anim=ag
 end
 toast.anim:Stop()
 toast.text:SetText("Copied to clipboard")
 toast:SetAlpha(1);toast:Show();toast.anim:Play()
end

local function Layout()
 if not editor then return end
 local innerW=math.max(240,(editor:GetWidth() or 330)-56)
 local innerH=math.max(64,(editor:GetHeight() or 146)-84)
 editor.scroll:SetSize(innerW+16,innerH)
 editor.edit:SetWidth(innerW)
 if editor.scroll.UpdateScrollChildRect then editor.scroll:UpdateScrollChildRect() end
end

local function ApplyText(text)
 editor.measure:SetWidth(600);editor.measure:SetText(text)
 local sw=editor.measure:GetStringWidth()
 if not Suite.Public(sw) or type(sw)~='number' then sw=420 end
 local width=math.max(330,math.min(650,sw+64))
 editor.measure:SetWidth(width-64)
 local sh=editor.measure:GetStringHeight()
 if not Suite.Public(sh) or type(sh)~='number' then sh=64 end
 local height=math.max(146,math.min(620,sh+98))
 editor:SetSize(width,height)
 Layout()
 editor.edit:SetText(text)
 editor.scroll:SetVerticalScroll(0)
 editor.edit:SetFocus()
 editor.edit:HighlightText()
end

function Chat.OpenMessageEditor(owner,text)
 local db=Chat.GetDB()
 if not db or not db.directCopy or not Chat.Core.Readable(text) or text=='' then return end
 if Chat.CloseHistory then Chat.CloseHistory() end
 local full=Chat.Core.Plain(text)
 local body=Chat.Core.MessageBody and Chat.Core.MessageBody(text) or full
 if not editor then
  editor=CreateFrame('Frame','SmyrnaChatMessageEditor',UIParent,'BackdropTemplate')
  editor:SetFrameStrata('FULLSCREEN_DIALOG');editor:SetFrameLevel(250);editor:SetClampedToScreen(true)
  editor:SetResizable(true);editor:SetResizeBounds(330,146,900,750)
  Suite.StylePanel(editor,true);editor.close=Suite.CloseButton(editor)
  local title=editor:CreateFontString(nil,'OVERLAY','GameFontNormal')
  title:SetPoint('TOPLEFT',16,-14);title:SetText('Copy message');title:SetTextColor(1,.86,.48)
  local border=CreateFrame('Frame',nil,editor,'BackdropTemplate')
  border:SetPoint('TOPLEFT',16,-36);border:SetPoint('BOTTOMRIGHT',-16,36);Suite.StyleCard(border)
  -- Native EditBox copy inside ScrollFrame: clips tall messages cleanly; user presses Ctrl+C.
  local scroll=CreateFrame('ScrollFrame',nil,border,'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT',8,-6);scroll:SetPoint('BOTTOMRIGHT',-24,6)
  local box=CreateFrame('EditBox',nil,scroll)
  box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject(ChatFontNormal);box:SetMaxLetters(0)
  box:SetWidth(280)
  scroll:SetScrollChild(box)
  box:SetScript('OnEscapePressed',function() editor:Hide() end)
  box:SetScript('OnKeyDown',function(_,key)
   if (issecretvalue and issecretvalue(key)) or type(key)~='string' then return end
   local mod=(IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
   if string.upper(key)=='C' and mod then
    local token=editor.generation
    -- Wait for native EditBox Ctrl+C copy to complete before closing & showing toast.
    C_Timer.After(.02,function()
     if editor and editor:IsShown() and editor.generation==token then
      editor:Hide()
      ShowCopiedNotice()
     end
    end)
   end
  end)
  scroll:EnableMouseWheel(true)
  local function Wheel(_,delta)
   local cur,mx=scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()
   if type(cur)=='number' and type(mx)=='number' then scroll:SetVerticalScroll(math.max(0,math.min(mx,cur-delta*36))) end
  end
  scroll:SetScript('OnMouseWheel',Wheel);box:EnableMouseWheel(true);box:SetScript('OnMouseWheel',Wheel)
  editor.scroll=scroll;editor.edit=box
  editor.measure=editor:CreateFontString(nil,'BACKGROUND','ChatFontNormal');editor.measure:Hide()
  local hint=editor:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  hint:SetPoint('BOTTOMLEFT',16,14);hint:SetText('Press Ctrl+C to copy  /  Esc to close');hint:SetTextColor(.70,.75,.84)
  local toggle=CreateFrame('Button',nil,editor,'UIPanelButtonTemplate')
  toggle:SetSize(84,20);toggle:SetPoint('BOTTOMRIGHT',-24,10);Suite.StyleButton(toggle)
  toggle:SetScript('OnClick',function()
   editor.showFull=not editor.showFull
   toggle:SetText(editor.showFull and 'Message only' or 'Full line')
   ApplyText(editor.showFull and editor.fullText or editor.bodyText)
  end)
  editor.toggle=toggle
  local resize=CreateFrame('Button',nil,editor);resize:SetSize(18,18);resize:SetPoint('BOTTOMRIGHT')
  resize:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up');resize:RegisterForDrag('LeftButton')
  resize:SetScript('OnDragStart',function() if not (InCombatLockdown and InCombatLockdown()) then editor:StartSizing('BOTTOMRIGHT') end end)
  resize:SetScript('OnDragStop',function() editor:StopMovingOrSizing() end);editor.resize=resize
  editor:SetScript('OnSizeChanged',Layout)
  editor:SetScript('OnHide',function()
   editor.generation=(editor.generation or 0)+1
   box:ClearFocus();box:SetText('');editor.measure:SetText('');scroll:SetVerticalScroll(0)
  end)
  UISpecialFrames[#UISpecialFrames+1]='SmyrnaChatMessageEditor'
 end
 editor.generation=(editor.generation or 0)+1
 editor.bodyText=body;editor.fullText=full;editor.showFull=true
 editor.toggle:SetShown(body~=full)
 editor.toggle:SetText('Message only')
 editor:ClearAllPoints()
 if owner and not (owner.IsForbidden and owner:IsForbidden()) then
  editor:SetPoint('BOTTOMLEFT',owner,'TOPLEFT',0,4)
 else
  editor:SetPoint('CENTER',UIParent,'CENTER',0,0)
 end
 editor:Show()
 ApplyText(full)
 Chat.MessageEditor=editor
end
