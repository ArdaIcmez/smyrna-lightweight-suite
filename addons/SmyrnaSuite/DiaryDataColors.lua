local _,Suite=...
local D=Suite.Modules.SmyrnaFieldDiary
if not D then return end
local defaults={personal='4dbfff',guild='ba8cff'}
local dirtyQueued=false
local function QueueRefresh()
 if dirtyQueued then return end
 dirtyQueued=true
 if C_Timer and C_Timer.After then
  C_Timer.After(.12,function()
   dirtyQueued=false
   if D.Dirty then D.Dirty() end
   if D.RefreshOptions then D.RefreshOptions() end
  end)
 else
  dirtyQueued=false
  if D.Dirty then D.Dirty() end
  if D.RefreshOptions then D.RefreshOptions() end
 end
end
function D.SourceColor(source)
 local colors=D.DB and D.DB.settings.dataColors
 local hex=colors and colors[source]
 if type(hex)~='string' or not hex:match('^%x%x%x%x%x%x$') then hex=defaults[source] or 'ffffff' end
 return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
end
function D.SetSourceColor(source,r,g,b)
 if not defaults[source] or not D.DB then return false end
 if not D.Core.Number(r,0,1) or not D.Core.Number(g,0,1) or not D.Core.Number(b,0,1) then return false end
 D.DB.settings.dataColors=D.DB.settings.dataColors or {}
 D.DB.settings.dataColors[source]=string.format('%02x%02x%02x',math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5))
 if D.RefreshDataColors then D.RefreshDataColors() end
 QueueRefresh()
 return true
end
function D.BuildDataColors(parent,x,y)
 local title=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');title:SetPoint('TOPLEFT',x,y);title:SetText(Suite.UIText('Data Colors (Outer Rim)','heading')..' '..Suite.UIText('(click to change)','muted'))
 local swatches={}
 local function Refresh() for source,texture in pairs(swatches) do texture:SetColorTexture(D.SourceColor(source)) end end
 D.RefreshDataColors=Refresh
 local entries={{'personal','Personal',105},{'guild','Guild',105}}
 local offset=0
 for _,entry in ipairs(entries) do
  local source,label,width=entry[1],entry[2],entry[3]
  local button=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');button:SetSize(width,24);button:SetPoint('TOPLEFT',x+offset,y-22);button:SetText('   '..label);Suite.StyleButton(button)
  local swatch=button:CreateTexture(nil,'OVERLAY',nil,2);swatch:SetSize(10,10);swatch:SetPoint('LEFT',6,0);swatches[source]=swatch
  button:SetScript('OnClick',function()
   local picker=ColorPickerFrame;if not picker or not picker.GetColorRGB then return end
   local r,g,b=D.SourceColor(source)
   local function Apply() D.SetSourceColor(source,picker:GetColorRGB()) end
   local function Cancel() D.SetSourceColor(source,r,g,b) end
   if picker.SetupColorPickerAndShow then picker:SetupColorPickerAndShow({r=r,g=g,b=b,hasOpacity=false,swatchFunc=Apply,cancelFunc=Cancel})
   elseif picker.SetColorRGB then picker:Hide();picker.func=nil;picker.cancelFunc=nil;picker:SetColorRGB(r,g,b);picker.hasOpacity=false;picker.func=Apply;picker.cancelFunc=Cancel;picker:Show() end
  end)
  offset=offset+width+4
 end
 local reset=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');reset:SetSize(60,24);reset:SetPoint('TOPLEFT',x+offset,y-22);reset:SetText('Reset');Suite.StyleButton(reset)
 reset:SetScript('OnClick',function() D.DB.settings.dataColors=nil;Refresh();if D.Dirty then D.Dirty() end;if D.RefreshOptions then D.RefreshOptions() end end)
 Refresh()
end
