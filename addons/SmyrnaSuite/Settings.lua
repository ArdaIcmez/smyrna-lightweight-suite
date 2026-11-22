local _,NS=...
-- Native settings entry is only a small launcher; the main UI stays lazy.
local function Register()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel=CreateFrame("Frame")
    panel:SetScript("OnShow",function(self)
        if self.built then return end;self.built=true
        local title=self:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",20,-20);title:SetText("Smyrna Lightweight Addon Suite")
        local text=self:CreateFontString(nil,"OVERLAY","GameFontHighlight");text:SetPoint("TOPLEFT",20,-55);text:SetText("Manage your Smyrna features.\nOptional databases can also be disabled in WoW AddOns.")
        local button=CreateFrame("Button",nil,self,"UIPanelButtonTemplate");button:SetSize(190,28);button:SetPoint("TOPLEFT",20,-110);button:SetText("Open suite");button:SetScript("OnClick",NS.Open)
    end)
    local category=Settings.RegisterCanvasLayoutCategory(panel,"Smyrna Lightweight Addon Suite")
    Settings.RegisterAddOnCategory(category)
end
local driver=CreateFrame("Frame");driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent",function(self) self:UnregisterEvent("PLAYER_LOGIN");Register() end)
