import unittest,struct
from lua_harness import upgrader_runtime,ROOT

class PopupTests(unittest.TestCase):
    def setup_pointer(self):
        l=upgrader_runtime()
        l.execute('''
focus=nil;trackers={}
function MouseIsOver(frame)
 local p=focus;while p do if p==frame then return true end;p=p.parent end;return false
end
function C_Timer.NewTicker(interval,fn)
 local t={cancelled=false};function t:Cancel() self.cancelled=true end
 trackers[#trackers+1]=t
 local function tick() if t.cancelled then return end;fn();if not t.cancelled then C_Timer.After(interval,tick) end end
 C_Timer.After(interval,tick);return t
end
IsShiftKeyDown=function() error('Shift must not be queried for hover activation') end
owner=CreateFrame('Button','CharacterChestSlot');GameTooltip:SetOwner(owner);focus=owner
local u=Suite.Modules.SmyrnaUpgrader;u.Driver.scripts.OnEvent(nil,'PLAYER_LOGIN');owner.scripts.OnEnter(owner)
''')
        return l

    def test_circles_appear_before_scan_and_finish_after_entering_popup(self):
        l=self.setup_pointer()
        l.execute('''
local u=Suite.Modules.SmyrnaUpgrader
assert(u.SourceDock:IsShown() and u.SourceDock.state==nil)
owner.scripts.OnLeave(owner);GameTooltip:Hide()
focus=u.SourceDock.buttons[1];focus.scripts.OnEnter(focus)
assert(u.SourceMenu.rows[1].text=='Checking upgrades...')
RunTimers(.3)
assert(u.SourceDock:IsShown() and u.SourceDock.state and u.SourceMenu:IsShown())
assert(u.SourceMenu.rows[1].text~='Checking upgrades...')
u.SourceMenu.rows[1].scripts.OnClick();RunTimers(.1)
assert(u.Details:IsShown() and u.Details.result and u.Details.sourceFilter=='Dungeon')
''')

    def test_gap_rows_and_scrollbar_keep_popup_open_then_cancel_tracker(self):
        l=self.setup_pointer()
        l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;RunTimers(.1)
owner.scripts.OnLeave(owner);focus=nil;RunTimers(.3)
assert(u.SourceDock:IsShown())
focus=u.SourceDock.buttons[1];focus.scripts.OnEnter(focus)
focus=u.SourceMenu.rows[1];focus.scripts.OnEnter(focus);RunTimers(1)
assert(u.SourceDock:IsShown() and u.SourceMenu:IsShown())
local scrollbar=CreateFrame('Button',nil,u.SourceMenu.scroll)
focus.scripts.OnLeave(focus);focus=scrollbar;RunTimers(1)
assert(u.SourceDock:IsShown())
focus=nil;RunTimers(1)
assert(not u.SourceDock:IsShown() and trackers[1].cancelled)
RunTimers(1);assert(#timers==0)
''')

    def test_controls_are_larger_and_position_away_from_next_slot(self):
        l=self.setup_pointer()
        l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;RunTimers(.1)
assert(u.SourceDock:GetWidth()==158 and u.SourceDock:GetHeight()==66)
for _,button in ipairs(u.SourceDock.buttons) do assert(button:GetWidth()==44 and button:GetHeight()==44) end
assert(u.SourceDock.anchor[3]=='BOTTOMRIGHT' and u.SourceDock.anchor[4]>0)
local right=CreateFrame('Button','CharacterFinger0Slot');focus=right
u.ShowSources(right,11,u.LastResult)
assert(u.SourceDock.anchor[3]=='BOTTOMLEFT' and u.SourceDock.anchor[4]<0)
''')
        for name in ['UpgradeCircle.tga','UpgradeMask.tga']:
            data=(ROOT/'addons/SmyrnaSuite/Media'/name).read_bytes()
            self.assertEqual(struct.unpack_from('<HHB',data,12),(64,64,32))

if __name__=='__main__':unittest.main()
