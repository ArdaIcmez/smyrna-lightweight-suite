"""Rebuild the tiny original UI circle/mask TGAs (development dependency: Pillow)."""
from pathlib import Path
from PIL import Image,ImageDraw

out=Path(__file__).resolve().parents[1]/'addons/SmyrnaSuite/Media'
image=Image.new('RGBA',(256,256),(0,0,0,0))
ImageDraw.Draw(image).ellipse((5,5,250,250),fill=(13,17,24,255),outline=(218,196,130,255),width=10)
image.resize((64,64),Image.Resampling.LANCZOS).save(out/'UpgradeCircle.tga')
image=Image.new('RGBA',(256,256),(255,255,255,0))
ImageDraw.Draw(image).ellipse((2,2,253,253),fill=(255,255,255,255))
image.resize((64,64),Image.Resampling.LANCZOS).save(out/'UpgradeMask.tga')
