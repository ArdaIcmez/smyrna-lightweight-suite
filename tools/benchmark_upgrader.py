from pathlib import Path
import sys,json,time,random
sys.path.insert(0,'tests')
from lua_harness import upgrader_runtime,ROOT
l=upgrader_runtime();l.eval('collectgarbage')( 'collect' );baseline=l.eval('collectgarbage')( 'count' )
result={'scope':'Lua5.1 simulation on this machine; not native WoW CPU/FPS/attributed RAM','equipment_count':l.eval('Suite.Equipment.count'),'baseline_all_new_modules_KiB':round(baseline,2),'quote_stress':[]}
for count in [100000,1000000]:
 l.execute('prices={};collectgarbage("collect")');before=l.eval('collectgarbage')('count');start=time.perf_counter()
 l.execute('local n=...;for i=1,n do Suite.Market.Accumulate(prices,1+i%5000,1+i%20,100+(i%100000)) end',count)
 elapsed=(time.perf_counter()-start)*1000;l.eval('collectgarbage')('collect');after=l.eval('collectgarbage')('count')
 result['quote_stress'].append({'input_rows':count,'unique_items':5000,'total_ms':round(elapsed,2),'retained_KiB':round(after-before,2)})
l.execute('prices=nil;collectgarbage("collect")')
start=time.perf_counter();l.execute('local u=Suite.Modules.SmyrnaUpgrader;local owner=CreateFrame("Button","CharacterChestSlot");GameTooltip:SetOwner(owner);u.Hover(owner,5);RunTimers()');result['chest_recommendation_total_simulated_ms']=round((time.perf_counter()-start)*1000,2)
result['top10']=[l.eval(f'Suite.Modules.SmyrnaUpgrader.LastResult.ranked[{i}].row.name') for i in range(1,11)]
l.execute('collectgarbage("collect")');result['after_recommendation_KiB']=round(l.eval('collectgarbage')('count'),2)
# Compare optimized projection with imported Auctioneer row decoder.
for kind,call in [('original_full_row','Suite.DecodeAuctioneerQuote(info,nil,nil)'),('quote_projection','Suite.AuctioneerQuoteFields(info)')]:
 start=time.perf_counter();l.execute('local info={[1]="Item",[3]=20,[10]=12345,[17]=2589};for i=1,100000 do '+call+' end');result[kind+'_100k_ms']=round((time.perf_counter()-start)*1000,2)
# Raw copied Pawn arithmetic vs the isolated runtime function for 2,900 deterministic fixtures.
state=json.loads((ROOT/'.local/addon-sources/Pawn/current.json').read_text());source=(ROOT/'.local/addon-sources/Pawn/snapshots'/state['active']/'source/Pawn.lua').read_text(encoding='utf-8-sig');a=source.index('function PawnGetItemValue(');b=source.index('-- Returns a friendly description of the best gems',a)
l.execute('PawnCommon={Scales={active={}}};PawnIgnoreStatValue=-1000000;PawnScaleBestGems={};PawnScaleTotals={};VgerCore={IsBattleOrLater=false,ReforgingExists=false,Assert=assert}')
l.execute(source[a:b])
l.execute('''math.randomseed(1206);parity=0
for _,weights in pairs(Suite.PrivatePawn.Scales) do PawnCommon.Scales.active.Values=weights
 for i=1,100 do local stats={Strength=math.random(0,100),Stamina=math.random(0,100),Intellect=math.random(0,100),Agility=math.random(0,100),MeleeDps=math.random(1,100),MeleeSpeed=2.8,SpellDamage=math.random(0,100)}
  local expected=PawnGetItemValue(stats,30,nil,'active',false,true,true);local actual=Suite.PrivatePawn.Score(stats,weights)
  assert(math.abs(expected-actual)<1e-9);parity=parity+1
 end
end''');result['pawn_arithmetic_parity_fixtures']=l.eval('parity')
(ROOT/'reports').mkdir(exist_ok=True);(ROOT/'reports/UPGRADER-0.9.31.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
