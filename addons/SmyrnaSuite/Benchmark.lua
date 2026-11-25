local _,NS=...
-- On-demand benchmark & memory inspector (/smyrna bench or /smyrna mem).
-- Zero idle overhead; cleans up temporary benchmark allocations before returning.
local window
local PACKAGES={"SmyrnaSuite","SmyrnaWorldDB","SmyrnaBestiaryDB","SmyrnaWorkshopDB","SmyrnaEquipmentDB","SmyrnaRemembranceDB","SmyrnaEmoty"}

local function NowMs()
    if debugprofilestop then return debugprofilestop() end
    return (GetTime and GetTime() or 0)*1000
end

local function CountKeys(tbl)
    if type(tbl)~="table" then return 0 end
    local n=0;for _ in pairs(tbl) do n=n+1 end;return n
end

local function CollectGC()
    if collectgarbage then
        collectgarbage("collect")
        collectgarbage("collect")
    end
end

local function Measure(label,iterations,fn)
    CollectGC()
    local startMem=collectgarbage and collectgarbage("count") or 0
    local t0=NowMs()
    local ok,err=pcall(fn,iterations)
    local elapsed=NowMs()-t0
    local deltaMem=(collectgarbage and collectgarbage("count") or 0)-startMem
    if not ok then
        return string.format("%-28s  ERROR: %s",label,tostring(err))
    end
    local perOp=iterations>0 and (elapsed/iterations) or elapsed
    return string.format("%-28s  %6.2f ms total  (%6.4f ms/op, %+.1f KiB temp)",label,elapsed,perOp,deltaMem)
end

function NS.TrimAllCaches()
    if NS.WorldDB and NS.WorldDB.TrimCache then NS.WorldDB.TrimCache() end
    if NS.Equipment and NS.Equipment.TrimCache then NS.Equipment.TrimCache() end
    local bestiary=NS.Modules.SmyrnaBestiary
    if bestiary and bestiary.Core and bestiary.Core.ClearCache then bestiary.Core.ClearCache() end
    if NS.BestiaryDefenseReference and NS.BestiaryDefenseReference.ClearCache then NS.BestiaryDefenseReference.ClearCache() end
    local workshop=NS.Modules.SmyrnaWorkshop
    if workshop and workshop.ClearCaches then workshop.ClearCaches() end
    if NS.Market and NS.Market.KV and NS.Market.KV.Invalidate then NS.Market.KV.Invalidate() end
    CollectGC()
end

