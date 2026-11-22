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
        local current
        for i = 1, math.min(GetNumGuildTradeSkill(), 10000) do
            local _, _, _, header, _, _, _, name, fullName, _, _, _, skill = GetGuildTradeSkillInfo(i)
            if Core.Readable(header) and header ~= "" then current = header end
            if current == selected and (Core.Readable(fullName) or Core.Readable(name)) then Add(fullName or name, skill, "game data") end
        end
    end
    if next(db.professionNotes) and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() do
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
    table.sort(rows)
    if #rows == 0 then return "No exposed members for " .. (selected or "this profession") .. ".\n\nIf available, open the game's guild profession list and expand this profession, then Refresh. A blank result does not mean nobody has this profession.", 0 end
    local total = #rows
    while #rows > 100 do rows[#rows] = nil end
    if total > 100 then rows[#rows + 1] = "Showing first 100 of " .. total .. "." end
    return table.concat(rows, "\n"), total
end


local panel,output
function NS.OpenGuildProfessions()
 if not panel then
  panel=CreateFrame("Frame","SmyrnaWorkshopGuild",UIParent,"BackdropTemplate");panel:SetSize(570,450);panel:SetPoint("CENTER");panel:SetFrameStrata("FULLSCREEN_DIALOG");panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});panel:SetBackdropColor(.03,.03,.04,1)
  local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton");close:SetPoint("TOPRIGHT")
  local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-16);title:SetText("Workshop - Guild professions")
  output=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");output:SetPoint("TOPLEFT",18,-155);output:SetWidth(530);output:SetJustifyH("LEFT")
  for i,name in ipairs(NS.professionNames) do
   local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");b:SetSize(170,24);b:SetPoint("TOPLEFT",18+((i-1)%3)*177,-45-math.floor((i-1)/3)*26);b:SetText(name)
   b:SetScript("OnClick",function() local ok,text=pcall(NS.ReadProfessions,name);output:SetText(ok and text or "Profession data unavailable.") end)
  end
  UISpecialFrames[#UISpecialFrames+1]="SmyrnaWorkshopGuild"
 end
 output:SetText("Choose a profession to read exposed guild data. No background queries.");panel:Show()
end
local driver=CreateFrame("Frame");driver:RegisterEvent("PLAYER_LOGIN");driver:SetScript("OnEvent",function(self)
 self:UnregisterEvent("PLAYER_LOGIN")
 NS.DB.professionNotes=NS.DB.professionNotes or {}
 if type(SmyrnaChatDB)=="table" and type(SmyrnaChatDB.professionNotes)=="table" then for k,v in pairs(SmyrnaChatDB.professionNotes) do if NS.DB.professionNotes[k]==nil then NS.DB.professionNotes[k]=v end end;SmyrnaChatDB.professionNotes=nil;SmyrnaChatDB.professions=nil end
end)
