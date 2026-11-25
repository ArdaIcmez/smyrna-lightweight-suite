local _,S=...
local WHITE='Interface\\Buttons\\WHITE8X8'
local panelEdge={bgFile=WHITE,edgeFile=WHITE,edgeSize=1,insets={left=1,right=1,top=1,bottom=1}}
local shellEdge={bgFile=WHITE,edgeFile=WHITE,edgeSize=2,insets={left=2,right=2,top=2,bottom=2}}
local cardEdge={bgFile=WHITE,edgeFile=WHITE,edgeSize=1,insets={left=1,right=1,top=1,bottom=1}}

local gradMin,gradMax
local function ApplyGradient(tex,orientation,r1,g1,b1,a1,r2,g2,b2,a2)
 if not tex then return end
 tex:SetColorTexture(1,1,1,1)
 if tex.SetGradient and CreateColor then
  if not gradMin then gradMin=CreateColor(0,0,0,1);gradMax=CreateColor(0,0,0,1) end
  if gradMin.SetRGBA then
   gradMin:SetRGBA(r1,g1,b1,a1);gradMax:SetRGBA(r2,g2,b2,a2)
   local ok=pcall(tex.SetGradient,tex,orientation,gradMin,gradMax)
   if ok then return end
  else
   local ok=pcall(tex.SetGradient,tex,orientation,CreateColor(r1,g1,b1,a1),CreateColor(r2,g2,b2,a2))
   if ok then return end
  end
 end
 if tex.SetGradientAlpha then
  local ok=pcall(tex.SetGradientAlpha,tex,orientation,r1,g1,b1,a1,r2,g2,b2,a2)
  if ok then return end
 end
 tex:SetColorTexture((r1+r2)*.5,(g1+g2)*.5,(b1+b2)*.5,(a1+a2)*.5)
end
S.ApplyGradient=ApplyGradient

-- Shared passive popup decoration. Alpha is always relative to the backing.
local function PopupMotif(f)
 local name=f.GetName and f:GetName()
 if name=='SmyrnaSuiteHub' or name=='SmyrnaBaggerFrame' then return end
 if f.IsObjectType and f:IsObjectType('Button') then return end
 if f.smyrnaPopupMotif then return end
 local tex=f:CreateTexture(nil,'BACKGROUND',nil,0)
 tex:SetPoint('TOPLEFT',3,-3);tex:SetPoint('BOTTOMRIGHT',-3,3)
 tex:SetTexture('Interface\\AddOns\\SmyrnaSuite\\Media\\OttomanFloral','REPEAT','REPEAT')
 tex:SetHorizTile(true);tex:SetVertTile(true)
 f.smyrnaPopupMotif=tex
 local function Refresh()
  local w,h=f:GetWidth(),f:GetHeight()
  local backdrop=f.GetBackdrop and f:GetBackdrop()
  local visible=backdrop~=nil and w>=180 and h>=60
  tex:SetShown(visible)
  if visible then
   local _,_,_,alpha=f:GetBackdropColor()
   tex:SetAlpha(.08*(alpha or 1))
   tex:SetTexCoord(0,math.max(1,w-6)/256,0,math.max(1,h-6)/256)
  end
 end
 f:HookScript('OnSizeChanged',Refresh);f:HookScript('OnShow',Refresh)
 if hooksecurefunc then
  hooksecurefunc(f,'SetBackdropColor',Refresh)
  hooksecurefunc(f,'SetBackdrop',Refresh)
 end
 Refresh()
end

