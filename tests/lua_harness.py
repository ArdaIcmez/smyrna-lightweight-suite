from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
if os.environ.get('SMYRNA_LUPA_PATH'):
    sys.path.insert(0, os.environ['SMYRNA_LUPA_PATH'])
elif (ROOT/'.local/lua-runtime').is_dir():
    sys.path.insert(0,str(ROOT/'.local/lua-runtime'))
else:
    for parent in ROOT.parents:
        local = parent / '2026-11-17/pla/work/lua-runtime-map'
        if local.is_dir():
            sys.path.insert(0, str(local));break
from lupa.lua51 import LuaRuntime


def runtime():
    l = LuaRuntime(unpack_returned_tuples=True)
    l.execute('''
Suite={Config={features={},data={},useDB=true,upgrader={profile='local:3'}},Modules={},Versions={},Loaded={}}
SmyrnaSuite=Suite;frames={};UISpecialFrames={};SlashCmdList={};clock=100000;timers={};messages={};equipment={[5]=2866,[16]=7957}
function time() return clock end
function GetRealmName() return 'Test realm' end
function UnitFactionGroup() return 'Horde' end
function UnitClass() return 'Paladin','PALADIN',2 end
function UnitLevel() return 30 end
function GetInventoryItemLink(unit,slot) return equipment[slot] and ('item:'..equipment[slot]) end
function InCombatLockdown() return false end
function IsControlKeyDown() return true end
function GetItemInfo() return nil end
function hooksecurefunc() end
function issecretvalue(v) return v=='SECRET' end
function CreateFrame(kind,name,parent,template)
 local f={kind=kind,name=name,parent=parent,template=template,scripts={},shown=true,level=parent and parent.level and parent.level+1 or 1,width=300,height=300,text='',offset=0}
 function f:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
 function f:SetScript(event,fn) self.scripts[event]=fn end
 function f:HookScript(event,fn) local old=self.scripts[event];self.scripts[event]=function(...) if old then old(...) end;fn(...) end end
 function f:GetScript(event) return self.scripts[event] end
 function f:SetPoint(...) self.anchor={...} end
 function f:ClearAllPoints() self.anchor=nil end
 function f:SetSize(w,h) self.width=w;self.height=h end
 function f:SetWidth(w) self.width=w end
 function f:SetHeight(h) self.height=h end
 function f:GetWidth() return self.width end
 function f:GetHeight() return self.height end
 function f:SetText(t) self.text=t or '';if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
 function f:GetText() return self.text end
 function f:GetName() return self.name end
 function f:GetParent() return self.parent end
 function f:GetFrameLevel() return self.level end
 function f:SetFrameLevel(level) self.level=level end
 function f:SetFrameStrata(strata) self.strata=strata end
 function f:GetFrameStrata() return self.strata or 'MEDIUM' end
 function f:SetAllPoints() end
 function f:SetColorTexture(...) self.color={...} end
 function f:SetTexture(path) self.texture=path end
 function f:EnableMouseWheel(enabled) self.wheel=enabled end
 function f:EnableMouse(enabled) self.mouse=enabled end
 function f:CreateTexture() return CreateFrame('Texture',nil,self) end
 function f:CreateFontString() return CreateFrame('FontString',nil,self) end
 function f:GetStringWidth() return #self.text*7 end
 function f:GetStringHeight() return math.max(14,math.ceil(#self.text*7/math.max(1,self.width))*14) end
 function f:SetScrollChild(child) self.child=child end
 function f:UpdateScrollChildRect() end
 function f:SetVerticalScroll(offset) self.offset=offset end
 function f:GetVerticalScroll() return self.offset end
 function f:GetVerticalScrollRange() return math.max(0,(self.child and self.child.height or 0)-self.height) end
 function f:Show() self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self) end end
 function f:Hide() self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self) end end
 function f:SetShown(value) if value then self:Show() else self:Hide() end end
 function f:IsShown() return self.shown end
 function f:SetOwner(owner) self.owner=owner end
 function f:GetOwner() return self.owner end
 function f:ClearLines() self.lines={} end
 function f:AddLine(text) self.lines=self.lines or {};self.lines[#self.lines+1]=text end
 function f:SetInventoryItem(unit,slot) self.item=GetInventoryItemLink(unit,slot) end
 function f:SetHyperlink(link) self.item=link end
 function f:GetItem() return 'Test item',self.item end
 function f:SetEnabled(v) self.enabled=v end
 function f:IsEnabled() return self.enabled~=false end
 function f:SetChecked(v) self.checked=v end
 function f:GetChecked() return self.checked end
 local noop=function() end
 for _,method in ipairs({'SetClampedToScreen','SetResizable','SetResizeBounds','SetMovable','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetJustifyH','SetTextColor','SetMaxLines','SetNormalTexture','RegisterForDrag','SetScale'}) do f[method]=noop end
 frames[#frames+1]=f;if name then _G[name]=f end
 return f
end
UIParent=CreateFrame('Frame','UIParent');GameTooltip=CreateFrame('GameTooltip','GameTooltip');ItemRefTooltip=CreateFrame('GameTooltip','ItemRefTooltip')
function Suite.StylePanel() end;function Suite.StyleButton() end
function Suite.CloseButton(parent) local b=CreateFrame('Button',nil,parent);b:SetScript('OnClick',function() parent:Hide() end);return b end
function Suite.UIText(text) return text end
DEFAULT_CHAT_FRAME={AddMessage=function(_,text) messages[#messages+1]=text end}
C_Timer={After=function(delay,fn) timers[#timers+1]={at=clock+delay,fn=fn} end}
function RunTimers(seconds)
 local untilTime=clock+(seconds or 5);local count=0
 while #timers>0 do
  table.sort(timers,function(a,b) return a.at<b.at end)
  if timers[1].at>untilTime then break end
  local t=table.remove(timers,1);clock=t.at;t.fn();count=count+1;assert(count<10000,'timer loop')
 end
 return count
end
C_Item={GetItemInfoInstant=function() return 2866,'Armor','Mail','INVTYPE_CHEST' end}
TooltipDataProcessor={AddTooltipPostCall=function(_,fn) itemPost=fn end};Enum={TooltipDataType={Item=0}}
''')
    load(l,'addons/SmyrnaSuite/Compatibility.lua')
    return l


def load(l, relative):
    text = (ROOT / relative).read_text(encoding='utf-8-sig')
    l.execute('assert(loadstring(...))("SmyrnaSuite",Suite)', text)


def upgrader_runtime():
    l = runtime()
    for file in ['addons/SmyrnaSuite/Equipment.lua', 'addons/SmyrnaSuite/PrivateScoring/PawnScore.lua',
                 'addons/SmyrnaEquipmentDB/Data.lua', 'addons/SmyrnaSuite/Modules/Upgrader.lua',
                 'addons/SmyrnaSuite/AuctioneerQuotes.lua', 'addons/SmyrnaSuite/Market.lua',
                 'addons/SmyrnaSuite/UpgraderDetails.lua','addons/SmyrnaSuite/UpgraderSources.lua']:
        load(l, file)
    return l
