local _,Suite=...
local C=Suite.Modules.SmyrnaChat
if not C then return end
local T={};C.TimeZones=T
T.Catalog={
 {id='turkiye',city='Turkiye',label='Turkiye',base=180},
 {id='newyork',city="New York - Arda's time",label="Arda's time",base=-300,rule='US'},
 {id='chicago',city='Chicago',label='Chicago',base=-360,rule='US'},
 {id='denver',city='Denver',label='Denver',base=-420,rule='US'},
 {id='losangeles',city='Los Angeles',label='Los Angeles',base=-480,rule='US'},
 {id='london',city='London',label='London',base=0,rule='EU'},
 {id='berlin',city='Berlin',label='Berlin',base=60,rule='EU'},
 {id='paris',city='Paris',label='Paris',base=60,rule='EU'},
 {id='dubai',city='Dubai',label='Dubai',base=240},
 {id='kolkata',city='Kolkata',label='Kolkata',base=330},
 {id='singapore',city='Singapore',label='Singapore',base=480},
 {id='tokyo',city='Tokyo',label='Tokyo',base=540},
 {id='utc',city='UTC / GMT',label='UTC',base=0},
}
local byID={};for _,z in ipairs(T.Catalog) do byID[z.id]=z end
local function Leap(y) return y%4==0 and (y%100~=0 or y%400==0) end
local before={0,31,59,90,120,151,181,212,243,273,304,334}
function T.Epoch(y,m,d,h,minute)
 local p=y-1
 local days=p*365+math.floor(p/4)-math.floor(p/100)+math.floor(p/400)+before[m]+d-719163
 if m>2 and Leap(y) then days=days+1 end
 return days*86400+(h or 0)*3600+(minute or 0)*60
end
local function Weekday(y,m,d) return (math.floor(T.Epoch(y,m,d)/86400)+4)%7 end
local function Sunday(y,m,n) return 1+(7-Weekday(y,m,1))%7+(n-1)*7 end
function T.Offset(id,now)
 local z=byID[id];if not z then return end
 local y=tonumber(date('!%Y',now));local start,finish
 if z.rule=='US' then
  start=T.Epoch(y,3,Sunday(y,3,2),2)-z.base*60
  finish=T.Epoch(y,11,Sunday(y,11,1),2)-(z.base+60)*60
 elseif z.rule=='EU' then
  start=T.Epoch(y,3,31-Weekday(y,3,31),1)
  finish=T.Epoch(y,10,31-Weekday(y,10,31),1)
 end
 return z.base+((start and now>=start and now<finish) and 60 or 0)
end
function T.GMT(offset)
 local n=math.abs(offset);return 'GMT'..(offset<0 and '-' or '+')..math.floor(n/60)..(n%60~=0 and string.format(':%02d',n%60) or '')
end
local cacheMinute,cacheKey,cached
function T.Init()
 local db=C.GetDB();if db.timeZonesEnabled==nil then db.timeZonesEnabled=true end
 if type(db.timeZones)~='table' then db.timeZones={'turkiye','newyork'} end
 local clean,seen={},{}
 for _,id in ipairs(db.timeZones) do if byID[id] and not seen[id] and #clean<8 then clean[#clean+1]=id;seen[id]=true end end
 db.timeZones=clean
