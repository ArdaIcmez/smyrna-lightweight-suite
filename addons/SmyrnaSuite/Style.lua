local _,S=...
local edge={bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12,insets={left=3,right=3,top=3,bottom=3}}
function S.StylePanel(f)
 f:SetBackdrop(edge);f:SetBackdropColor(.065,.065,.075,1);f:SetBackdropBorderColor(.48,.42,.29,.95)
end
function S.HeaderStrip(f)
 if f.smyrnaHeaderStrip then return end
 local t=f:CreateTexture(nil,'BACKGROUND');t:SetPoint('TOPLEFT',5,-5);t:SetPoint('TOPRIGHT',-5,-5);t:SetHeight(33);t:SetColorTexture(.14,.115,.065,1);f.smyrnaHeaderStrip=t
end
local function ButtonState(b)
 local state=b.smyrnaButtonStyle
 local pressed=state.selected or state.down
 state.left:SetShown(pressed);state.right:SetShown(pressed);state.center:SetShown(pressed)
end
local function ReleaseButton(b)
 b.smyrnaButtonStyle.down=false;ButtonState(b)
end
function S.SetButtonSelected(b,selected)
 if not b.smyrnaButtonStyle then S.StyleButton(b) end
 b.smyrnaButtonStyle.selected=not not selected;ButtonState(b)
end
-- Optional accent colors also support two-tone buttons such as Resistances.
function S.SetButtonAccent(b,r,g,blue,r2,g2,b2)
 if not b.smyrnaButtonStyle then S.StyleButton(b) end
 local state=b.smyrnaButtonStyle
 state.left:SetColorTexture(r,g,blue,1);state.right:SetColorTexture(r2 or r,g2 or g,b2 or blue,1)
end
function S.StyleButton(b)
 if b.smyrnaButtonStyle then return end
 b:SetNormalTexture('Interface\\Buttons\\WHITE8X8');local t=b:GetNormalTexture();if t then t:SetVertexColor(.09,.11,.15,1) end
 b:SetHighlightTexture('Interface\\Buttons\\WHITE8X8');local h=b:GetHighlightTexture();if h then h:SetVertexColor(.35,.55,.75,.25) end
 b:SetPushedTexture('Interface\\Buttons\\WHITE8X8');local p=b:GetPushedTexture();if p then p:SetVertexColor(.16,.16,.17,1) end
 local caption=b:GetFontString();if caption then caption:SetDrawLayer('OVERLAY',0) end
 local state={};b.smyrnaButtonStyle=state;b.smyrnaStyled=true
 -- Overlay the colored backgrounds, but stay below captions and icons.
 state.left=b:CreateTexture(nil,'OVERLAY',nil,-7);state.left:SetPoint('TOPLEFT');state.left:SetPoint('BOTTOMRIGHT',b,'BOTTOM',0,0)
 state.right=b:CreateTexture(nil,'OVERLAY',nil,-7);state.right:SetPoint('TOPLEFT',b,'TOP',0,0);state.right:SetPoint('BOTTOMRIGHT')
 state.center=b:CreateTexture(nil,'OVERLAY',nil,-6);state.center:SetPoint('TOPLEFT',1,-1);state.center:SetPoint('BOTTOMRIGHT',-1,1);state.center:SetColorTexture(.19,.16,.105,1)
 S.SetButtonAccent(b,.74,.58,.25)
 b:HookScript('OnMouseDown',function(self,button) if button=='LeftButton' and self:IsEnabled() then self.smyrnaButtonStyle.down=true;ButtonState(self) end end)
 b:HookScript('OnMouseUp',ReleaseButton);b:HookScript('OnLeave',ReleaseButton);b:HookScript('OnHide',ReleaseButton);b:HookScript('OnDisable',ReleaseButton)
 ButtonState(b)
end
function S.CloseButton(parent)
 local b=CreateFrame('Button',nil,parent,'BackdropTemplate');b:SetSize(26,26);b:SetPoint('TOPRIGHT',-7,-7);b:SetText('')
 local label=b:CreateFontString(nil,'OVERLAY','GameFontHighlightLarge');label:SetAllPoints();label:SetText('×');S.StyleButton(b)
 b:SetScript('OnClick',function() parent:Hide() end);return b
end
local _,S=...
local function Walk(f)
 if f.GetObjectType and f:GetObjectType()=='Button' and f.GetText then
  local text=f:GetText()
  if type(text)=='string' and text~='' and not f.smyrnaStyled then S.StyleButton(f);f.smyrnaStyled=true end
 end
 if f.GetChildren then for _,child in ipairs({f:GetChildren()}) do Walk(child) end end
end
S.StyleTree=Walk
