
frames={};UISpecialFrames={};SlashCmdList={};UIParent={};FOCUS=nil
Suite={Modules={},Versions={},Loaded={},Config={features={}}}
function issecretvalue(v) return v=='SECRET' end
function CreateFrame(kind,name,parent,template)
 local f={kind=kind,name=name,parent=parent,template=template,scripts={},text='',shown=false,width=kind=='ScrollFrame' and 600 or 200,height=kind=='ScrollFrame' and 319 or 200,level=1,offset=0,highlights=0}
 function f:SetScript(e,fn) self.scripts[e]=fn end
 function f:HookScript(e,fn) local old=self.scripts[e];self.scripts[e]=function(...) if old then old(...) end;fn(...) end end
 function f:SetShown(v) if v then self:Show() else self:Hide() end end
 function f:GetFontString() return nil end
 function f:SetClipsChildren(v) self.clips=v end
 function f:SetHitRectInsets(...) self.hitInsets={...} end
 function f:SetFrameStrata(v) self.strata=v end
 function f:GetFrameStrata() return self.strata or 'MEDIUM' end
 function f:SetColorTexture(...) self.color={...} end
 function f:SetMinMaxValues(low,high) self.min=low;self.max=high end
 function f:SetValue(value) self.value=value;if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end end
 function f:GetValue() return self.value or 0 end
 function f:SetThumbTexture(path) self.thumb=CreateFrame('Texture',nil,self) end
 function f:GetThumbTexture() return self.thumb end
 function f:RegisterEvent() end
 function f:Show() self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self) end end
 function f:Hide() self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self) end end
 function f:IsShown() return self.shown end
 function f:SetSize(w,h) self.width=w;self.height=h end
 function f:GetWidth() return self.width end
 function f:GetHeight() return self.height end
 function f:SetWidth(v) self.width=v end
 function f:SetHeight(v) self.height=v end
 function f:SetText(v) self.text=v;if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
 function f:GetText() return self.text end
 function f:SetPoint(...) self.anchor={...} end
 function f:SetParent(v) self.parent=v end
 function f:GetFrameLevel() return self.level end
 function f:SetFrameLevel(v) self.level=v end
 function f:EnableMouse(v) self.mouse=v end
 function f:EnableKeyboard(v) self.keyboard=v end
 function f:SetMouseClickEnabled(v) self.clickEnabled=v end
 function f:SetMouseMotionEnabled(v) self.motionEnabled=v end
 function f:SetTextInsets(...) self.insets={...} end
 function f:SetScrollChild(v) self.child=v end
 function f:SetVerticalScroll(v) self.offset=v end
 function f:GetVerticalScroll() return self.offset end
 function f:GetVerticalScrollRange() return math.max(0,self.child.height-self.height) end
 function f:SetEnabled(v) self.enabled=v end
 function f:SetFocus() FOCUS=self;self.focus=true end
 function f:ClearFocus() if FOCUS==self then FOCUS=nil end;self.focus=false end
 function f:HighlightText(...) self.highlights=self.highlights+1;if self.scripts.OnCursorChanged then self.scripts.OnCursorChanged(self,0,-self.height,0,14) end end
 function f:GetStringHeight()
  local height=0
  for line in (self.text..'\\n'):gmatch('(.-)\\n') do height=height+math.max(1,math.ceil(#line*7/math.max(1,self.width)))*14 end
  return height
 end
 function f:GetStringWidth() return #self.text*7 end
 function f:CreateFontString() return CreateFrame('FontString',nil,self) end
 function f:CreateTexture() return CreateFrame('Texture',nil,self) end
 setmetatable(f,{__index=function() return function() end end});frames[#frames+1]=f
 if kind=='ScrollFrame' and template=='InputScrollFrameTemplate' then f.EditBox=CreateFrame('EditBox',nil,f);f.CharCount=CreateFrame('FontString',nil,f) end
 return f
end
CopyToClipboard=function() error('Forbidden clipboard call') end
