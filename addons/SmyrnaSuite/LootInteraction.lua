local _,S=...
-- Loot buttons belong to Blizzard. Do not attach item/reagent click handlers
-- to them or keep Suite dialogs above a newly opened loot window.
function S.IsLootInteraction(owner)
 if S.LootOpen or (LootFrame and not (LootFrame.IsForbidden and LootFrame:IsForbidden()) and LootFrame:IsShown()) then return true end
 local frame=owner
 for _=1,16 do
  if not frame or (frame.IsForbidden and frame:IsForbidden()) then break end
  local name=frame.GetName and frame:GetName()
  if S.Public(name) and type(name)=='string' and (name=='LootFrame' or name:match('^LootButton%d+') or name:match('^LootFrame')) then return true end
  frame=frame.GetParent and frame:GetParent()
 end
 return false
end
local dialogs={
 'SmyrnaSuiteHub','SmyrnaSuitePanel','SmyrnaChatMessageEditor','SmyrnaChatCopyWindow','SmyrnaChatSettingsWindow',
 'SmyrnaBestiaryLoot','SmyrnaBestiarySources','SmyrnaRemembranceHistory','SmyrnaWorkshopPanel','SmyrnaUpgraderDetails',
 'SmyrnaFieldDiaryData','SmyrnaFieldDiaryGuildWindow','SmyrnaFieldDiaryManager','SmyrnaBenchmarkWindow','SmyrnaTaylanMenu','SmyrnaAoEPreview',
}
local driver=CreateFrame('Frame')
driver:RegisterEvent('LOOT_OPENED');driver:RegisterEvent('LOOT_CLOSED')
driver:SetScript('OnEvent',function(_,event)
 S.LootOpen=event=='LOOT_OPENED'
 if S.LootOpen then
  for _,name in ipairs(dialogs) do local f=_G[name];if f and f:IsShown() then f:Hide() end end
 end
end)
