local _,Suite=...
local NS=Suite.Modules.SmyrnaFieldDiary
if not NS then return end
local C=NS.Core
local KIND_LABELS={mine="Mine",herb="Herb",skin="Skin",fish="Fish",rare="Rare"}
local KIND_FULL={mine="Mining",herb="Herbalism",skin="Skinning",fish="Fishing",rare="Rare"}
local KIND_HEX={mine="ffb333",herb="33ff66",skin="cc8040",fish="33bfff",rare="c8cdd6"}

local window,rows,scroll,canvas,searchBox,summaryText
local sourceBtns,kindBtns={},{}
local deleteMatchBtn,clearGuildBtn,clearOwnBtn,pruneBtn
local filterSource,filterKind,searchQuery="all","all",""
local confirmAction,confirmExpires,confirmGen=nil,0,0
local searchGen=0
local currentMatches={}

local function RecordName(r)
    if NS.SampleNameForRecord then return NS.SampleNameForRecord(r) end
    if type(r[14])=="table" then
        for _,v in pairs(r[14]) do if type(v)=="string" and v~="" then return v end end
    end
    return KIND_FULL[r[4]] or "Discovery"
end

local function NotifyChanged()
    NS.DB.revision=(NS.DB.revision or 0)+1
    NS.Dirty()
    if NS.RefreshOptions then NS.RefreshOptions() end
    if NS.RefreshGuildWindow then NS.RefreshGuildWindow() end
    if NS.RefreshManager then NS.RefreshManager() end
end

local function ResetConfirm()
    confirmAction=nil; confirmExpires=0
end

local function CollectEntries()
    local list={}
    local mapNames={}
    local q=string.lower((searchQuery or ""):gsub("^%s+",""):gsub("%s+$",""))
    local function Scan(store,sourceTag)
        if not store or not store.records then return end
        for key,r in pairs(store.records) do
            local k=r[4]
            if C.kinds[k] and (filterKind=="all" or filterKind==k) then
                if not mapNames[r[1]] then
                    local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r[1])
                    mapNames[r[1]]=(info and info.name) or ("Map "..tostring(r[1]))
                end
                local zone=mapNames[r[1]]
                local name=RecordName(r)
                local who=sourceTag=="shared" and ((type(r[12])=="string" and r[12]~="") and (r[12]:match("^([^-]+)") or r[12]) or "Guildmate") or "Personal"
                local ok=true
                if q~="" then
                    local hay=string.lower(zone.." "..name.." "..who.." "..(KIND_FULL[k] or k))
                    ok=hay:find(q,1,true)~=nil
                end
                if ok then
                    local coords=""
                    if C.Number(r[16],0,10000) and C.Number(r[17],0,10000) then
                        coords=string.format("%.1f, %.1f",r[16]/100,r[17]/100)
                    else
                        local w,h=(NS.MapWorldSize and NS.MapWorldSize(r[1])) or (C_Map and C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(r[1]))
                        coords=(C.Number(w,1,200000) and C.Number(h,1,200000)) and string.format("%.1f, %.1f",100*(r[2]*50+25)/w,100*(r[3]*50+25)/h) or ""
                    end
                    list[#list+1]={
                        store=store,
                        source=sourceTag,
                        key=key,
                        kind=k,
                        name=name,
                        who=who,
                        zone=zone,
                        coords=coords,
                        samples=r[5] or 1,
                        last=r[9] or 0,
                    }
                end
            end
        end
    end
    if filterSource=="all" or filterSource=="own" then Scan(NS.DB.own,"own") end
    if filterSource=="all" or filterSource=="shared" then Scan(NS.DB.shared,"shared") end
    table.sort(list,function(a,b)
        if a.last~=b.last then return a.last>b.last end
        if a.samples~=b.samples then return a.samples>b.samples end
        return a.name<b.name
    end)
    return list
end

local function MakeRow(i)
    local row=CreateFrame("Frame",nil,canvas,"BackdropTemplate")
    row:SetSize(714,28)
    Suite.StyleCard(row,.076,.088,.120)
    row.tag=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.tag:SetPoint("LEFT",8,0); row.tag:SetWidth(42); row.tag:SetJustifyH("LEFT")
    row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    row.name:SetPoint("LEFT",54,0); row.name:SetWidth(200); row.name:SetJustifyH("LEFT"); row.name:SetMaxLines(1)
    row.who=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.who:SetPoint("LEFT",258,0); row.who:SetWidth(116); row.who:SetJustifyH("LEFT"); row.who:SetMaxLines(1)
    row.place=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.place:SetPoint("LEFT",378,0); row.place:SetWidth(190); row.place:SetJustifyH("LEFT"); row.place:SetMaxLines(1); row.place:SetTextColor(.78,.82,.88)
    row.count=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.count:SetPoint("LEFT",572,0); row.count:SetWidth(68); row.count:SetJustifyH("RIGHT"); row.count:SetTextColor(1,.86,.48)
    row.del=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
    row.del:SetSize(56,20); row.del:SetPoint("RIGHT",-8,0); row.del:SetText("Delete"); Suite.StyleButton(row.del)
    row.del:SetScript("OnClick",function(self)
        local entry=self.entry
        if not entry then return end
        ResetConfirm()
        if C.Delete and C.Delete(entry.store,entry.key) then
            NotifyChanged()
        end
    end)
    rows[i]=row
    return row
