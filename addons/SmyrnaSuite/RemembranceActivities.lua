local _,Suite=...
local R=Suite.Modules.SmyrnaRemembrance
if not R then return end
local A={};R.Activities=A
local PREFIX='SmyrnaTogether1'
local own,pending,confirmed={},{},{}
local pendingCount=0
local driver=CreateFrame('Frame')
local function Public(v) return R.Public(v) end
local function Number(v,max) return Public(v) and type(v)=='number' and v==v and v%1==0 and v>0 and v<=max end
local function Text(v) return Public(v) and type(v)=='string' and #v>0 and #v<=200 and not v:find('[%c|]') and v end
local function Now() return math.floor(R.Now()/1000) end
local function Active() return R.DB and R.DB.enabled and R.DB.players and R.DB.activitiesEnabled end
function A.Group()
 local result={}
 local raid=IsInRaid and IsInRaid()
 local count=raid and GetNumGroupMembers and GetNumGroupMembers() or GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
 if not Public(count) or type(count)~='number' then return result end
 for i=1,math.min(count,40) do
  local unit=(raid and 'raid' or 'party')..i
  local guid=UnitGUID(unit)
  local sameMe=UnitIsUnit and UnitIsUnit(unit,'player')
  if Public(guid) and type(guid)=='string' and guid:match('^Player%-%d+%-%x+$') and not (Public(sameMe) and sameMe) then
   local first,last=UnitFullName(unit);local name=Suite.PlayerName(Text(first),Text(last))
   if name then result[#result+1]={unit=unit,guid=guid,key='P:'..guid,name=name,first=first} end
  end
 end
 return result
end
local kinds={D=true,C=true,B=true,W=true,Q=true,E=true}
function A.Add(person,kind,id,title,stamp)
 if not Active() or not person or not kinds[kind] or not Number(id,10000000) or not Text(title) then return false end
 local db=R.DB;stamp=stamp or Now()
 if not Number(stamp,10000000000) then return false end
 local row=R.ReadRecord(person.key,db.records[person.key])
 if not row then
  local level=UnitLevel and UnitLevel(person.unit);if not Number(level,1000) then level=nil end
  db.records[person.key]=R.PackRecord(person.name,stamp*1000,0,level,nil)
  R.Count=R.Count+1
  if R.EnforceCap then R.EnforceCap() end
 end
 local catalog=kind..':'..id
 db.activityNames[catalog]=title
 db.activities[person.key]=Suite.EventLog.Append(db.activities[person.key],kind..','..id..','..stamp..';')
 R.Revision=(R.Revision or 0)+1
 return true
end
local function Instance()
 if not GetInstanceInfo then return end
 local name,kind,difficulty,_,_,_,_,id=GetInstanceInfo()
 if not Text(name) or not Public(kind) or not Number(id,10000000) or (kind~='party' and kind~='raid' and kind~='pvp') then return end
 return {name=name,kind=kind,id=id,difficulty=Number(difficulty,10000) and difficulty or 0}
end
local function SameInstance(unit)
 if UnitPosition then
  local _,_,_,here=UnitPosition('player');local _,_,_,there=UnitPosition(unit)
  if Public(here) and Public(there) and type(here)=='number' and type(there)=='number' and here>0 and there>0 then return here==there end
 end
 local visible=UnitIsVisible and UnitIsVisible(unit)
 return Public(visible) and visible==true
end
function A.Scan()
 local instance=Instance()
 if R.DB and not instance then R.DB.activitySession=nil;return end
 if not Active() then return end
 local key=instance.kind..':'..instance.id..':'..instance.difficulty
 local session=R.DB.activitySession
 if type(session)~='table' or session.key~=key then session={key=key,seen={},completed={},bosses={}};R.DB.activitySession=session end
 for _,person in ipairs(A.Group()) do
  if SameInstance(person.unit) and not session.seen[person.key] then
   session.seen[person.key]=true
   A.Add(person,instance.kind=='pvp' and 'B' or 'D',instance.id,instance.name)
  end
 end
 return instance,session
end
function A.Complete(kind,bossID,bossName)
 local instance,session=A.Scan();if not instance then return end
 if kind=='W' and instance.kind~='pvp' then return end
 if kind=='E' and instance.kind=='pvp' then return end
 if kind=='C' and instance.kind~='party' and instance.kind~='raid' then return end
 for _,person in ipairs(A.Group()) do
  if SameInstance(person.unit) then
   local dedup=kind=='E' and session.bosses or session.completed
   local key=person.key..':'..kind..':'..(bossID or 0)
   if not dedup[key] then
    dedup[key]=true
    A.Add(person,kind,bossID or instance.id,bossID and (instance.name..' - '..bossName) or instance.name)
   end
  end
 end
end
local function Prune()
 local now=Now()
 for id,row in pairs(own) do if now-row.stamp>600 then own[id]=nil end end
 for key,row in pairs(pending) do if now-row.stamp>600 then pending[key]=nil;pendingCount=pendingCount-1 end end
 for key,stamp in pairs(confirmed) do if now-stamp>600 then confirmed[key]=nil end end
end
local function Confirm(person,id)
 local row=own[id];local key=person.key..':'..id
 if not row or not row.members[person.key] or confirmed[key] then return end
 confirmed[key]=Now()
 local title=C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
 A.Add(person,'Q',id,Text(title) or ('Quest #'..id),math.max(row.stamp,Now()))
end
local function Send(id)
 local api=C_ChatInfo
 if not api or not api.SendAddonMessage then return end
 if api.AreOutgoingAddonChatMessagesRestricted and api.AreOutgoingAddonChatMessagesRestricted() then return end
 local channel=IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and 'INSTANCE_CHAT' or IsInRaid and IsInRaid() and 'RAID' or 'PARTY'
 api.SendAddonMessage(PREFIX,'Q|'..id,channel)
end
function A.Quest(id)
 if not Active() or not R.DB.questConfirm or not Number(id,10000000) then return end
 Prune()
 if own[id] then return end
 local members={};local group=A.Group()
 if #group==0 then return end
 for _,person in ipairs(group) do members[person.key]=true end
 own[id]={stamp=Now(),members=members}
 for _,person in ipairs(group) do if pending[person.key..':'..id] then Confirm(person,id) end end
 Send(id)
end
function A.Receive(prefix,message,channel,sender)
 if not Active() or not R.DB.questConfirm or not Public(prefix) or prefix~=PREFIX or not Public(channel) or (channel~='PARTY' and channel~='RAID' and channel~='INSTANCE_CHAT') then return false end
 if not Text(sender) or not Public(message) or type(message)~='string' or #message>24 or message:find('[%c]') then return false end
 local id=tonumber(message:match('^Q|(%d+)$'));if not Number(id,10000000) then return false end
 local match
 local short=sender:match('^([^-]+)')
 for _,person in ipairs(A.Group()) do
  if sender==person.name or sender==person.first or (short and (short==person.name or short==person.first)) then if match then return false end;match=person end
 end
 if not match then return false end
 Prune()
 local key=match.key..':'..id
 if pending[key] or confirmed[key] or pendingCount>=256 then return false end
 pending[key]={stamp=Now()};pendingCount=pendingCount+1
 Confirm(match,id)
 return true
end
local activitySections={{'D','Dungeons / raids together'},{'C','Dungeon completions confirmed'},{'E','Bosses defeated together'},{'B','Battlegrounds together'},{'W','Battlegrounds completed'}}

function A.Summary(key)
 local packed=R.DB and R.DB.activities and R.DB.activities[key]
 local out={dgCount=0,bgCount=0,questCount=0,bossCount=0,total=0,dungeons={},bgs={}}
 if type(packed)~='string' and type(packed)~='table' then return out end
 local dgMap,bgMap,dgOrder,bgOrder={},{},{},{}
 local cCount,wCount=0,0
 for entry in Suite.EventLog.Entries(packed) do
  local kind,id,stamp=entry:match('^([DCEBWQ]),(%d+),(%d+)$')
  id,stamp=tonumber(id),tonumber(stamp)
  if Number(id,10000000) and Number(stamp,10000000000) then
   local title=R.DB.activityNames[kind..':'..id] or (kind=='Q' and ('Quest #'..id) or ('Activity #'..id))
   if kind=='D' then
    out.dgCount=out.dgCount+1
    if not dgMap[title] then dgMap[title]=0; dgOrder[#dgOrder+1]=title end
    dgMap[title]=dgMap[title]+1
   elseif kind=='C' then
    cCount=cCount+1
    if not dgMap[title] then dgMap[title]=0; dgOrder[#dgOrder+1]=title end
    if dgMap[title]==0 then dgMap[title]=1 end
   elseif kind=='E' then
    out.bossCount=out.bossCount+1
   elseif kind=='B' then
    out.bgCount=out.bgCount+1
    if not bgMap[title] then bgMap[title]=0; bgOrder[#bgOrder+1]=title end
    bgMap[title]=bgMap[title]+1
   elseif kind=='W' then
    wCount=wCount+1
    if not bgMap[title] then bgMap[title]=0; bgOrder[#bgOrder+1]=title end
    if bgMap[title]==0 then bgMap[title]=1 end
   elseif kind=='Q' then
    out.questCount=out.questCount+1
   end
  end
 end
 if out.dgCount==0 and cCount>0 then out.dgCount=cCount end
 if out.bgCount==0 and wCount>0 then out.bgCount=wCount end
 for i=#dgOrder,1,-1 do
  local nm=dgOrder[i]
  out.dungeons[#out.dungeons+1]={name=nm,count=dgMap[nm]}
 end
 for i=#bgOrder,1,-1 do
  local nm=bgOrder[i]
  out.bgs[#out.bgs+1]={name=nm,count=bgMap[nm]}
 end
 out.total=out.dgCount+out.bgCount+out.questCount
 return out
end

function A.FormatNamedList(items,maxShow)
 if type(items)~='table' or #items==0 then return '' end
 local parts={}
 local limit=math.min(#items,maxShow or 6)
 for i=1,limit do
  local it=items[i]
  parts[#parts+1]=it.count>1 and (it.name..' x'..it.count) or it.name
 end
 if #items>limit then parts[#parts+1]='+'..(#items-limit)..' more' end
 return table.concat(parts,', ')
end

function A.Lines(key)
 local packed=R.DB.activities and R.DB.activities[key]
 if type(packed)~='string' and type(packed)~='table' then return {},0 end
 local groups={D={},C={},E={},B={},W={}}
 local questCount,count=0,0
 for entry in Suite.EventLog.Entries(packed) do
  local kind,id,stamp=entry:match('^([DCEBWQ]),(%d+),(%d+)$')
  id,stamp=tonumber(id),tonumber(stamp)
  if Number(id,10000000) and Number(stamp,10000000000) then
   count=count+1
   if kind=='Q' then
    questCount=questCount+1
   elseif groups[kind] then
    local title=R.DB.activityNames[kind..':'..id] or ('Activity #'..id)
    groups[kind][#groups[kind]+1]=R.Format(stamp*1000)..'  -  '..title
   end
  end
 end
 local lines={}
 for _,section in ipairs(activitySections) do
  local rows=groups[section[1]]
  if #rows>0 then
   if #lines>0 then lines[#lines+1]='' end
   lines[#lines+1]=Suite.UIText(section[2],'heading')
   for i=#rows,1,-1 do lines[#lines+1]=rows[i] end
  end
 end
 if questCount>0 then
  if #lines>0 then lines[#lines+1]='' end
  lines[#lines+1]=Suite.UIText('Quests completed together','heading')
  lines[#lines+1]=questCount..(questCount==1 and ' quest completed together' or ' quests completed together')
 end
 return lines,count
end
function R.InitActivities()
 local db=R.DB
 db.activities=type(db.activities)=='table' and db.activities or {}
 db.activityNames=type(db.activityNames)=='table' and db.activityNames or {}
 if db.activitiesEnabled==nil then db.activitiesEnabled=true end
 if db.questConfirm==nil then db.questConfirm=true end
 if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
 for _,event in ipairs({'PLAYER_ENTERING_WORLD','ZONE_CHANGED_NEW_AREA','GROUP_ROSTER_UPDATE','QUEST_TURNED_IN','CHAT_MSG_ADDON','ENCOUNTER_END','LFG_COMPLETION_REWARD','PVP_MATCH_COMPLETE','UPDATE_BATTLEFIELD_STATUS'}) do pcall(driver.RegisterEvent,driver,event) end
end
driver:SetScript('OnEvent',function(_,event,...)
 if not Active() then
  if R.DB and (event=='PLAYER_ENTERING_WORLD' or event=='ZONE_CHANGED_NEW_AREA' or event=='GROUP_ROSTER_UPDATE') then
   local instance=Instance();local session=R.DB.activitySession
   if not instance or (session and session.key~=instance.kind..':'..instance.id..':'..instance.difficulty) then R.DB.activitySession=nil end
  end
  return
 end
 if event=='QUEST_TURNED_IN' then A.Quest(...)
 elseif event=='CHAT_MSG_ADDON' then A.Receive(...)
 elseif event=='LFG_COMPLETION_REWARD' then A.Complete('C');if R.DB and R.DB.activitySession then R.DB.activitySession.finished=true end
 elseif event=='ENCOUNTER_END' then local id,name,_,_,success=...;if Public(success) and success==1 and Number(id,10000000) and Text(name) then A.Complete('E',id,name) end
 elseif event=='PVP_MATCH_COMPLETE' then A.Complete('W');if R.DB and R.DB.activitySession then R.DB.activitySession.finished=true end
 elseif event=='UPDATE_BATTLEFIELD_STATUS' then
  local winner=GetBattlefieldWinner and GetBattlefieldWinner();if Public(winner) and (winner==0 or winner==1) then A.Complete('W');if R.DB and R.DB.activitySession then R.DB.activitySession.finished=true end else A.Scan() end
 elseif event=='PLAYER_ENTERING_WORLD' then
  local isLogin,isReload=...
  if Public(isLogin) and Public(isReload) and not isLogin and not isReload and R.DB and R.DB.activitySession and R.DB.activitySession.finished then
   R.DB.activitySession=nil
  end
  Prune();A.Scan()
 else Prune();A.Scan() end
end)
