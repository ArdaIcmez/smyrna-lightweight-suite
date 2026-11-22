import unittest
from lua_harness import upgrader_runtime


class UpgraderTests(unittest.TestCase):
    def setUp(self):
        self.l = upgrader_runtime()

    def test_no_pawn_character_hover_and_details(self):
        self.l.execute('''
assert(PawnCommon==nil and PawnGetItemValue==nil)
local u=Suite.Modules.SmyrnaUpgrader;local owner=CreateFrame('Button','CharacterChestSlot')
GameTooltip:SetOwner(owner);GameTooltip:SetInventoryItem('player',5)
u.Hover(owner,5);RunTimers()
local result=u.LastResult;assert(result and result.baseID==2866 and #result.ranked==10)
for i,c in ipairs(result.ranked) do
 assert(c.row.id~=2866 and c.row.level<=30 and c.score>u.Score(Suite.Equipment.Get(2866),result.profile))
 if i>1 then assert(not u.Better(c,result.ranked[i-1])) end
end
assert(GameTooltip.lines[1]:find('Nearest upgrade:',1,true) and #GameTooltip.lines==3)
u.OpenDetails(5,nil,owner);assert(u.Details:IsShown() and u.Details.result==result)
assert(u.DetailRows[1].candidate.row.id==result.ranked[1].row.id)
u.Details:Hide();assert(u.Details.result==nil)
''')

    def test_ah_tab_only_boe(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;local owner=CreateFrame('Button','CharacterChestSlot')
GameTooltip:SetOwner(owner);u.OpenDetails(5,nil,owner);RunTimers()
local state=u.Details.result;assert(state and #state.rankedAH>0)
u.Details.ahTab.scripts.OnClick();assert(u.Details.onlyAH)
for i,c in ipairs(state.rankedAH) do assert(c.row.bind=='Binds when equipped' and u.DetailRows[i].candidate==c) end
u.Details.allTab.scripts.OnClick();assert(not u.Details.onlyAH)
assert(u.DetailRows[1].candidate==state.ranked[1])
''')

    def test_slot_and_class_restrictions(self):
        self.l.execute('''
local g=Suite.Equipment
assert(not g.Eligible(g.Get(7935),2,30,5,g.Get(2866))) -- Plate before 40
assert(not g.Eligible(g.Get(7959),2,30,16,g.Get(7957))) -- Requires level45
assert(not g.Eligible(g.Get(5191),2,30,16,g.Get(7957))) -- 1H vs 2H
assert(not g.Eligible(g.Get(2870),8,30,5,nil)) -- Mage cannot wear mail
local r={level=1,quality=2,class='Armor',subclass='Miscellaneous',classMask=-1,id=99,unique=true,inv=11}
assert(not g.Eligible(r,2,30,11,nil,99))
r.classMask=1;assert(not g.Eligible(r,2,30,11,nil))
''')

    def test_armor_progression_trained_weapons_and_source_menus(self):
        self.l.execute('''
local g=Suite.Equipment
assert(g.Context(2,39).tier=='Mail' and g.Context(2,40).tier=='Plate')
assert(g.Context(7,39).tier=='Leather' and g.Context(7,40).tier=='Mail')
for _,class in ipairs({5,8,9}) do assert(g.Context(class,60).tier=='Cloth') end
IsPlayerSpell=function(id) return id==202 end
local context=g.Context(2,30);assert(context.weapons['Two-Handed Sword'])
local sword={id=1,level=1,quality=2,class='Weapon',subclass='Two-Handed Sword',inv=17,classMask=-1}
assert(g.Eligible(sword,2,30,16,nil,nil,context))
sword.subclass='Two-Handed Axe';assert(not g.Eligible(sword,2,30,16,nil,nil,context))
assert(not g.Eligible(sword,2,30,17,nil,nil,context))
local u=Suite.Modules.SmyrnaUpgrader;local owner=CreateFrame('Button','CharacterChestSlot');GameTooltip:SetOwner(owner)
u.Hover(owner,5);RunTimers();local state=u.LastResult
for _,c in ipairs(state.ranked) do assert(c.row.subclass=='Mail') end
assert(u.SourceDock:IsShown())
u.SourceDock.buttons[2].scripts.OnEnter();assert(u.SourceMenu:IsShown() and u.SourceMenu.filter=='Quest')
u.SourceMenu.scroll.scripts.OnMouseWheel(nil,-100);assert(u.SourceMenu.scroll:GetVerticalScroll()<=u.SourceMenu.scroll:GetVerticalScrollRange())
u.SourceDock.buttons[3].scripts.OnEnter();assert(u.SourceMenu.filter=='AH')
for _,b in ipairs(u.SourceMenu.rows) do if b.candidate then assert(b.candidate.row.bind=='Binds when equipped') end end
u.OpenDetails(5,nil,owner,'Quest');assert(u.Details.sourceFilter=='Quest')
local list=u.Details.result.groups.Quest
if #list>0 then assert(u.DetailRows[1].candidate==list[1]) end
''')

    def test_hovered_bag_item_is_comparison_baseline(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;local owner=CreateFrame('Button','BagItem')
IsShiftKeyDown=function() return true end
GameTooltip:SetOwner(owner);GameTooltip.item='item:2870'
u.ItemTooltip(GameTooltip);RunTimers()
assert(u.LastResult.baseID==2870)
local value=u.Score(Suite.Equipment.Get(2870),u.LastResult.profile)
for _,c in ipairs(u.LastResult.ranked) do assert(c.score>value) end
''')

    def test_forever_modern_talent_api_without_legacy_globals(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;Suite.Config.upgrader.profile='auto'
GetTalentTabInfo=nil;GetSpecialization=nil
C_SpecializationInfo={GetSpecializationInfo=function(i) return 60+i,'Tree','Description',123,'DAMAGER',1,i==3 and 20 or 0 end,GetSpecialization=function() return 1 end}
assert(u.Profile().key=='2:3')
local owner=CreateFrame('Button','CharacterChestSlot');GameTooltip:SetOwner(owner)
u.OpenDetails(5,nil,owner);RunTimers();assert(u.Details.result and u.Details.result.profile.key=='2:3' and not u.LastStatus)
C_SpecializationInfo=nil
GetTalentTabInfo=function(i) return 60+i,'Tree','Description',123,i==3 and 20 or 0 end
assert(u.Profile().key=='2:3')
''')

    def test_ctrl_hover_and_stationary_modifier_press(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;local owner=CreateFrame('Button','CharacterChestSlot');GameTooltip:SetOwner(owner)
local ctrl=false;IsControlKeyDown=function() return ctrl end;IsShiftKeyDown=function() return false end
u.Driver.scripts.OnEvent(nil,'PLAYER_LOGIN')
owner.scripts.OnEnter(owner);assert(#timers==0 and not u.SourceDock)
ctrl=true;u.Driver.scripts.OnEvent(nil,'MODIFIER_STATE_CHANGED','LCTRL',1);RunTimers()
assert(u.SourceDock:IsShown() and u.SourceDock.anchor[2]==owner)
owner.scripts.OnLeave(owner);RunTimers();assert(not u.SourceDock:IsShown())
''')

    def test_details_show_terminal_missing_profile_or_database_message(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;Suite.Config.upgrader.profile='auto'
GetTalentTabInfo=nil;GetSpecialization=nil;C_SpecializationInfo=nil
u.OpenDetails(5);assert(u.LastStatus:find('profile',1,true) and not u.Details.result)
Suite.Config.upgrader.profile='local:3';Suite.Equipment.Ensure=function() return false end
u.OpenDetails(5);assert(u.LastStatus:find('Equipment DB',1,true) and not u.Details.result)
''')

    def test_batch_failure_is_visible_and_retry_completes(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;local score=u.Score;local n=0
u.Score=function(...) n=n+1;if n>1 then error('Injected scoring failure') end;return score(...) end
local owner=CreateFrame('Button','CharacterChestSlot');GameTooltip:SetOwner(owner)
u.OpenDetails(5,nil,owner);RunTimers()
assert(u.LastStatus:find('Injected scoring failure',1,true) and not u.Details.result)
u.Score=score;u.OpenDetails(5,nil,owner);RunTimers();assert(u.Details.result and not u.LastStatus)
''')

    def test_candidates_follow_every_class_armor_tier(self):
        self.l.execute('''
local g=Suite.Equipment
for _,class in ipairs({1,2,3,4,5,7,8,9,11}) do
 for _,level in ipairs({1,39,40,60}) do
  local ctx=g.Context(class,level)
  for _,id in ipairs(g.Candidates(5,level,class,ctx)) do
   local row=g.Get(id,true)
   assert(row.level<=level and row.subclass==ctx.tier)
  end
 end
end
''')

    def test_profile_no_spell_usage_guess_and_cache(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader
Suite.Config.upgrader.profile='auto'
GetTalentTabInfo=function(i) return 'Tree',nil,i==3 and 20 or 0 end
assert(u.Profile().key=='2:3')
local owner=CreateFrame('Button','CharacterChestSlot');GameTooltip:SetOwner(owner)
u.Hover(owner,5);RunTimers();local old=u.LastResult
u.Hover(owner,5);assert(#timers==0 and u.LastResult==old)
u.Invalidate();u.Hover(owner,5);assert(#timers>0);RunTimers();assert(u.LastResult~=old)
''')

    def test_quest_filters_and_no_ah_claim(self):
        self.l.execute('''
local u=Suite.Modules.SmyrnaUpgrader
local row={sources={{kind='Quest',level=1,id=1,faction='Alliance',classes='',repeatable=false},{kind='Quest',level=1,id=2,faction='Horde',classes='Mage',repeatable=false}}}
assert(next(u.SelectSource(row,30))==nil)
row.sources={{kind='Quest',level=1,id=3,faction='Horde',classes='',repeatable=false}}
C_QuestLog={IsQuestFlaggedCompleted=function() return true end};assert(next(u.SelectSource(row,30))==nil)
assert(u.SourceLabel({source={kind='Crafted'},row={bind='Binds when equipped'}})=='Profession (AH)')
assert(u.SourceLabel({source={kind='World'},row={bind='Binds when picked up'}})=='World drop')
''')

    def test_looting_bypasses_upgrade_hooks(self):
        self.l.execute("""
Suite.IsLootInteraction=function() return true end
local u=Suite.Modules.SmyrnaUpgrader
local owner=CreateFrame('Button','LootButton1');GameTooltip:SetOwner(owner)
u.Hover(owner,5);u.ItemTooltip(GameTooltip)
assert(#timers==0 and u.LastResult==nil)
""")

    def test_engine_handles_unusable_stats_and_speed_baseline(self):
        self.l.execute('''
local e=Suite.PrivatePawn
assert(e.Score({Strength=10,Stamina=5},{Strength=2,Stamina=1})==25)
assert(e.Score({Strength=10,IsShield=1},{Strength=2,IsShield=-1000000})==0)
assert(e.Score({MeleeSpeed=3},{MeleeSpeed=2,SpeedBaseline=2})==2)
assert(e.Score({RedSocket=1},{Strength=1})==nil)
''')


if __name__ == '__main__':
    unittest.main()
