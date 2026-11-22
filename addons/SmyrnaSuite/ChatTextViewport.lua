local _,Suite=...
-- Keep text in a regular EditBox, as in the original message editor.
-- Move it inside a clipped Frame instead of making it a ScrollFrame scroll child:
-- native caret and drag-selection hit testing then use ordinary frame coordinates.
function Suite.CreateChatTextViewport(parent)
 local view=CreateFrame('Frame',nil,parent)
 view:SetClipsChildren(true);view:EnableMouse(false)
 view:SetFrameStrata(parent:GetFrameStrata());view:SetFrameLevel(parent:GetFrameLevel()+2)
 local box=CreateFrame('EditBox',nil,view)
 box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject(ChatFontNormal)
 box:SetMaxLetters(0);box:EnableMouse(true);box:EnableKeyboard(true)
 box:SetFrameStrata(parent:GetFrameStrata());box:SetFrameLevel(view:GetFrameLevel()+1)
 box:SetTextInsets(2,2,2,2);box:SetPoint('TOPLEFT',view,'TOPLEFT',0,0)
 local slider=CreateFrame('Slider',nil,parent)
 slider:SetPoint('TOPLEFT',view,'TOPRIGHT',5,0);slider:SetPoint('BOTTOMLEFT',view,'BOTTOMRIGHT',5,0)
 slider:SetWidth(12);slider:SetOrientation('VERTICAL');slider:SetMinMaxValues(0,0);slider:SetValueStep(1)
 slider:SetThumbTexture('Interface\\Buttons\\UI-ScrollBar-Knob')
 slider:GetThumbTexture():SetSize(12,24)
 slider:SetFrameLevel(box:GetFrameLevel()+1)
 local offset,range=0,0
 function view:GetVerticalScroll() return offset end
 function view:GetVerticalScrollRange() return range end
 local function Position()
  box:SetPoint('TOPLEFT',view,'TOPLEFT',0,offset)
  -- Offscreen text must not intercept clicks on the header or nearby windows.
  box:SetHitRectInsets(0,0,offset,math.max(0,box:GetHeight()-view:GetHeight()-offset))
 end
 function view:SetVerticalScroll(value)
  offset=math.max(0,math.min(range,value));Position()
  if slider:GetValue()~=offset then slider:SetValue(offset) end
 end
 function view:UpdateScrollChildRect()
  range=math.max(0,box:GetHeight()-self:GetHeight())
  slider:SetMinMaxValues(0,range);slider:SetShown(range>0)
  self:SetVerticalScroll(offset)
 end
 slider:SetScript('OnValueChanged',function(_,value) view:SetVerticalScroll(value) end)
 local function Wheel(_,delta) view:SetVerticalScroll(offset-delta*42) end
 view:EnableMouseWheel(true);box:EnableMouseWheel(true)
 view:SetScript('OnMouseWheel',Wheel);box:SetScript('OnMouseWheel',Wheel)
 view.EditBox=box;view.ScrollBar=slider
 return view,box
end
