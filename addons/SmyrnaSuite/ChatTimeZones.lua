local _,Suite=...
local C=Suite.Modules.SmyrnaChat
if not C then return end
local T={};C.TimeZones=T
T.Catalog={
 {id='gmt-12',city='Baker Island, International Date Line West',label='Date Line West',base=-720},
 {id='gmt-11',city='American Samoa, Midway, Niue',label='Samoa / Midway',base=-660},
 {id='gmt-10',city='Hawaii (Honolulu), Tahiti',label='Hawaii / Tahiti',base=-600},
 {id='gmt-9',city='Alaska (Anchorage, Juneau)',label='Alaska',base=-540,rule='US'},
 {id='gmt-8',city='Pacific Time (Los Angeles, Seattle, Vancouver)',label='Pacific (LA / Vancouver)',base=-480,rule='US'},
 {id='gmt-7',city='Mountain Time (Denver, Phoenix, Calgary)',label='Mountain (Denver)',base=-420,rule='US'},
 {id='gmt-6',city='Central Time (Chicago, Dallas, Mexico City)',label='Central (Chicago)',base=-360,rule='US'},
 {id='newyork',city='Eastern Time (New York, Toronto, Miami)',label='NYC time',base=-300,rule='US'},
 {id='gmt-4',city='Atlantic Time (Halifax, Santiago, Caracas, Puerto Rico)',label='Atlantic / Santiago',base=-240},
 {id='gmt-3:30',city="Newfoundland (St. John's)",label='Newfoundland',base=-210,rule='US'},
 {id='gmt-3',city='Brasilia, Buenos Aires, Sao Paulo, Montevideo',label='Buenos Aires / Sao Paulo',base=-180},
 {id='gmt-2',city='Mid-Atlantic, South Georgia',label='Mid-Atlantic',base=-120},
 {id='gmt-1',city='Azores, Cape Verde',label='Azores / Cape Verde',base=-60,rule='EU'},
 {id='gmt0',city='UTC / GMT (London, Lisbon, Dublin, Reykjavik)',label='UTC / London',base=0},
 {id='gmt+1',city='Central Europe (Berlin, Paris, Rome, Madrid, Amsterdam)',label='Central Europe',base=60,rule='EU'},
 {id='gmt+2',city='Eastern Europe (Athens, Helsinki, Cairo, Johannesburg)',label='Eastern Europe / Cairo',base=120,rule='EU'},
 {id='telaviv',city='Tel Aviv (Israel)',label='Tel Aviv',base=120,rule='IL'},
 {id='turkiye',city='Turkiye',label='Turkiye',base=180},
 {id='gmt+3:30',city='Iran (Tehran)',label='Tehran',base=210},
 {id='gmt+4',city='Gulf (Dubai, Abu Dhabi, Baku, Tbilisi)',label='Dubai / Baku',base=240},
 {id='gmt+5',city='Pakistan, Central Asia (Karachi, Tashkent)',label='Karachi / Tashkent',base=300},
 {id='gmt+5:30',city='India, Sri Lanka (Mumbai, New Delhi, Colombo)',label='India (New Delhi)',base=330},
 {id='gmt+6',city='Bangladesh, Kazakhstan (Dhaka, Almaty)',label='Dhaka / Almaty',base=360},
 {id='gmt+7',city='Indochina (Bangkok, Hanoi, Jakarta)',label='Bangkok / Jakarta',base=420},
 {id='gmt+8',city='China, Singapore, Perth, Hong Kong, Taipei',label='Singapore / Beijing',base=480},
 {id='gmt+9',city='Japan, Korea (Tokyo, Seoul)',label='Tokyo / Seoul',base=540},
 {id='gmt+9:30',city='Central Australia (Adelaide, Darwin)',label='Adelaide / Darwin',base=570},
 {id='gmt+10',city='Eastern Australia (Sydney, Melbourne, Brisbane, Guam)',label='Sydney / Melbourne',base=600},
 {id='gmt+11',city='Solomon Islands, New Caledonia, Magadan',label='Solomon Is.',base=660},
 {id='gmt+12',city='New Zealand, Fiji (Auckland, Wellington, Suva)',label='Auckland / Fiji',base=720},
 {id='gmt+13',city="Samoa, Tonga (Apia, Nuku'alofa)",label='Tonga / Samoa',base=780},
 {id='gmt+14',city='Line Islands (Kiritimati)',label='Line Islands',base=840},
}
local legacyAliases={
 chicago='gmt-6',denver='gmt-7',losangeles='gmt-8',london='gmt0',utc='gmt0',
 berlin='gmt+1',paris='gmt+1',singapore='gmt+8',tokyo='gmt+9',
}
local byID,indexByID,defaultIndex={},{},1
for i,z in ipairs(T.Catalog) do
 byID[z.id]=z;indexByID[z.id]=i
 if z.id=='gmt0' then defaultIndex=i end