local function AppendMemory(lines,heading)
    local api=C_AddOns or {}
    local updateMem=api.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage
    local getMem=api.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    local isLoaded=api.IsAddOnLoaded or IsAddOnLoaded
    if not (updateMem and getMem) then return end
    updateMem()
    lines[#lines+1]=heading
    local total=0
    for _,pkg in ipairs(PACKAGES) do
        local kb=getMem(pkg) or 0
        local loaded=isLoaded and isLoaded(pkg)
        total=total+kb
        lines[#lines+1]=string.format("  %-22s %8.1f KiB  (%5.2f MiB)  %s",pkg,kb,kb/1024,loaded and "loaded" or "unloaded")
    end
    lines[#lines+1]=string.format("  %-22s %8.1f KiB  (%5.2f MiB)","TOTAL",total,total/1024)
    lines[#lines+1]=""
end

local function OpenReport(text)
    if not window then
        window=CreateFrame("Frame","SmyrnaBenchmarkWindow",UIParent,"BackdropTemplate")
        window:SetSize(660,460);window:SetPoint("CENTER");window:SetFrameStrata("FULLSCREEN_DIALOG");window:SetFrameLevel(220);window:SetClampedToScreen(true)
        window:SetMovable(true);window:EnableMouse(true);window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        window:SetScript("OnDragStop",window.StopMovingOrSizing)
        NS.StylePanel(window,true);NS.HeaderStrip(window,40);NS.CloseButton(window)
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-12);title:SetText("Smyrna Suite Benchmark & Memory");title:SetTextColor(1,.86,.48)
        local help=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");help:SetPoint("TOPLEFT",16,-48);help:SetText("Ctrl+A, Ctrl+C to copy. /smyrna bench or /smyrna mem.");help:SetTextColor(.70,.75,.84)
        local rerun=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");rerun:SetSize(76,22);rerun:SetPoint("TOPRIGHT",-16,-44);rerun:SetText("Re-run");NS.StyleButton(rerun)
        rerun:SetScript("OnClick",function() NS.RunBenchmark(false) end)
        local trim=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");trim:SetSize(136,22);trim:SetPoint("RIGHT",rerun,"LEFT",-6,0);trim:SetText("Trim caches & GC");NS.StyleButton(trim)
        trim:SetScript("OnClick",function() NS.TrimAllCaches();NS.RunBenchmark(true) end)
        local scroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",16,-74);scroll:SetPoint("BOTTOMRIGHT",-36,16)
        local edit=CreateFrame("EditBox",nil,scroll);edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal);edit:SetWidth(600);edit:SetHeight(360);edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed",function() window:Hide() end)
        scroll:SetScrollChild(edit);window.edit=edit;window.scroll=scroll
        window:SetScript("OnHide",function() edit:ClearFocus() end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaBenchmarkWindow"
    end
    window:Show()
    window.edit:SetText(text)
    window.edit:SetCursorPosition(0)
    window.scroll:UpdateScrollChildRect()
    window.scroll:SetVerticalScroll(0)
end

function NS.RunBenchmark(memoryOnly)
    local lines={"SMYRNA SUITE MEMORY & PERFORMANCE REPORT",""}
    CollectGC()
    AppendMemory(lines,"ADDON MEMORY BREAKDOWN (after GC)")

    lines[#lines+1]="INTERNAL STORE & CACHE COUNTS"
    if NS.WorldDB then
        local st=NS.WorldDB.CacheStats()
        local hits,misses=0,0
        for _,k in ipairs({"N","Q","I","O","D","Z"}) do hits=hits+(st[k].hits or 0); misses=misses+(st[k].misses or 0) end
        local tot=hits+misses
        local rate=tot>0 and (100*hits/tot) or 0
        lines[#lines+1]=string.format("  WorldDB     : %s  (LRU N:%d/%d Q:%d/%d I:%d/%d O:%d/%d D:%d/%d Z:%d/%d | HitRate %.1f%%)",
            NS.WorldDB.loaded and "loaded" or "unloaded",
            st.N.size,st.N.cap,st.Q.size,st.Q.cap,st.I.size,st.I.cap,st.O.size,st.O.cap,st.D.size,st.D.cap,st.Z.size,st.Z.cap,rate)
        lines[#lines+1]="  Shared Refs : WorldDB -> Quests, Journal, Market, Discoveries | Equipment -> Upgrader, Journal | Market -> Upgrader, Tooltips"
    end
    local bestiary=NS.Modules.SmyrnaBestiary
    if bestiary then
        lines[#lines+1]=string.format("  Bestiary    : %d raw NPCs, %d ref items, %d saved records",CountKeys(bestiary.Raw),CountKeys(bestiary.Items),bestiary.DB and bestiary.DB.count or 0)
    end
    local workshop=NS.Modules.SmyrnaWorkshop
    if workshop then
        lines[#lines+1]=string.format("  Workshop    : %d ref recipes, %d index mats, %d learned",workshop.References and #workshop.References or 0,CountKeys(workshop.Index),workshop.recipeCount or 0)
    end
    local equip=NS.Equipment
    if equip then
        lines[#lines+1]=string.format("  Equipment   : %d catalog records, %d cached rows",equip.records and (equip.count or CountKeys(equip.records)) or 0,CountKeys(equip.cache))
    end
    local diary=NS.Modules.SmyrnaFieldDiary
    if diary and diary.DB then
        lines[#lines+1]=string.format("  FieldDiary  : %d own cells, %d shared cells",diary.DB.own and diary.DB.own.count or 0,diary.DB.shared and diary.DB.shared.count or 0)
    end
    local rem=NS.Modules.SmyrnaRemembrance
    if rem and rem.DB then
        lines[#lines+1]=string.format("  Remembrance : %d remembered records",rem.Count or CountKeys(rem.DB.records))
    end
    if NS.Market and NS.Market.KV and NS.Market.KV.Stats then
        local ks=NS.Market.KV.Stats()
        lines[#lines+1]=string.format("  Market KV   : %d items (%d w/ hist), %d shards, %.1f KiB packed, LRU %d/%d",
            ks.items or 0,ks.histItems or 0,ks.shards or 0,(ks.kvBytes or 0)/1024,ks.cacheSize or 0,ks.cacheCap or 0)
    end
    lines[#lines+1]=""

    if not memoryOnly then
        lines[#lines+1]="MODULE HOT-PATH MICROBENCHMARKS (loaded data only; no extra DBs loaded)"
        local chat=NS.Modules.SmyrnaChat
        if chat and chat.Core then
            local sample="|cff888888[12:34:56]|r |cff69ccf0|Hplayer:Jaina-Forever:1|h[Jaina]|h|r: Portals are ready!"
            lines[#lines+1]=Measure("Chat.Core.Plain (x200)",200,function(n) for _=1,n do chat.Core.Plain(sample) end end)
            if chat.TimeZones then
                local now=GetServerTime and GetServerTime() or time()
                lines[#lines+1]=Measure("Chat.TimeZones.Lines (x200)",200,function(n) for _=1,n do chat.TimeZones.Lines(now) end end)
            end
        end
        if diary and diary.DB and diary.Core then
            local pos=diary.Position and diary.Position()
            local mapID=pos and pos.map or 1434
            local w,h=(pos and pos.width or 3000),(pos and pos.height or 2000)
            lines[#lines+1]=Measure("FieldDiary.Aggregate (x50)",50,function(n) for _=1,n do diary.Core.Aggregate(diary.DB,mapID,w,h) end end)
        end
        local sampleNPC=bestiary and next(bestiary.Raw or {})
        if bestiary and bestiary.DB and bestiary.Core and sampleNPC then
            local ctx,diff=(bestiary.Context and bestiary.Context()) or "M1429",0
            lines[#lines+1]=Measure("Bestiary.Drops warm (x100)",100,function(n)
                bestiary.Core.Drops(sampleNPC,ctx,diff,bestiary.DB.settings)
                for _=1,n do bestiary.Core.Drops(sampleNPC,ctx,diff,bestiary.DB.settings) end
            end)
            lines[#lines+1]=Measure("Bestiary.Drops cold (x15)",15,function(n)
                for _=1,n do bestiary.Core.ClearCache();bestiary.Core.Drops(sampleNPC,ctx,diff,bestiary.DB.settings) end
            end)
        else
            lines[#lines+1]="Bestiary.Drops               (SmyrnaBestiaryDB not loaded yet)"
        end
        local sampleMat=workshop and workshop.Index and next(workshop.Index)
        if workshop and workshop.Uses and sampleMat then
            lines[#lines+1]=Measure("Workshop.Uses (x100)",100,function(n) for _=1,n do workshop.Uses(sampleMat) end end)
        else
            lines[#lines+1]="Workshop.Uses                (SmyrnaWorkshopDB not loaded yet)"
        end
        if equip and equip.records then
            local ids={};for id in pairs(equip.records) do ids[#ids+1]=id;if #ids>=32 then break end end
            lines[#lines+1]=Measure("Equipment.Get warm (x200)",200,function(n)
                for i=1,n do equip.Get(ids[(i-1)%#ids+1],true) end
            end)
            local upg=NS.Modules.SmyrnaUpgrader
            local profile=upg and upg.Profile and upg.Profile()
            if profile and ids[1] then
                local row=equip.Get(ids[1],true)
                lines[#lines+1]=Measure("Upgrader.Score (x200)",200,function(n) for _=1,n do upg.Score(row,profile) end end)
            end
        else
            lines[#lines+1]="Equipment / Upgrader         (SmyrnaEquipmentDB not loaded yet)"
        end
        if rem and rem.DB then
            lines[#lines+1]=Measure("Remembrance.Page (x30)",30,function(n) for _=1,n do rem.Page("all",nil) end end)
        end
        lines[#lines+1]=""
        lines[#lines+1]="SYNTHETIC LOAD TEST (2,500+ cross-module lookups)"
        if NS.WorldDB and NS.WorldDB.loaded then
            local dlist=NS.WorldDB.Dungeons() or {}
            local slug=dlist[1] and dlist[1].s
            local mapID=(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 1429
            lines[#lines+1]=Measure("WorldDB.Zone O(1) (x200)",200,function(n) for _=1,n do NS.WorldDB.Zone(mapID) end end)
            if slug then
                lines[#lines+1]=Measure("WorldDB.Dungeon warm (x200)",200,function(n) for _=1,n do NS.WorldDB.Dungeon(slug) end end)
            end
            lines[#lines+1]=Measure("WorldDB.Item LRU (x500)",500,function(n)
                local sample={25,35,36,37,38,159,117,2070,4540,7005}
                for i=1,n do NS.WorldDB.Item(sample[(i-1)%#sample+1]) end
            end)
            lines[#lines+1]=Measure("WorldDB.Quest LRU (x500)",500,function(n)
                local z=NS.WorldDB.Zone(mapID)
                local qs=(z and z.q) or {783,7,15,21,33}
                local lim=math.min(#qs,10)
                if lim>0 then for i=1,n do NS.WorldDB.Quest(qs[(i-1)%lim+1]) end end
            end)
        else
            lines[#lines+1]="WorldDB Load Test            (SmyrnaWorldDB not loaded yet — open Quests or Journal first)"
        end
        if NS.Market and NS.Market.Price then
            lines[#lines+1]=Measure("Market.Price lookup (x500)",500,function(n) for i=1,n do NS.Market.Price(2589+(i%20)) end end)
            if NS.Market.KV and NS.Market.KV.Series then
                lines[#lines+1]=Measure("Market.KV.Series (x200)",200,function(n) for i=1,n do NS.Market.KV.Series(2589+(i%20)) end end)
            end
        end
        local aggro=NS.Modules.SmyrnaAggroMate
        if aggro and aggro.AggroRadius then
            lines[#lines+1]=Measure("AggroMate.Radius (x1000)",1000,function(n) for i=1,n do aggro.AggroRadius(20+(i%15),25) end end)
        end
        lines[#lines+1]=""
        -- Clean up all temporary benchmark caches & garbage before reporting final footprint.
        NS.TrimAllCaches()
        AppendMemory(lines,"POST-BENCHMARK MEMORY (after cache trim & GC)")
    end

    local report=table.concat(lines,"\n")
    OpenReport(report)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna:|r Benchmark/memory report ready (temporary benchmark garbage collected).") end
    return report
end