function S.StylePanel(f,thick)
 f:SetBackdrop(thick and shellEdge or panelEdge)
 f:SetBackdropColor(.055,.063,.082,.97)
 PopupMotif(f)
 if thick then
  -- Signature Smyrna Gilded Frame: 4 outer brushed-gold bars + 1 inner burnished-silver rim + gilded corner brackets
  f:SetBackdropBorderColor(.82,.67,.33,.96)
  if not f.smyrnaGildedFrame then
   local g={}
   -- Inner 1px burnished-silver filigree rim (inset 3px inside the 2px gold border)
   local sTop=f:CreateTexture(nil,'BORDER',nil,3);sTop:SetPoint('TOPLEFT',3,-3);sTop:SetPoint('TOPRIGHT',-3,-3);sTop:SetHeight(1);sTop:SetColorTexture(.78,.82,.88,.48)
   local sBot=f:CreateTexture(nil,'BORDER',nil,3);sBot:SetPoint('BOTTOMLEFT',3,3);sBot:SetPoint('BOTTOMRIGHT',-3,3);sBot:SetHeight(1);sBot:SetColorTexture(.78,.82,.88,.42)
   local sLft=f:CreateTexture(nil,'BORDER',nil,3);sLft:SetPoint('TOPLEFT',3,-3);sLft:SetPoint('BOTTOMLEFT',3,3);sLft:SetWidth(1);sLft:SetColorTexture(.78,.82,.88,.45)
   local sRgt=f:CreateTexture(nil,'BORDER',nil,3);sRgt:SetPoint('TOPRIGHT',-3,-3);sRgt:SetPoint('BOTTOMRIGHT',-3,3);sRgt:SetWidth(1);sRgt:SetColorTexture(.78,.82,.88,.45)
   g.silver={sTop,sBot,sLft,sRgt}
   -- 4 bright gold corner L-brackets
   local corners={{'TOPLEFT',0,0},{'TOPRIGHT',0,0},{'BOTTOMLEFT',0,0},{'BOTTOMRIGHT',0,0}}
   g.corners={}
   for _,c in ipairs(corners) do
    local ch=f:CreateTexture(nil,'OVERLAY',nil,6);ch:SetPoint(c[1],f,c[1],c[2],c[3]);ch:SetSize(10,2);ch:SetColorTexture(1,.86,.48,.95)
    local cv=f:CreateTexture(nil,'OVERLAY',nil,6);cv:SetPoint(c[1],f,c[1],c[2],c[3]);cv:SetSize(2,10);cv:SetColorTexture(1,.86,.48,.95)
    g.corners[#g.corners+1]=ch
    g.corners[#g.corners+1]=cv
   end
   f.smyrnaGildedFrame=g
  end
 else
  f:SetBackdropBorderColor(.36,.32,.25,.88)
  if not f.smyrnaInnerLine then
   local topLine=f:CreateTexture(nil,'BORDER')
   topLine:SetPoint('TOPLEFT',1,-1);topLine:SetPoint('TOPRIGHT',-1,-1);topLine:SetHeight(1)
   topLine:SetColorTexture(.78,.82,.88,.22)
   f.smyrnaInnerLine=topLine
  end
 end
end

function S.StyleCard(f,bgR,bgG,bgB)
 f:SetBackdrop(cardEdge)
 f:SetBackdropColor(bgR or .085,bgG or .098,bgB or .132,.96)
 f:SetBackdropBorderColor(.22,.25,.33,.88)
 if not f.smyrnaCardSheen then
  local sheen=f:CreateTexture(nil,'BACKGROUND',nil,1)
  sheen:SetPoint('TOPLEFT',1,-1);sheen:SetPoint('TOPRIGHT',-1,-1);sheen:SetHeight(16)
  ApplyGradient(sheen,'VERTICAL',1,1,1,0,1,1,1,.035)
  f.smyrnaCardSheen=sheen
 end
end

-- Subtle rarity glow radiated softly from all four corners of a framed card.
function S.SetCornerGlow(card,r,g,b,intensity)
 if not card then return end
 local glow=card.smyrnaCornerGlow
 if not glow then
  if not r then return end
  glow={shown=false}
  local corners={
   {'TOPLEFT',true,true},
   {'TOPRIGHT',false,true},
   {'BOTTOMLEFT',true,false},
   {'BOTTOMRIGHT',false,false},
  }
  for i,c in ipairs(corners) do
   local wash=card:CreateTexture(nil,'BACKGROUND',nil,2)
   local hEdge=card:CreateTexture(nil,'BORDER',nil,2)
   local vEdge=card:CreateTexture(nil,'BORDER',nil,2)
   local pt,isLeft,isTop=c[1],c[2],c[3]
   local ox=isLeft and 1 or -1;local oy=isTop and -1 or 1
   wash:SetPoint(pt,card,pt,ox,oy);wash:SetSize(74,26)
   hEdge:SetPoint(pt,card,pt,ox,oy);hEdge:SetSize(56,2)
   vEdge:SetPoint(pt,card,pt,ox,oy);vEdge:SetSize(2,24)
   glow[i]={wash=wash,hEdge=hEdge,vEdge=vEdge,isLeft=isLeft,isTop=isTop}
  end
  card.smyrnaCornerGlow=glow
 end
 if not r then
  if glow.shown then
   for i=1,4 do local gItem=glow[i];gItem.wash:Hide();gItem.hEdge:Hide();gItem.vEdge:Hide() end
   glow.shown=false
  end
  return
 end
 local a=intensity or .15
 if glow.shown and glow.r==r and glow.g==g and glow.b==b and glow.a==a then return end
 glow.shown=true;glow.r=r;glow.g=g;glow.b=b;glow.a=a
 local edgeA=math.min(.72,a*2.6)
 for i=1,4 do
  local gItem=glow[i]
  gItem.wash:Show();gItem.hEdge:Show();gItem.vEdge:Show()
  if gItem.isLeft then
   ApplyGradient(gItem.wash,'HORIZONTAL',r,g,b,a,r,g,b,0)
   ApplyGradient(gItem.hEdge,'HORIZONTAL',r,g,b,edgeA,r,g,b,0)
  else
   ApplyGradient(gItem.wash,'HORIZONTAL',r,g,b,0,r,g,b,a)
   ApplyGradient(gItem.hEdge,'HORIZONTAL',r,g,b,0,r,g,b,edgeA)
  end
  if gItem.isTop then
   ApplyGradient(gItem.vEdge,'VERTICAL',r,g,b,0,r,g,b,edgeA)
  else
   ApplyGradient(gItem.vEdge,'VERTICAL',r,g,b,edgeA,r,g,b,0)
  end
 end
end

function S.CreateIconTile(parent,size)
 local tile=CreateFrame('Frame',nil,parent,'BackdropTemplate')
 tile:SetSize(size,size)
 tile:SetBackdrop(cardEdge)
 tile:SetBackdropColor(.03,.035,.05,1)
 tile:SetBackdropBorderColor(.36,.38,.45,.95)
 local tex=tile:CreateTexture(nil,'ARTWORK')
 tex:SetPoint('TOPLEFT',2,-2);tex:SetPoint('BOTTOMRIGHT',-2,2)
 tex:SetTexCoord(.08,.92,.08,.92)
 tile.icon=tex
 return tile
end

function S.AttachTooltip(widget,title,body,label)
 if not widget then return widget end
 if label and widget.SetHitRectInsets and label.GetStringWidth then
  local w=label:GetStringWidth()
  if type(w)=="number" and w>0 then widget:SetHitRectInsets(0,-(w+8),0,0) end
 end
 widget:HookScript("OnEnter",function(self)
  if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
  GameTooltip:SetOwner(self,"ANCHOR_TOP")
  GameTooltip:SetText(title or "",1,.86,.48)
  if body and body~="" then GameTooltip:AddLine(body,.84,.88,.94,true) end
  GameTooltip:Show()
 end)
 widget:HookScript("OnLeave",function()
  if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
 end)
 return widget
end

function S.HorizontalRule(parent,x,y,width)
 local line=parent:CreateTexture(nil,'ARTWORK')
 line:SetPoint('TOPLEFT',x,y)
 line:SetSize(math.max(1,width),1)
 ApplyGradient(line,'HORIZONTAL',.74,.58,.28,.58,.74,.58,.28,.08)
 return line
end

function S.OptionSection(parent,text,x,y,width)
 local offset=0
 if text and text~='' then
  local label=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
  label:SetPoint('TOPLEFT',x,y)
  label:SetText(text)
  label:SetTextColor(.93,.77,.40)
  local measured=label:GetStringWidth()
  offset=(type(measured)=='number' and measured or (#text*6))+10
 end
 S.HorizontalRule(parent,x+offset,y-6,math.max(1,width-offset))
end

function S.HeaderStrip(f,height)
 if f.smyrnaHeaderStrip then return f.smyrnaHeaderStrip end
 local h=height or 42
 local t=f:CreateTexture(nil,'BACKGROUND',nil,1)
 t:SetPoint('TOPLEFT',2,-2);t:SetPoint('TOPRIGHT',-2,-2);t:SetHeight(h)
 ApplyGradient(t,'VERTICAL',.055,.063,.082,1,.14,.118,.075,1)
 local rule=f:CreateTexture(nil,'BORDER',nil,2)
 rule:SetPoint('TOPLEFT',t,'BOTTOMLEFT',0,0);rule:SetPoint('TOPRIGHT',t,'BOTTOMRIGHT',0,0);rule:SetHeight(1)
 ApplyGradient(rule,'HORIZONTAL',.68,.55,.28,.15,.68,.55,.28,.65)
 f.smyrnaHeaderStrip=t;f.smyrnaHeaderRule=rule
 return t
end

local function ButtonState(b)
 local state=b.smyrnaButtonStyle
 local pressed=state.selected or state.down
 state.left:SetShown(pressed);state.right:SetShown(pressed);state.center:SetShown(pressed)
 if state.border then
  if pressed then state.border:SetColorTexture(state.accentR or .88,state.accentG or .71,state.accentB or .34,.95)
  else state.border:SetColorTexture(.25,.29,.38,.85) end
 end
 local caption=b.GetFontString and b:GetFontString()
 if caption then
  if state.selected then caption:SetTextColor(1,.92,.72)
  elseif not b:IsEnabled() then caption:SetTextColor(.48,.51,.57)
  else caption:SetTextColor(.90,.92,.96) end
 end
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
 state.accentR,state.accentG,state.accentB=r,g,blue
 state.left:SetColorTexture(r,g,blue,1);state.right:SetColorTexture(r2 or r,g2 or g,b2 or blue,1)
 ButtonState(b)
end
function S.StyleButton(b)
 if b.smyrnaButtonStyle then return end
 b:SetNormalTexture(WHITE);local t=b:GetNormalTexture();if t then t:SetVertexColor(.11,.135,.185,1) end
 b:SetHighlightTexture(WHITE);local h=b:GetHighlightTexture();if h then h:SetVertexColor(.34,.52,.78,.24) end
 b:SetPushedTexture(WHITE);local p=b:GetPushedTexture();if p then p:SetVertexColor(.18,.16,.12,1) end
 if b.SetDisabledTexture then b:SetDisabledTexture(WHITE);local d=b:GetDisabledTexture();if d then d:SetVertexColor(.07,.08,.105,.85) end end
 local caption=b:GetFontString();if caption then caption:SetDrawLayer('OVERLAY',1) end
 local state={};b.smyrnaButtonStyle=state;b.smyrnaStyled=true
 local top=b:CreateTexture(nil,'BORDER',nil,3);top:SetPoint('TOPLEFT');top:SetPoint('TOPRIGHT');top:SetHeight(1);top:SetColorTexture(.25,.29,.38,.85)
 local bot=b:CreateTexture(nil,'BORDER',nil,3);bot:SetPoint('BOTTOMLEFT');bot:SetPoint('BOTTOMRIGHT');bot:SetHeight(1);bot:SetColorTexture(.18,.21,.28,.85)
 local lft=b:CreateTexture(nil,'BORDER',nil,3);lft:SetPoint('TOPLEFT');lft:SetPoint('BOTTOMLEFT');lft:SetWidth(1);lft:SetColorTexture(.22,.26,.34,.85)
 local rgt=b:CreateTexture(nil,'BORDER',nil,3);rgt:SetPoint('TOPRIGHT');rgt:SetPoint('BOTTOMRIGHT');rgt:SetWidth(1);rgt:SetColorTexture(.22,.26,.34,.85)
 state.border=top
 state.left=b:CreateTexture(nil,'OVERLAY',nil,-7);state.left:SetPoint('TOPLEFT');state.left:SetPoint('BOTTOMRIGHT',b,'BOTTOM',0,0)
 state.right=b:CreateTexture(nil,'OVERLAY',nil,-7);state.right:SetPoint('TOPLEFT',b,'TOP',0,0);state.right:SetPoint('BOTTOMRIGHT')
 state.center=b:CreateTexture(nil,'OVERLAY',nil,-6);state.center:SetPoint('TOPLEFT',1,-1);state.center:SetPoint('BOTTOMRIGHT',-1,1);state.center:SetColorTexture(.21,.175,.11,1)
 S.SetButtonAccent(b,.84,.67,.31)
 b:HookScript('OnMouseDown',function(self,button) if button=='LeftButton' and self:IsEnabled() then self.smyrnaButtonStyle.down=true;ButtonState(self) end end)
 b:HookScript('OnMouseUp',ReleaseButton);b:HookScript('OnLeave',ReleaseButton);b:HookScript('OnHide',ReleaseButton)
 b:HookScript('OnDisable',ButtonState);b:HookScript('OnEnable',ButtonState)
 ButtonState(b)
end

function S.CloseButton(parent)
 local b=CreateFrame('Button',nil,parent,'BackdropTemplate');b:SetSize(24,24);b:SetPoint('TOPRIGHT',-8,-8);b:SetText('')
 local label=b:CreateFontString(nil,'OVERLAY','GameFontHighlightLarge');label:SetAllPoints();label:SetText('x');label:SetTextColor(.82,.84,.88)
 S.StyleButton(b)
 local h=b:GetHighlightTexture();if h then h:SetVertexColor(.72,.2,.22,.45) end
 b:SetScript('OnClick',function() parent:Hide() end);return b
end

function S.CreateSlider(parent,width,minVal,maxVal)
 local s=CreateFrame('Slider',nil,parent)
 s:SetSize(width,20);s:SetOrientation('HORIZONTAL');s:SetMinMaxValues(minVal,maxVal);s:SetValueStep(1);s:SetObeyStepOnDrag(true)
 s:EnableMouse(true);s:EnableMouseWheel(true)
 local border=s:CreateTexture(nil,'BACKGROUND',nil,0)
 border:SetPoint('LEFT',2,0);border:SetPoint('RIGHT',-2,0);border:SetHeight(6)
 border:SetColorTexture(.30,.33,.42,.9)
 local groove=s:CreateTexture(nil,'BACKGROUND',nil,1)
 groove:SetPoint('LEFT',3,0);groove:SetPoint('RIGHT',-3,0);groove:SetHeight(4)
 groove:SetColorTexture(.05,.06,.085,1)
 local thumb=s:CreateTexture(nil,'OVERLAY');thumb:SetSize(12,18);thumb:SetColorTexture(.92,.76,.38,1)
 s:SetThumbTexture(thumb)
 local fill=s:CreateTexture(nil,'ARTWORK',nil,0)
 fill:SetPoint('TOPLEFT',groove,'TOPLEFT',0,0)
 fill:SetPoint('BOTTOMLEFT',groove,'BOTTOMLEFT',0,0)
 fill:SetPoint('RIGHT',thumb,'CENTER',0,0)
 ApplyGradient(fill,'HORIZONTAL',.54,.42,.19,.9,.90,.74,.36,1)
 s:SetScript('OnMouseWheel',function(self,delta)
  local lo,hi=self:GetMinMaxValues()
  local cur=math.floor((self:GetValue() or lo)+.5)
  self:SetValue(math.max(lo,math.min(hi,cur+(delta>0 and 1 or -1))))
 end)
 return s
end

local function WalkChildren(n,...)
 for i=1,n do
  local child=select(i,...)
  if child then S.StyleTree(child) end
 end
end
local function Walk(f)
 if f.GetObjectType and f:GetObjectType()=='Button' and f.GetText then
  local text=f:GetText()
  if type(text)=='string' and text~='' and not f.smyrnaStyled then S.StyleButton(f);f.smyrnaStyled=true end
 end
 if f.GetChildren then WalkChildren(select('#',f:GetChildren()),f:GetChildren()) end
end
S.StyleTree=Walk

-- Small optional-action footer. Restore pooled tooltip fonts before reuse.
local hintFonts=setmetatable({},{__mode='k'})
function S.OptionalHint(tip,text)
 if not tip or (tip.IsForbidden and tip:IsForbidden()) then return end
 tip:AddLine(text,.60,.65,.72,true)
 local name=tip:GetName();local line=name and _G[name..'TextLeft'..tip:NumLines()]
 if not line then return end
 local saved=hintFonts[tip]
 if not saved then
  saved={};hintFonts[tip]=saved
  tip:HookScript('OnTooltipCleared',function()
   for region,font in pairs(saved) do
    if font.object then region:SetFontObject(font.object) else region:SetFont(unpack(font)) end
    saved[region]=nil
   end
  end)
 end
 if not saved[line] then
  local font,size,flags=line:GetFont()
  saved[line]={font,size,flags,object=line:GetFontObject()}
 end
 line:SetFontObject(GameFontHighlightSmall)
end
