local _,Suite=...
local Chat=Suite.Modules.SmyrnaChat
if not Chat then return end
local editor
local function Layout()
 if not editor then return end
 -- Only resize with the window. Typing and moving the caret must not reposition
 -- the native text control or change its selection geometry.
 editor.edit:SetSize(math.max(240,editor:GetWidth()-48),math.max(64,editor:GetHeight()-82))
end
function Chat.OpenMessageEditor(owner,text)
 if not Chat.GetDB().directCopy or not Chat.Core.Readable(text) or text=='' then return end
 if Chat.CloseHistory then Chat.CloseHistory() end
 if Chat.SelectionTest then Chat.SelectionTest:Hide() end
 local plain=Chat.Core.Plain(text)
 if not editor then
  editor=CreateFrame('Frame','SmyrnaChatMessageEditor',UIParent,'BackdropTemplate')
  editor:SetFrameStrata('FULLSCREEN_DIALOG');editor:SetFrameLevel(250);editor:SetClampedToScreen(true)
  editor:SetResizable(true);editor:SetResizeBounds(280,146,900,750)
  Suite.StylePanel(editor);editor.close=Suite.CloseButton(editor)
  local title=editor:CreateFontString(nil,'OVERLAY','GameFontNormal')
  title:SetPoint('TOPLEFT',16,-14);title:SetText('Message editor')
  local border=CreateFrame('Frame',nil,editor,'BackdropTemplate')
  border:SetPoint('TOPLEFT',16,-36);border:SetPoint('BOTTOMRIGHT',-16,34);Suite.StylePanel(border)
  -- Configuration 1 from the in-game comparison: direct child, default native
  -- mouse/keyboard handling, and above the decorative border.
  local box=CreateFrame('EditBox',nil,editor)
  box:SetPoint('TOPLEFT',24,-42);box:SetFrameLevel(border:GetFrameLevel()+2)
  box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject(ChatFontNormal);box:SetMaxLetters(0)
  box:SetScript('OnEscapePressed',function() editor:Hide() end)
  editor.edit=box
  editor.measure=editor:CreateFontString(nil,'BACKGROUND','ChatFontNormal');editor.measure:Hide()
  local hint=editor:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  hint:SetPoint('BOTTOMLEFT',16,14);hint:SetText('Drag to select  /  Ctrl+C to copy  /  Escape to close')
  local resize=CreateFrame('Button',nil,editor);resize:SetSize(18,18);resize:SetPoint('BOTTOMRIGHT')
  resize:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up');resize:RegisterForDrag('LeftButton')
  resize:SetScript('OnDragStart',function() editor:StartSizing('BOTTOMRIGHT') end)
  resize:SetScript('OnDragStop',function() editor:StopMovingOrSizing() end);editor.resize=resize
  editor:SetScript('OnSizeChanged',Layout)
  editor:SetScript('OnHide',function() box:ClearFocus();box:SetText('');editor.measure:SetText('') end)
  UISpecialFrames[#UISpecialFrames+1]='SmyrnaChatMessageEditor'
 end
 editor.measure:SetWidth(600);editor.measure:SetText(plain)
 local width=math.max(280,math.min(650,editor.measure:GetStringWidth()+48))
 editor.measure:SetWidth(width-48)
 local height=math.max(146,math.min(750,editor.measure:GetStringHeight()+94))
 editor:SetSize(width,height);editor:ClearAllPoints();editor:SetPoint('BOTTOMLEFT',owner,'TOPLEFT',0,4)
 Layout();editor.edit:SetText(plain);editor:Show()
 -- As in the successful test: do not force focus, caret or highlight on open.
 Chat.MessageEditor=editor
end