end
function T.Add(id)
 local db=C.GetDB();if not byID[id] or #db.timeZones>=8 then return false end
 for _,old in ipairs(db.timeZones) do if old==id then return false end end
 db.timeZones[#db.timeZones+1]=id;cacheMinute=nil;return true
end
function T.Remove(id)
 for i,old in ipairs(C.GetDB().timeZones) do if old==id then table.remove(C.GetDB().timeZones,i);cacheMinute=nil;return true end end
end
function T.Lines(now)
 local db=C.GetDB();local minute=math.floor(now/60);local key=table.concat(db.timeZones,',')
 if minute==cacheMinute and key==cacheKey then return cached end
 local rows={}
 for _,id in ipairs(db.timeZones) do local z=byID[id];local offset=T.Offset(id,now);rows[#rows+1]={label=z.label..' ('..T.GMT(offset)..')',value=date('!%H:%M',now+offset*60),id=id} end
 cacheMinute=minute;cacheKey=key;cached=rows;return rows
end
function T.AppendTooltip()
 local db=C.GetDB();if not db or not db.timeZonesEnabled or #db.timeZones==0 then return end
 if TimeManagerClockButton and GameTooltip:GetOwner()~=TimeManagerClockButton then return end
 local now=GetServerTime and GetServerTime() or time()
 for _,r in ipairs(T.Lines(now)) do GameTooltip:AddDoubleLine(r.label,r.value,.6,.83,1,1,1,1) end
 GameTooltip:Show()
end
function C.BuildTimeZones(parent)
 local function Label(text,x,y)
  local f=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');f:SetPoint('TOPLEFT',x,y);f:SetText(text);return f
 end
 Label('Time Zone',20,-224):SetTextColor(.6,.83,1)
 local enabled=CreateFrame('CheckButton',nil,parent,'UICheckButtonTemplate');enabled:SetPoint('TOPLEFT',365,-216)
 local el=enabled:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');el:SetPoint('LEFT',enabled,'RIGHT',0,0);el:SetText('Show on clock tooltip')
 enabled:SetChecked(C.GetDB().timeZonesEnabled);enabled:SetScript('OnClick',function(self) C.GetDB().timeZonesEnabled=not not self:GetChecked() end)
 local choice='turkiye';local rows={};local menu
 local function Button(text,x,y,w,fn)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,24);b:SetPoint('TOPLEFT',x,y);b:SetText(text);b:SetScript('OnClick',fn);Suite.StyleButton(b);return b
 end
 local picker
 local status=Label('',365,-256)
 local function Refresh()
  enabled:SetChecked(C.GetDB().timeZonesEnabled)
  local now=GetServerTime and GetServerTime() or time()
  for i,r in ipairs(T.Lines(now)) do
   local row=rows[i]
   if not row then
    local x=20+math.floor((i-1)/4)*440;local y=-290-((i-1)%4)*28
    row={label=Label('',x,y-5)};row.remove=Button('Remove',x+335,y,70,function() T.Remove(row.id);Refresh() end);rows[i]=row
   end
   row.id=r.id;row.label:SetText(r.label..'  '..r.value);row.label:Show();row.remove:Show()
  end
  for i=#C.GetDB().timeZones+1,#rows do rows[i].label:Hide();rows[i].remove:Hide() end
 end
 picker=Button('Turkiye v',20,-250,210,function()
  if not menu then
   menu=CreateFrame('Frame',nil,parent,'BackdropTemplate');menu:SetPoint('TOPLEFT',picker,'BOTTOMLEFT',0,-3);menu:SetSize(430,math.ceil(#T.Catalog/2)*26+8);menu:SetFrameLevel(parent:GetFrameLevel()+30);menu:EnableMouse(true);Suite.StylePanel(menu)
   for i,z in ipairs(T.Catalog) do
    local b=CreateFrame('Button',nil,menu,'UIPanelButtonTemplate');b:SetSize(207,24);b:SetPoint('TOPLEFT',5+((i-1)%2)*213,-4-math.floor((i-1)/2)*26);b:SetText(z.city);Suite.StyleButton(b)
    b:SetScript('OnClick',function() choice=z.id;picker:SetText(z.city..' v');menu:Hide() end)
   end
  elseif menu:IsShown() then menu:Hide();return end
  menu:Show()
 end)
 Button('Add',240,-250,95,function() local ok=T.Add(choice);status:SetText(ok and '' or 'Already added, or at the 8-zone limit.');Refresh() end)
 parent:HookScript('OnShow',Refresh);parent:HookScript('OnHide',function() if menu then menu:Hide() end end)
 Refresh()
end
local hooked
local function HookClock()
 if not hooked and TimeManagerClockButton_UpdateTooltip then hooksecurefunc('TimeManagerClockButton_UpdateTooltip',T.AppendTooltip);hooked=true end
end
local driver=CreateFrame('Frame');driver:RegisterEvent('ADDON_LOADED');driver:RegisterEvent('PLAYER_LOGIN')
driver:SetScript('OnEvent',function(self,event,name)
 if event=='PLAYER_LOGIN' then T.Init();HookClock();self:UnregisterEvent('PLAYER_LOGIN')
 elseif name=='Blizzard_TimeManager' then HookClock() end
end)
