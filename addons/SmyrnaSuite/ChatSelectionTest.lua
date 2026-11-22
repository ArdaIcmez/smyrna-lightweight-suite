local _,Suite=...
local Chat=Suite.Modules.SmyrnaChat
if not Chat then return end
local panel,boxes
local labels={
 '1  Original plain EditBox (default mouse settings)',
 '2  Plain EditBox with explicit mouse input',
 '3  Plain EditBox in a standard scroll frame',
 '4  Blizzard InputScrollFrameTemplate',
 '5  Current Smyrna clipped viewport',
}
function Chat.OpenSelectionTest(owner,text)
 if not Chat.GetDB().directCopy or not Chat.Core.Readable(text) then return end
 if Chat.CloseHistory then Chat.CloseHistory() end
 if not panel then
  panel=CreateFrame('Frame','SmyrnaChatSelectionTest',UIParent,'BackdropTemplate')
  panel:SetSize(620,650);panel:SetPoint('CENTER');panel:SetFrameStrata('FULLSCREEN_DIALOG');panel:SetFrameLevel(250)
  panel:SetClampedToScreen(true);Suite.StylePanel(panel);Suite.CloseButton(panel)
  local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',16,-14);title:SetText('Mouse selection test — 1 to 5')
  local help=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');help:SetPoint('TOPLEFT',16,-40)
  help:SetText('Click and drag over words in each box. Ctrl+C copies. Tell me which numbers work.')
  boxes={}
  for i=1,5 do
   local y=-68-(i-1)*108
   local label=panel:CreateFontString(nil,'OVERLAY','GameFontNormal');label:SetPoint('TOPLEFT',18,y);label:SetText(labels[i])
   local border=CreateFrame('Frame',nil,panel,'BackdropTemplate');border:SetPoint('TOPLEFT',16,y-20);border:SetSize(580,78)
   Suite.StylePanel(border)
   local view,box
   if i==4 then
    view=CreateFrame('ScrollFrame',nil,border,'InputScrollFrameTemplate');view:SetPoint('TOPLEFT',8,-6);view:SetSize(540,64)
    box=view.EditBox;if view.CharCount then view.CharCount:Hide() end
    box:EnableMouse(true)
   elseif i==5 then
    view,box=Suite.CreateChatTextViewport(border);view:SetPoint('TOPLEFT',8,-6);view:SetSize(540,64)
   elseif i==3 then
    view=CreateFrame('ScrollFrame',nil,border,'UIPanelScrollFrameTemplate');view:SetPoint('TOPLEFT',8,-6);view:SetSize(540,64)
    box=CreateFrame('EditBox',nil,view);view:SetScrollChild(box);box:SetPoint('TOPLEFT')
    box:EnableMouse(true)
   else
    box=CreateFrame('EditBox',nil,panel);box:SetPoint('TOPLEFT',24,y-26)
    box:SetFrameLevel(border:GetFrameLevel()+2)
    if i==2 then box:EnableMouse(true);box:EnableKeyboard(true) end
   end
   box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject(ChatFontNormal);box:SetMaxLetters(0)
   box:SetWidth(540);box:SetHeight(64)
   box:SetScript('OnEscapePressed',function() panel:Hide() end)
   boxes[i]={edit=box,view=view}
  end
  local hint=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');hint:SetPoint('BOTTOMLEFT',16,18)
  hint:SetText('Temporary diagnosis only. Escape or X closes. No messages are sent.')
  panel:SetScript('OnHide',function() for _,row in ipairs(boxes) do row.edit:ClearFocus();row.edit:SetText('') end end)
  UISpecialFrames[#UISpecialFrames+1]='SmyrnaChatSelectionTest'
 end
 local plain=Chat.Core.Plain(text)
 for _,row in ipairs(boxes) do
  row.edit:SetText(plain);row.edit:SetCursorPosition(0)
  if row.view then
   row.view:UpdateScrollChildRect();row.view:SetVerticalScroll(0)
  end
 end
 panel:SetScale(math.min(1,(UIParent:GetHeight()-30)/650));panel:Show()
 -- No forced focus/highlight or mouse scripts: each box owns its native input.
 Chat.SelectionTest=panel;Chat.SelectionTestBoxes=boxes
end
