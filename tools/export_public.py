"""Export installed master code to repository addons without local-only Market/photos.
Does not change the source install, saved game state, or create ZIPs.
"""
from pathlib import Path
import argparse,shutil,re
PACKAGES=('SmyrnaSuite','SmyrnaBestiaryDB','SmyrnaWorkshopDB','SmyrnaEquipmentDB','SmyrnaRemembranceDB','SmyrnaWorldDB')
EXCLUDED={'SmyrnaSuite/Market.lua','SmyrnaSuite/Modules/MarketUI.lua','SmyrnaSuite/Media/Taylan.tga','SmyrnaSuite/Media/TaylanFrown.tga','SmyrnaSuite/Media/TaylanSmile.tga'}
def export(source,destination):
    source=source.resolve();destination=destination.resolve()
    assert source!=destination and not source.is_relative_to(destination) and not destination.is_relative_to(source)
    for pkg in PACKAGES:
        incoming=source/pkg;outgoing=destination/pkg
        assert incoming.is_dir(),pkg
        wanted=set()
        for f in incoming.rglob('*'):
            if not f.is_file():continue
            rel=f.relative_to(source).as_posix()
            if rel in EXCLUDED or f.suffix.lower() in {'.zip','.bak','.log'}:continue
            wanted.add(f.relative_to(incoming));dest=destination/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,dest)
        for f in outgoing.rglob('*'):
            if f.is_file() and f.relative_to(outgoing) not in wanted:
                assert f.resolve().is_relative_to(outgoing.resolve());f.unlink()
    root=destination/'SmyrnaSuite'
    p=root/'SmyrnaSuite.toc';s=p.read_text(encoding='utf-8-sig');s='\n'.join(x for x in s.splitlines() if x not in {'Market.lua','Modules/MarketUI.lua'})+'\n';s=s.replace(', SmyrnaMarketDB','');p.write_text(s,encoding='utf-8')
    p=root/'Suite.lua';s=p.read_text(encoding='utf-8-sig');s='\n'.join(x for x in s.splitlines() if not ('SmyrnaMarket' in x and ('SMYRNAMARKETUI' in x or 'Local AH price cache' in x)))+'\n';p.write_text(s,encoding='utf-8')
    p=root/'Tutorial.lua';s=p.read_text(encoding='utf-8-sig');s,n=re.subn(r" \{'Market','[^']+',.*?\n  '[^\n]*'\},\n",'',s,flags=re.S);assert n==1,'Market guide section changed; review export';s=s.replace('Workshop/Upgrader/Market tooltips','Workshop/Upgrader tooltips');p.write_text(s,encoding='utf-8')
    p=root/'UpgraderDetails.lua';s=p.read_text(encoding='utf-8-sig');s=s.replace("local showAH=(c.row.bind=='Binds when equipped')","local showAH=S.Market~=nil and (c.row.bind=='Binds when equipped')");s=s.replace('scan:SetEnabled(n>0)','scan:SetEnabled(S.Market~=nil and n>0)');s=s.replace("scan:SetText('Scan AH for these upgrades');S.StyleButton(scan)","scan:SetText('Scan AH for these upgrades');S.StyleButton(scan);scan:Hide()");p.write_text(s,encoding='utf-8')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--destination',type=Path,default=Path(__file__).resolve().parents[1]/'addons');a=parser.parse_args();export(a.source,a.destination)