end
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
 elseif z.rule=='IL' then
  start=T.Epoch(y,3,(31-Weekday(y,3,31))-2,2)-z.base*60
  finish=T.Epoch(y,10,31-Weekday(y,10,31),2)-(z.base+60)*60
 end
 return z.base+((start and now>=start and now<finish) and 60 or 0)
end
function T.GMT(offset)
 local n=math.abs(offset);return 'GMT'..(offset<0 and '-' or '+')..math.floor(n/60)..(n%60~=0 and string.format(':%02d',n%60) or '')
end
function T.CityLabel(id,now)
 local z=byID[id];if not z then return end
 local offset=T.Offset(id,now)
 local gmt=T.GMT(z.base)
 if offset~=z.base then gmt=gmt..' (DST '..T.GMT(offset)..')' end
 return gmt..' - '..z.city
end
local cacheMinute,cacheVersion,cached
local version=0
function T.Init()
 local db=C.GetDB();if not db then return end
 if db.timeZonesEnabled==nil then db.timeZonesEnabled=true end
 if type(db.timeZones)~='table' then db.timeZones={'turkiye','newyork'} end
 local clean,seen={},{}
 for _,raw in ipairs(db.timeZones) do
  local id=byID[raw] and raw or legacyAliases[raw]
  if id and byID[id] and not seen[id] and #clean<8 then clean[#clean+1]=id;seen[id]=true end
 end
 db.timeZones=clean;version=version+1;cacheMinute=nil
