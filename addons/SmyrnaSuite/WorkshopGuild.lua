local _,Suite=...
local NS=Suite.Modules.SmyrnaWorkshop
if not NS then return end
local Core={Readable=function(v) return not (issecretvalue and issecretvalue(v)) and type(v)=="string" end,Trim=function(v) return (v:gsub("^%s+",""):gsub("%s+$","")) end,Key=function(v) return (v:lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")) end}
NS.professionNames = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring", "Cooking", "First Aid", "Fishing" }
local valid = {}
for _, name in ipairs(NS.professionNames) do valid[string.lower(name)] = name end

function NS.ParseProfessions(text)
    local names, seen = {}, {}
    for token in text:gmatch("[^,]+") do
        local name = valid[string.lower(Core.Trim(token))]
        if not name then return nil, "Use listed profession names, separated by commas." end
        if not seen[name] then names[#names + 1] = name; seen[name] = true end
    end
    if #names > 6 then return nil, "At most six professions per person." end
    return table.concat(names, ", ")
end

-- Read only on explicit refresh. No background cache, events, expansion or queries.
function NS.ReadProfessions(selected)
    local db = NS.DB;db.professionNotes=db.professionNotes or {}
    if C_TradeSkillUI and C_TradeSkillUI.IsGuildTradeSkillsEnabled then
        local ok,enabled=pcall(C_TradeSkillUI.IsGuildTradeSkillsEnabled)
        if ok and enabled==false then return "This client does not expose guild profession lists. Smyrna cannot determine other players' professions automatically.",0 end
    end
    if not GetNumGuildTradeSkill or not GetGuildTradeSkillInfo then return "Guild profession data is unavailable in this client.",0 end
    local rows, seen = {}, {}
    local function Add(name, skill, source)
        if not Core.Readable(name) or name == "" then return end
        local key = Core.Key(name)
        if seen[key] then return end
        seen[key] = true
        rows[#rows + 1] = name .. (type(skill) == "number" and (" (" .. skill .. ")") or "") .. " - " .. source
    end
    -- Only consume already exposed profession rows; collapsed headers may omit names.
    if GetNumGuildTradeSkill and GetGuildTradeSkillInfo then
        local count=GetNumGuildTradeSkill()
        if not (issecretvalue and issecretvalue(count)) and type(count)=="number" then
            local current
            for i = 1, math.min(count, 10000) do
                local _, _, _, header, _, _, _, name, fullName, _, _, _, skill = GetGuildTradeSkillInfo(i)
                if Core.Readable(header) and header ~= "" then current = header end
                if current == selected then
                    local picked = (Core.Readable(fullName) and fullName ~= "" and fullName) or (Core.Readable(name) and name ~= "" and name) or nil
                    local safeSkill = (not (issecretvalue and issecretvalue(skill)) and type(skill) == "number") and skill or nil
                    if picked then Add(picked, safeSkill, "game data") end
                end
            end
        end
    end
    if next(db.professionNotes) and GetNumGuildMembers and GetGuildRosterInfo then
        local totalMembers=GetNumGuildMembers()
        if not (issecretvalue and issecretvalue(totalMembers)) and type(totalMembers)=="number" then
            for i = 1, totalMembers do
                local name = GetGuildRosterInfo(i)
                if Core.Readable(name) then
                    local short = name:match("^([^-]+)")
                    local record = db.professionNotes[Core.Key(name)] or (short and db.professionNotes[Core.Key(short)])
                    if type(record) == "string" then
                        for token in record:gmatch("[^,]+") do
                            if Core.Trim(token) == selected then Add(name, nil, "personal record"); break end
                        end
                    end
                end
            end
        end
    end
    table.sort(rows)
    if #rows == 0 then return "No exposed members for " .. (selected or "this profession") .. ".\n\nIf available, open the game's guild profession list and expand this profession, then Refresh. A blank result does not mean nobody has this profession.", 0 end
    local total = #rows
    while #rows > 100 do rows[#rows] = nil end
    if total > 100 then rows[#rows + 1] = "Showing first 100 of " .. total .. "." end
    return table.concat(rows, "\n"), total
end


local panel,output,outScroll,outCanvas
local function SetOutputText(text)
 output:SetText(text)
 if outCanvas and outScroll then
  outCanvas:SetHeight(math.max(216,(output:GetStringHeight() or 20)+18))
  outScroll:UpdateScrollChildRect()
  outScroll:SetVerticalScroll(0)
 end
end
function NS.OpenGuildProfessions()
 if not panel then
  panel=CreateFrame("Frame","SmyrnaWorkshopGuild",UIParent,"BackdropTemplate");panel:SetSize(570,450);panel:SetPoint("CENTER");panel:SetFrameStrata("FULLSCREEN_DIALOG");panel:SetClampedToScreen(true)
  Suite.StylePanel(panel,true)
  Suite.CloseButton(panel)
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-14);title:SetText("Workshop - Guild Professions");title:SetTextColor(1,.86,.48)
  Suite.OptionSection(panel,"Professions",16,-40,538)
  for i,name in ipairs(NS.professionNames) do
   local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");b:SetSize(172,24);b:SetPoint("TOPLEFT",16+((i-1)%3)*180,-58-math.floor((i-1)/3)*28);b:SetText(name);Suite.StyleButton(b)
   b:SetScript("OnClick",function() local ok,text=pcall(NS.ReadProfessions,name);SetOutputText(ok and text or "Profession data unavailable.") end)
  end
  Suite.OptionSection(panel,"Exposed Guild Roster Results",16,-176,538)
  local card=CreateFrame("Frame",nil,panel,"BackdropTemplate");card:SetPoint("TOPLEFT",16,-196);card:SetSize(538,238);Suite.StyleCard(card,.074,.086,.118)
  outScroll=CreateFrame("ScrollFrame",nil,card,"UIPanelScrollFrameTemplate");outScroll:SetPoint("TOPLEFT",8,-8);outScroll:SetPoint("BOTTOMRIGHT",-28,8)
  outCanvas=CreateFrame("Frame",nil,outScroll);outCanvas:SetSize(492,216);outScroll:SetScrollChild(outCanvas)
  outScroll:EnableMouseWheel(true)
  outScroll:SetScript("OnMouseWheel",function(self,delta)
   local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
   if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*36))) end
  end)
  output=outCanvas:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");output:SetPoint("TOPLEFT",4,-2);output:SetWidth(484);output:SetJustifyH("LEFT")
  UISpecialFrames[#UISpecialFrames+1]="SmyrnaWorkshopGuild"
 end
 SetOutputText("Choose a profession to read exposed guild data. No background queries.");panel:Show()
end
local driver=CreateFrame("Frame");driver:RegisterEvent("PLAYER_LOGIN");driver:SetScript("OnEvent",function(self)
 self:UnregisterEvent("PLAYER_LOGIN")
 if not NS.DB then return end
 NS.DB.professionNotes=NS.DB.professionNotes or {}
 if type(SmyrnaChatDB)=="table" and type(SmyrnaChatDB.professionNotes)=="table" then for k,v in pairs(SmyrnaChatDB.professionNotes) do if NS.DB.professionNotes[k]==nil then NS.DB.professionNotes[k]=v end end;SmyrnaChatDB.professionNotes=nil;SmyrnaChatDB.professions=nil end
end)
