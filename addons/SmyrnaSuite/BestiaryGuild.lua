local _,Suite=...
local B=Suite.Modules.SmyrnaBestiary
if not B then return end
local C=B.Core
local prefix='SmyrnaLoot1'
local frame=CreateFrame('Frame')
local function Guild()
 if not GetGuildInfo then return end
 local n,_,_,realm=GetGuildInfo('player')
 if not C.Public(n) or type(n)~='string' then return end
 if not C.Public(realm) or type(realm)~='string' then
  local r=GetRealmName and GetRealmName()
  realm=(C.Public(r) and type(r)=='string') and r or ''
 end
 return n..'@'..realm
end
local RECENT=8192
local KEYCAP,ITEMCAP,GUILDCAP=4096,256,8
local rowCache,rowRing,rowSlots,rowCursor,ROW_CACHE_CAP={},{},{},1,64
local function Decode(text)
 local total,body=(text or ''):match('^(%d+)|([%d:,]*)$')
 local hits={};for id,n in (body or ''):gmatch('(%d+):(%d+)') do hits[tonumber(id)]=tonumber(n) end
 return tonumber(total) or 0,hits
end
local function Add(d,build,context,npc,diff,ids,migrating)
 local key=build..':'..context..':'..diff..':'..npc
 if not d.totals[key] then
  if not d.keyCount then d.keyCount=0;for _ in pairs(d.totals) do d.keyCount=d.keyCount+1 end end
  if not migrating and d.keyCount>=KEYCAP then B.GuildCapacityReached=true;return false end
 end
 local total,hits=Decode(d.totals[key]);total=total+1
 local size=0;for _ in pairs(hits) do size=size+1 end
 for _,id in ipairs(ids) do if not hits[id] then size=size+1 end end
 if not migrating and size>ITEMCAP then B.GuildCapacityReached=true;return false end
 for _,id in ipairs(ids) do hits[id]=(hits[id] or 0)+1 end
 local keys={};for id in pairs(hits) do keys[#keys+1]=id end;table.sort(keys)
 local parts={};for _,id in ipairs(keys) do parts[#parts+1]=id..':'..hits[id] end
 if not d.totals[key] then d.keyCount=(d.keyCount or 0)+1 end
 d.totals[key]=total..'|'..table.concat(parts,',')
 d.count=(d.count or 0)+1
 rowCache[key]=nil;rowSlots[key]=nil
 return true
end
local function Remember(d,guid)
 d.recentSlots=d.recentSlots or {}
 local slot=d.cursor or 1;local old=d.queue[slot]
 if old and d.recentSlots[old]==slot then d.recent[old]=nil;d.recentSlots[old]=nil end
 d.queue[slot]=guid;d.recent[guid]=true;d.recentSlots[guid]=slot;d.cursor=slot%RECENT+1
end
local function Store()
 local guild=Guild();if not guild then return end
 local root=B.DB.guildSamples
 if type(root)~='table' or root.version~=2 then
  local old=root;root={version=2,guilds={}}
  if type(old)=='table' and type(old.guild)=='string' then
   local d={totals={},count=0,recent={},queue={},cursor=1};root.guilds[old.guild]=d
   for guid,value in pairs(old.events or {}) do
    local context,npc,diff,build,ids
    if type(value)=='string' then
     local body;context,npc,diff,build,body=value:match('^([MI]%d+)|(%d+)|(%d+)|(%d+)|([%d,]*)$')
     ids={};for id in (body or ''):gmatch('%d+') do ids[#ids+1]=tonumber(id) end
    elseif type(value)=='table' then context,npc,diff,build,ids=unpack(value) end
    if context and npc and diff and build and type(ids)=='table' then Add(d,tostring(build),context,npc,diff,ids,true);Remember(d,guid) end
   end
  end
  B.DB.guildSamples=root
 end
 local d=root.guilds[guild]
 if not d then
  local count=0;for _ in pairs(root.guilds) do count=count+1 end
  if count>=GUILDCAP then B.GuildCapacityReached=true;return end
  d={totals={},count=0,recent={},queue={},cursor=1};root.guilds[guild]=d
 end
 return d
end
function B.GuildRows(context,npc,difficulty)
 local d=Store();if not d then return {} end
 local key=B.DB.build..':'..context..':'..difficulty..':'..npc
 local packed=d.totals[key]
 if not packed then return {} end
 local cached=rowCache[key]
 if cached and cached.raw==packed then return cached.rows end
 local total,hits=Decode(packed)
 local rows={};if total>0 then for id,n in pairs(hits) do rows[#rows+1]={id=id,pct=100*n/total,source='H',hits=n,windows=total} end end
 local old=rowRing[rowCursor]
 if old and rowSlots[old]==rowCursor then rowCache[old]=nil;rowSlots[old]=nil end
 rowRing[rowCursor]=key;rowSlots[key]=rowCursor;rowCursor=rowCursor%ROW_CACHE_CAP+1
 rowCache[key]={raw=packed,rows=rows}
 return rows
end
function B.ReceiveGuild(message,channel,sender)
 if not B.DB or not B.DB.settings.enabled or not B.DB.settings.guildShare or channel~='GUILD' then return false end
 if not C.Public(message) or type(message)~='string' or #message>250 then return false end
 local build,context,diff,guid,body=message:match('^1|(%d+)|([MI]%d+)|(%d+)|([^|]+)|([%d,]*)$')
 local npc=guid and C.NPC(guid);diff=tonumber(diff)
 if build~=B.DB.build or not npc or not C.Number(diff,0,1000) then return false end
 local d=Store();if not d or d.recent[guid] then return false end
 local ids,seen={},{}
 for token in body:gmatch('[^,]+') do local id=tonumber(token);if not C.Number(id,1,10000000) or seen[id] then return false end;seen[id]=true;ids[#ids+1]=id;if #ids>64 then return false end end
 if not Add(d,build,context,npc,diff,ids) then
  if not B.GuildCapacityWarned and B.Say then B.GuildCapacityWarned=true;B.Say('Guild sample storage is full for new entries. Existing data is kept; this sample was skipped.') end
  return false
 end
 Remember(d,guid)
 B.DB.revision=B.DB.revision+1;B.Changed();return true
end
function B.ShareLoot(guid,context,difficulty,items)
 if not B.DB.settings.guildShare or not Guild() then return end
 local ids={};for id in pairs(items) do ids[#ids+1]=id end;table.sort(ids)
 local payload=table.concat({'1',B.DB.build,context,difficulty,guid,table.concat(ids,',')},'|')
 -- One atomic loot window: never transmit an incomplete item list.
 if #payload>250 then return end
 if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return end
 if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(prefix,payload,'GUILD') end
end
frame:RegisterEvent('PLAYER_LOGIN');frame:RegisterEvent('CHAT_MSG_ADDON')
frame:SetScript('OnEvent',function(self,event,p,message,channel,sender)
 if event=='PLAYER_LOGIN' then
  self:UnregisterEvent('PLAYER_LOGIN')
  if B.DB and B.DB.settings.guildShare==nil then B.DB.settings.guildShare=false end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
 elseif C.Public(p) and p==prefix and C.Public(channel) and C.Public(sender) and type(sender)=='string' then
  local first,last
  if UnitFullName then first,last=UnitFullName('player') elseif UnitName then first,last=UnitName('player') end
  local own=Suite.PlayerName(first,last)
  local short=sender:match('^([^-]+)')
  local isSelf=(own and (sender==own or short==own)) or (C.Public(first) and type(first)=='string' and (sender==first or short==first))
  if not isSelf then B.ReceiveGuild(message,channel,sender) end
 end
end)