end
function T.Add(id)
 local db=C.GetDB();if not db or type(db.timeZones)~='table' or not byID[id] or #db.timeZones>=8 then return false end
 for _,old in ipairs(db.timeZones) do if old==id then return false end end
 db.timeZones[#db.timeZones+1]=id;version=version+1;cacheMinute=nil;return true
end
function T.Remove(id)
 local db=C.GetDB();if not db or type(db.timeZones)~='table' then return end
 for i,old in ipairs(db.timeZones) do if old==id then table.remove(db.timeZones,i);version=version+1;cacheMinute=nil;return true end end
end
function T.Lines(now)
 local db=C.GetDB();local list=db and db.timeZones
 if type(list)~='table' then return {} end
 local minute=math.floor(now/60)
 if minute==cacheMinute and version==cacheVersion and cached then return cached end
 local rows={}
 for _,id in ipairs(list) do local z=byID[id];if z then local offset=T.Offset(id,now);rows[#rows+1]={label=z.label..' ('..T.GMT(offset)..')',value=date('!%H:%M',now+offset*60),id=id} end end
 cacheMinute=minute;cacheVersion=version;cached=rows;return rows
end
function T.AppendTooltip()
 local db=C.GetDB();if not db or not db.timeZonesEnabled or type(db.timeZones)~='table' or #db.timeZones==0 then return end
 if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
 if TimeManagerClockButton and GameTooltip:GetOwner()~=TimeManagerClockButton then return end
 local now=GetServerTime and GetServerTime() or time()
 for _,r in ipairs(T.Lines(now)) do GameTooltip:AddDoubleLine(r.label,r.value,.6,.83,1,1,1,1) end
 GameTooltip:Show()
end
function C.BuildTimeZones(parent)
 local function Label(text,x,y)
  local f=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');f:SetPoint('TOPLEFT',x,y);f:SetText(text);return f
 end
 Label('Time Zone',20,-302):SetTextColor(.6,.83,1)
 local enabled=CreateFrame('CheckButton',nil,parent,'UICheckButtonTemplate');enabled:SetPoint('TOPLEFT',365,-296)
 local el=enabled:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');el:SetPoint('LEFT',enabled,'RIGHT',0,0);el:SetText('Show on clock tooltip')
 enabled:SetChecked(C.GetDB().timeZonesEnabled);enabled:SetScript('OnClick',function(self) C.GetDB().timeZonesEnabled=not not self:GetChecked() end)
 local choiceIndex=defaultIndex
 local rows={}
 local function Button(text,x,y,w,h,fn)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,h or 24);b:SetPoint('TOPLEFT',x,y);b:SetText(text);b:SetScript('OnClick',fn);Suite.StyleButton(b);return b
 end
 local status=Label('',565,-302);status:SetWidth(335);status:SetJustifyH('LEFT');status:SetTextColor(1,.78,.4)
 local slider=Suite.CreateSlider(parent,340,1,#T.Catalog)
 slider:SetPoint('TOPLEFT',50,-327)
 local selectedText=Label('',20,-354);selectedText:SetWidth(870);selectedText:SetJustifyH('LEFT')
 local function UpdateSelected()
  local z=T.Catalog[choiceIndex] or T.Catalog[defaultIndex]
  local now=GetServerTime and GetServerTime() or time()
  local offset=T.Offset(z.id,now)
  local gmt=T.GMT(z.base)..(offset~=z.base and (' (DST '..T.GMT(offset)..')') or '')
  local clock=date('!%H:%M',now+offset*60)
  selectedText:SetText('|cff99d4ff'..gmt..'|r  '..z.city..'  |cffffffff('..clock..')|r')
 end
 local function SetIndex(idx)
  choiceIndex=math.max(1,math.min(#T.Catalog,math.floor(idx+.5)))
  if slider:GetValue()~=choiceIndex then slider:SetValue(choiceIndex) end
  UpdateSelected()
 end
 slider:SetScript('OnValueChanged',function(_,value)
  local idx=math.max(1,math.min(#T.Catalog,math.floor((value or defaultIndex)+.5)))
  if idx~=choiceIndex then choiceIndex=idx;status:SetText('') end
  UpdateSelected()
 end)
 local function Refresh()
  local db=C.GetDB()
  enabled:SetChecked(db and db.timeZonesEnabled)
  local now=GetServerTime and GetServerTime() or time()
  UpdateSelected()
  local lines=T.Lines(now)
  for i,r in ipairs(lines) do
   local row=rows[i]
   if not row then
    local x=20+math.floor((i-1)/4)*440;local y=-384-((i-1)%4)*28
    local lbl=Label('',x,y-5);lbl:SetWidth(328);lbl:SetJustifyH('LEFT');lbl:SetMaxLines(1)
    row={label=lbl};row.remove=Button('Remove',x+335,y,70,24,function() T.Remove(row.id);status:SetText('');Refresh() end);rows[i]=row
   end
   row.id=r.id;row.label:SetText(r.label..'  '..r.value);row.label:Show();row.remove:Show()
  end
  for i=#lines+1,#rows do rows[i].label:Hide();rows[i].remove:Hide() end
 end
 Button('<',20,-325,24,22,function() SetIndex(choiceIndex-1);status:SetText('') end)
 Button('>',396,-325,24,22,function() SetIndex(choiceIndex+1);status:SetText('') end)
 Button('GMT+0',426,-325,60,22,function() SetIndex(defaultIndex);status:SetText('') end)
 Button('Add',492,-325,78,22,function()
  local z=T.Catalog[choiceIndex]
  local ok=z and T.Add(z.id)
  status:SetText(ok and '' or 'Already added, or at the 8-zone limit.')
  Refresh()
 end)
 slider:SetValue(defaultIndex)
 parent:HookScript('OnShow',function() status:SetText('');Refresh() end)
 Refresh()
end
local hooked
local function HookClock(frame)
 if not hooked and TimeManagerClockButton_UpdateTooltip then hooksecurefunc('TimeManagerClockButton_UpdateTooltip',T.AppendTooltip);hooked=true end
 if hooked and frame then frame:UnregisterEvent('ADDON_LOADED');frame:SetScript('OnEvent',nil) end
end
local driver=CreateFrame('Frame');driver:RegisterEvent('ADDON_LOADED');driver:RegisterEvent('PLAYER_LOGIN')
driver:SetScript('OnEvent',function(self,event,name)
 if event=='PLAYER_LOGIN' then
  T.Init();HookClock(self);self:UnregisterEvent('PLAYER_LOGIN')
  local isLoaded=(C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not hooked and isLoaded and isLoaded('Blizzard_TimeManager') then self:UnregisterEvent('ADDON_LOADED');self:SetScript('OnEvent',nil) end
 elseif Suite.Public(name) and name=='Blizzard_TimeManager' then HookClock(self) end
end)
