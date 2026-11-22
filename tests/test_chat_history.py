import unittest
from lua_harness import LuaRuntime,ROOT

class HistoryTests(unittest.TestCase):
    def test_batched_history_preserves_all_lines_native_handlers_and_scroll(self):
        l=LuaRuntime(unpack_returned_tuples=True)
        l.execute((ROOT/'tests/fixtures/history_frames.lua').read_text())
        l.execute(r'''
queue={};C_Timer={After=function(_,fn) queue[#queue+1]=fn end}
local original=CreateFrame
CreateFrame=function(kind,name,parent,template)
 local f=original(kind,name,parent,template);f.generation=0
 function f:GetScript(event) return self.scripts[event] end
 if template=='InputScrollFrameTemplate' then
  f.child=f.EditBox
  f.EditBox:SetScript('OnTextChanged',function(self) self.height=math.max(20,#self.text/30*14) end)
  f.EditBox:SetScript('OnCursorChanged',function() end)
  f.EditBox:SetScript('OnUpdate',function() end)
 end
 return f
end
''')
        for file in ['Style.lua','Modules/Chat.lua','ChatMessageEditor.lua','ChatSelection.lua']:
            l.execute('assert(loadstring(...))("SmyrnaSuite",Suite)',(ROOT/'addons/SmyrnaSuite'/file).read_text(encoding='utf-8'))
        l.execute(r'''
local c=Suite.Modules.SmyrnaChat;local db={directCopy=true};c.GetDB=function() return db end
assert(c.HistoryRetention()==10);db.historyRetention=1000;assert(c.HistoryRetention()==1000)
local source={};function source:GetNumMessages() return 650 end;function source:GetMessageInfo(i) return 'Message '..i end
c.CopyFrame(source);while #queue>0 do table.remove(queue,1)() end
local w;for _,f in ipairs(frames) do if f.name=='SmyrnaChatCopyWindow' then w=f end end
local e,v=w.edit,w.scroll;local expected={};for i=1,650 do expected[i]='Message '..i end
assert(e.text==table.concat(expected,'\n'))
assert(e.scripts.OnUpdate and e.scripts.OnCursorChanged and e.scripts.OnTextChanged)
assert(not rawget(e,'focus') and e.highlights==0)
e.scripts.OnMouseWheel(e,-100000);assert(v:GetVerticalScroll()==v:GetVerticalScrollRange())
c.CopyFrame(source);w:Hide();while #queue>0 do table.remove(queue,1)() end;assert(e.text=='')
''')

if __name__=='__main__':unittest.main()