end

local function UpdateActionLabels()
    local now=GetTime()
    if confirmAction and now>confirmExpires then ResetConfirm() end
    local n=#currentMatches
    deleteMatchBtn:SetText(confirmAction=="match" and ("Confirm delete ("..n..")?") or ("Delete matching ("..n..")"))
    deleteMatchBtn:SetEnabled(n>0)
    clearGuildBtn:SetText(confirmAction=="guild" and "Confirm clear Guild?" or "Clear all Guild")
    clearGuildBtn:SetEnabled((NS.DB.shared and NS.DB.shared.count or 0)>0)
    clearOwnBtn:SetText(confirmAction=="own" and "Confirm clear Personal?" or "Clear all Personal")
    clearOwnBtn:SetEnabled((NS.DB.own and NS.DB.own.count or 0)>0)
end

function NS.RefreshManager()
    if not window or not window:IsShown() or not NS.DB then return end
    for k,b in pairs(sourceBtns) do Suite.SetButtonSelected(b,filterSource==k) end
    for k,b in pairs(kindBtns) do Suite.SetButtonSelected(b,filterKind==k) end
    currentMatches=CollectEntries()
    local totalOwn=NS.DB.own and NS.DB.own.count or 0
    local totalShared=NS.DB.shared and NS.DB.shared.count or 0
    local shown=math.min(#currentMatches,200)
    local countText=#currentMatches>shown and ("Showing "..shown.." of "..#currentMatches.." matching entries") or ("Showing "..#currentMatches.." matching entries")
    summaryText:SetText(string.format("%s  (%d personal, %d guild total). Use filters + Delete matching, or delete individual rows below.",countText,totalOwn,totalShared))
    UpdateActionLabels()
    for i=1,math.max(shown,#rows) do
        local e=i<=shown and currentMatches[i] or nil
        local row=rows[i] or MakeRow(i)
        if e then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*32)
            row.tag:SetText("|cff"..(KIND_HEX[e.kind] or "ffffff")..KIND_LABELS[e.kind].."|r")
            row.name:SetText(e.name)
            if e.source=="shared" then
                row.who:SetText("by "..e.who); row.who:SetTextColor(.58,.86,1)
            else
                row.who:SetText("Personal"); row.who:SetTextColor(.47,.88,.62)
            end
            row.place:SetText(e.zone..(e.coords~="" and (" ("..e.coords..")") or ""))
            row.count:SetText(e.samples..(e.samples==1 and " sample" or " samples"))
            row.del.entry=e
            row:Show()
        else
            row.del.entry=nil; row:Hide()
        end
    end
    canvas:SetHeight(math.max(290,shown*32))
    scroll:UpdateScrollChildRect()
end

local function ConfirmOrRun(action,fn)
    local now=GetTime()
    if confirmAction==action and now<=confirmExpires then
        confirmGen=confirmGen+1
        ResetConfirm()
        fn()
    else
        confirmAction=action; confirmExpires=now+6; confirmGen=confirmGen+1
        local tok=confirmGen
        UpdateActionLabels()
        if C_Timer and C_Timer.After then
            C_Timer.After(6.1,function()
                if tok==confirmGen and window and window:IsShown() then ResetConfirm(); UpdateActionLabels() end
            end)
        end
    end
end

function NS.OpenManager(zoneQuery,kindFilter)
    if not NS.DB then return end
    if not window then
        rows={}
        window=CreateFrame("Frame","SmyrnaFieldDiaryManager",UIParent,"BackdropTemplate")
        window:SetSize(780,560); window:SetPoint("CENTER"); window:SetFrameStrata("FULLSCREEN_DIALOG"); window:SetFrameLevel(190); window:SetClampedToScreen(true)
        window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        window:SetScript("OnDragStop",window.StopMovingOrSizing)
        Suite.StylePanel(window,true); Suite.HeaderStrip(window,42); Suite.CloseButton(window)
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-12); title:SetText("Field Diary - Manage & Delete Data"); title:SetTextColor(1,.86,.48)

        -- Row 1: Source filter + Search box
        local sx=16
        local sLbl=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); sLbl:SetPoint("TOPLEFT",sx,-52); sLbl:SetText("Source:"); sLbl:SetTextColor(.93,.77,.40); sx=sx+52
        for _,entry in ipairs({{"all","All",44},{"own","Personal",72},{"shared","Guild",56}}) do
            local key,label,w=entry[1],entry[2],entry[3]
            local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); b:SetSize(w,22); b:SetPoint("TOPLEFT",sx,-48); b:SetText(label); Suite.StyleButton(b)
            b:SetScript("OnClick",function() filterSource=key; ResetConfirm(); NS.RefreshManager() end)
            sourceBtns[key]=b; sx=sx+w+5
        end

        local qLbl=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); qLbl:SetPoint("TOPLEFT",340,-52); qLbl:SetText("Filter zone / item / player:"); qLbl:SetTextColor(.93,.77,.40)
        searchBox=CreateFrame("EditBox",nil,window,"InputBoxTemplate")
        searchBox:SetSize(220,22); searchBox:SetPoint("TOPLEFT",496,-48); searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged",function(self)
            searchQuery=self:GetText() or ""; ResetConfirm()
            searchGen=searchGen+1; local tok=searchGen
            if C_Timer and C_Timer.After then
                C_Timer.After(.15,function() if tok==searchGen and window and window:IsShown() then NS.RefreshManager() end end)
            else NS.RefreshManager() end
        end)
        searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        local clearSearch=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); clearSearch:SetSize(44,22); clearSearch:SetPoint("LEFT",searchBox,"RIGHT",4,0); clearSearch:SetText("Clear"); Suite.StyleButton(clearSearch)
        clearSearch:SetScript("OnClick",function() searchBox:SetText(""); searchBox:ClearFocus() end)

        -- Row 2: Datapoint kind filter
        local kx=16
        local kLbl=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); kLbl:SetPoint("TOPLEFT",kx,-82); kLbl:SetText("Type:"); kLbl:SetTextColor(.93,.77,.40); kx=kx+52
        for _,entry in ipairs({{"all","All",44},{"mine","Mining",64},{"herb","Herbs",58},{"skin","Skinning",70},{"fish","Fishing",64},{"rare","Rares",58}}) do
            local key,label,w=entry[1],entry[2],entry[3]
            local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); b:SetSize(w,22); b:SetPoint("TOPLEFT",kx,-78); b:SetText(label); Suite.StyleButton(b)
            b:SetScript("OnClick",function() filterKind=key; ResetConfirm(); NS.RefreshManager() end)
            kindBtns[key]=b; kx=kx+w+5
        end

        -- Row 3: Bulk delete controls (2-click safe confirm)
        Suite.OptionSection(window,"Bulk Actions (click twice to confirm)",16,-110,748)
        deleteMatchBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); deleteMatchBtn:SetSize(188,24); deleteMatchBtn:SetPoint("TOPLEFT",16,-130); Suite.StyleButton(deleteMatchBtn)
        deleteMatchBtn:SetScript("OnClick",function()
            ConfirmOrRun("match",function()
                local removed=0
                for _,e in ipairs(currentMatches) do
                    if C.Delete and C.Delete(e.store,e.key) then removed=removed+1 end
                end
                NS.Say("Deleted "..removed.." matching field diary entries.")
                NotifyChanged()
            end)
        end)

        pruneBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); pruneBtn:SetSize(134,24); pruneBtn:SetPoint("LEFT",deleteMatchBtn,"RIGHT",8,0); pruneBtn:SetText("Clear old (30d+)"); Suite.StyleButton(pruneBtn)
        pruneBtn:SetScript("OnClick",function()
            ResetConfirm(); NS.Prune(); NotifyChanged()
        end)

        clearGuildBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); clearGuildBtn:SetSize(180,24); clearGuildBtn:SetPoint("LEFT",pruneBtn,"RIGHT",8,0); Suite.StyleButton(clearGuildBtn)
        clearGuildBtn:SetScript("OnClick",function()
            ConfirmOrRun("guild",function()
                NS.DB.shared=C.NewStore()
                NS.Say("Cleared all downloaded guild samples.")
                NotifyChanged()
            end)
        end)

        clearOwnBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); clearOwnBtn:SetSize(186,24); clearOwnBtn:SetPoint("LEFT",clearGuildBtn,"RIGHT",8,0); Suite.StyleButton(clearOwnBtn)
        clearOwnBtn:SetScript("OnClick",function()
            ConfirmOrRun("own",function()
                NS.DB.own=C.NewStore()
                NS.Say("Cleared all personal field diary finds.")
                NotifyChanged()
            end)
        end)

        Suite.OptionSection(window,"Saved Entries",16,-166,748)
        summaryText=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); summaryText:SetPoint("TOPLEFT",18,-184); summaryText:SetWidth(744); summaryText:SetJustifyH("LEFT"); summaryText:SetTextColor(.74,.80,.88)

        scroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-206); scroll:SetSize(732,336)
        canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(714,336); scroll:SetScrollChild(canvas)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*40))) end
        end)

        window:SetScript("OnHide",function() ResetConfirm(); if searchBox then searchBox:ClearFocus() end end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaFieldDiaryManager"
    end
    if type(zoneQuery)=="string" then
        searchQuery=zoneQuery
        if searchBox then searchBox:SetText(zoneQuery) end
    end
    if kindFilter and (kindFilter=="all" or C.kinds[kindFilter]) then
        filterKind=kindFilter
    end
    ResetConfirm()
    window:Show()
    NS.RefreshManager()
end
