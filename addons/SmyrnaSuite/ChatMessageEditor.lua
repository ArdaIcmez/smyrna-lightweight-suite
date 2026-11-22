local _,Suite=...
local Chat=Suite.Modules.SmyrnaChat
if not Chat then return end
local editor
local function Reflow()
 if not editor then return end
 local width=math.max(240,editor:GetWidth()-42)
 editor.measure:SetWidth(width);editor.measure:SetText(editor.edit:GetText() or '')
 editor.edit:SetWidth(width);editor.edit:SetHeight(math.max(36,editor.measure:GetStringHeight()+12));editor.scroll:UpdateScrollChildRect()
end
function Chat.OpenMessageEditor(owner,text)
 if Chat.OpenSelectionTest then return Chat.OpenSelectionTest(owner,text) end
 if not Chat.GetDB().directCopy or not Chat.Core.Readable(text) or text=='' then return end
 if Chat.CloseHistory then Chat.CloseHistory() end
 local plain=Chat.Core.Plain(text)
 if not editor then
  editor=CreateFrame('Frame','SmyrnaChatMessageEditor',UIParent,'BackdropTemplate');editor:SetFrameStrata('FULLSCREEN_DIALOG');editor:SetFrameLevel(200);editor:SetClampedToScreen(true);editor:SetResizable(true);editor:SetMovable(true)
  editor:SetResizeBounds(280,110,900,600)
  Suite.StylePanel(editor)
  local close=Suite.CloseButton(editor);editor.close=close
  local title=editor:CreateFontString(nil,'OVERLAY','GameFontNormal');title:SetPoint('TOPLEFT',12,-10);title:SetText('Message editor')
  local drag=CreateFrame('Button',nil,editor);drag:SetPoint('TOPLEFT',0,0);drag:SetSize(200,27);drag:RegisterForDrag('LeftButton')
  drag:SetScript('OnDragStart',function() editor:StartMoving() end);drag:SetScript('OnDragStop',function() editor:StopMovingOrSizing() end)
  local scroll,box=Suite.CreateChatTextViewport(editor);scroll:SetPoint('TOPLEFT',12,-35);scroll:SetPoint('BOTTOMRIGHT',-30,32);editor.scroll=scroll
  editor.edit=box
  editor.measure=editor:CreateFontString(nil,'BACKGROUND','ChatFontNormal');editor.measure:Hide()
  box:SetScript('OnEscapePressed',function() editor:Hide() end)
  box:SetScript('OnTextChanged',Reflow)
  box:SetScript('OnCursorChanged',function(_,_,y,_,height)
   local offset=scroll:GetVerticalScroll();if type(offset)~='number' then return end
   if -y<offset then scroll:SetVerticalScroll(-y) elseif -y+height>offset+scroll:GetHeight() then scroll:SetVerticalScroll(-y+height-scroll:GetHeight()) end
  end)
  local hint=editor:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');hint:SetPoint('BOTTOMLEFT',12,12);hint:SetText('Ctrl+C to copy  /  Escape to close')
  local resize=CreateFrame('Button',nil,editor);resize:SetSize(18,18);resize:SetPoint('BOTTOMRIGHT');resize:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up');resize:RegisterForDrag('LeftButton');editor.resize=resize
  resize:SetScript('OnDragStart',function() editor:StartSizing('BOTTOMRIGHT') end);resize:SetScript('OnDragStop',function() editor:StopMovingOrSizing();Reflow() end)
  editor:SetScript('OnSizeChanged',Reflow)
  editor:SetScript('OnHide',function() box:ClearFocus();box:SetText('');editor.measure:SetText('') end)
  UISpecialFrames[#UISpecialFrames+1]='SmyrnaChatMessageEditor'
 end
 editor.measure:SetWidth(600);editor.measure:SetText(plain)
 local natural=editor.measure:GetStringWidth();if type(natural)~='number' then natural=380 end
 local width=math.max(280,math.min(600,natural+42));editor.measure:SetWidth(width-42)
 local height=math.max(110,math.min(300,editor.measure:GetStringHeight()+79))
 editor:SetSize(width,height);editor:ClearAllPoints();editor:SetPoint('BOTTOMLEFT',owner,'TOPLEFT',0,4);editor:Show()
 editor.edit:SetText(plain);Reflow();editor.scroll:SetVerticalScroll(0);editor.edit:SetFocus();editor.edit:SetCursorPosition(0);editor.scroll:SetVerticalScroll(0)
 Chat.MessageEditor=editor
end
