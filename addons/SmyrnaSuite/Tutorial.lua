local _,S=...
-- Static help only: no reference loading, item requests or background updates.
local topics={
 {'Start here','INV_Misc_Book_09',
  {'Open your suite','Click the Smyrna 35 icon beside the minimap. Pick a feature along the top.','Minimap 35  >  Feature'},
  {'Choose what you use','Settings turns features and optional databases on or off. Apply & reload saves the change.','Settings  >  Apply & reload'},
  {'Learn one feature at a time','Choose a guide on the left to see how each tool works.','Choose a guide  >  Try it in game'},
  'Built-in data guides add item, recipe, and creature loot information on demand so they stay lightweight until you need them.'},
 {'Chat','INV_Misc_Note_01',
  {'Copy one message','Right-click a chat message to open the copy box. Highlight what you want, press Ctrl+C, then Escape to close.','Right-click message  >  Select  >  Ctrl+C'},
  {'Read your history','Click History next to the chat resize grip to scroll and copy older messages from this session.','Chat corner:  History  /  Resize'},
  {'Customize timestamps & clocks','Set timestamp colors, scrollback length, and world time zones. Hover the minimap clock to see your saved zones.','Chat settings  >  Time Zone slider'},
  'Chat history lasts for your current session and clears on reload.'},
 {'Bestiary','INV_Misc_Bone_09',
  {'Ctrl + hover for quick stats','Hold Ctrl while hovering any enemy to see its notable drops and class-relevant resistances without cluttering normal tooltips.','Ctrl + hover enemy  >  Quick summary'},
  {'Explore its loot','Ctrl + left-click a creature for its loot. Click any rarity or subcategory heading (like Recipes) to collapse it and jump straight to gear.','Ctrl + left-click  >  Loot'},
  {'Check resistances','Switch to the Resistances tab to see which damage schools work best against that enemy.','Loot  /  Resistances'},
  'Loot samples and resistance references are separate data. Missing data does not mean no drops or no resistance. Rates describe loot windows, not guaranteed drops.'},
 {'Field Diary','INV_Pick_02',
  {'Gather normally','Mine and loot ore, pick herbs, skin creatures, or cast and loot a fishing school. Hovering a school alone does not save a find.','Vein / Herb / Skin / School  >  Loot'},
  {'Spot a rare','Target or hover a rare creature. Silver markers remember an estimated sighting location.','Silver ring = rare sighting'},
  {'View your map','Use the discoveries map for saved finds. Guildies downloads shared samples; Manage lets you inspect and delete data. Map markers are optional.','Field Diary  >  Guildies / Manage'},
  'Gold: ore; green: herbs; brown: skins; blue: schools; silver: rares. The rim shows personal or guild data. Locations can be estimated. Current retention is 30 days.'},
 {'Remembrance','INV_Misc_PocketWatch_01',
  {'Remember people you meet','Hover players you have met before to see when you first met and last crossed paths.','Player hover  >  First / Last seen'},
  {'Open their story','Ctrl + left-click a player to open their history window with your shared dates.','Ctrl + left-click  >  History'},
  {'Keep shared moments','Browse dungeon, battleground and quest activity lists. Matching quest turn-ins require both players to use Smyrna with confirmation enabled.','Remembrance  >  Dungeons / BGs / Quests'},
  'Quest confirmation matches the same turn-in while grouped within 10 minutes; it does not prove shared objectives. Encounter history is local, not a live player tracker.'},
 {'Upgrader','INV_Sword_04',
  {'Instant hover upgrade %','Hover any equippable item (bags, loot, AH, merchants, or quest rewards) to see its live +% upgrade or -% downgrade vs your equipped gear.','Hover gear  >  +X% upgrade'},
  {'Compare upgrade sources','Press C and hold Ctrl while hovering an equipped slot for Dungeon, Quest, and AH circles — or Ctrl + left-click any gear for the full ranked list.','Ctrl + left-click gear  >  Ranked list'},
  {'Preview future upgrades','Use the slider in Upgrader settings to choose how many upcoming level upgrades (1-25) to preview per category.','Upgrader  >  Future upgrades'},
  'Scores both catalog items and random-enchant greens using your selected stat profile. Rankings use stat weights, not simulated DPS. AH quotes are listings, not completed sales.'},
 {'Workshop','INV_Hammer_20',
  {'Check any material','Hover a crafting reagent in your bags, profession window, or chat to see how many recipes use it.','Item hover  >  Recipe summary'},
  {'Browse recipes','Ctrl + left-click a material to view every recipe that uses it as clean rarity-colored cards grouped by profession.','Ctrl + left-click  >  Recipes'},
  {'Find merchants','Expand the Merchants section at the top of Workshop to see vendors and last-seen prices.','Merchants  >  Location / Price'},
  'Open your profession windows once so Workshop knows which recipes you have already learned.'},
 {'AggroMate','Ability_Creature_Cursed_04',
  {'Directional threat arc','Enable enemy Nameplates (V) to see a sleek quarter-arc colored Green, Yellow, Orange, or Red by distance. It hides automatically in combat.','AggroMate  >  Quarter-arc + Target pill'},
  {'TankMate nameplates','In combat, TankMate tints nameplates Green when attacking you, Amber when losing threat, and frames loose mobs in an oversized Red NO AGGRO border.','AggroMate  >  TankMate'},
  {'Compact leash tracker','While running more than 10 yards from a pull in combat, a sleek progress card tracks yards and seconds until reset — and closes when you stop.','Run away >10 yd  >  Leash tracker'},
  'Range and leash values are estimates, not a promise that a mob will reset. Edit Mode or AggroMate sliders let you move and resize the display.'},
 {'Bagger','INV_Misc_Bag_08',
  {'One gilded bag window','Press B (or /bagger) to open all your bags — including your reagent bag — in one searchable, gilded Smyrna window.','B  >  Search / Sort / Bag bar'},
  {'Filter & sort fast','Type in the search box to highlight matching items, click bag icons to toggle individual bags, or click Sort to organize everything.','Search box  /  Bag bar  /  Sort'},
  {'Customize your style','Click Style on the bag header (or open the Bagger tab) to pick your own background color, opacity, columns, and scale.','Bagger  >  Background color & layout'},
  'Uses native Blizzard item slots so right-click use/sell, Shift+click links, Workshop/Upgrader/Market tooltips, and drag-and-drop all work seamlessly.'},
 {'Guild','INV_Misc_GroupLooking',
  {'Find other Smyrna users','Open Guild and click Scan Guild. Other online users can report their enabled sharing features.','Guild  >  Scan Guild'},
  {'Choose what you share','Use the Guild switches for location, profession and map sharing. Both sides need compatible Smyrna features enabled.','Guild  >  Sharing switches'},
  {'Exchange gathering samples','Use Field Diary > Guildies to inspect available samples and request a download. Manage lets you remove shared data.','Field Diary  >  Guildies  >  Download'},
  'Reports depend on online guildmates and their sharing choices. If minimap pins are missing, use the World Map or Guild list. Shared reports are not guaranteed facts.'},
 {'Journal','INV_Misc_Map_01',
  {'Choose a dungeon','Open Journal and select a dungeon to browse its bosses, rares, faction-filtered quests, and interactive map floors.','Journal  >  Dungeon  >  Map / Quests'},
  {'Explore boss loot','Click Bosses & Loot or hover any boss pin on the map to inspect drops, resistances, and live upgrade badges.','Bosses & Loot  /  Map pins'},
  {'Compare an item','Ctrl + click a gear item in the loot preview to open Upgrader for that item.','Loot item  >  Ctrl + click  >  Upgrader'},
  'Quests automatically filter to your faction plus neutral quests. Map and loot coverage varies by dungeon. Drops are possibilities, not guarantees.'},
 {'Market','INV_Misc_Coin_02',
  {'Run a fast full scan','Open any Auction House and click Full Scan (or /sah). Watch the gold progress bar as Smyrna caches current realm prices.','Auctioneer  >  Full Scan'},
  {'See prices everywhere','Once scanned, cached Smyrna AH prices appear automatically on item tooltips in your bags, loot windows, and the Market tab.','Item hover  >  Smyrna AH price'},
  {'Quick Sell & shopping lists','Use Quick Sell to see undercut suggestions for items in your bags, or add terms to Lists to track materials and gear.','Market  >  Quick Sell / Lists'},
  'Cached prices can become stale between scans. Listings are asking prices, not completed sales. Smyrna never buys or posts items automatically.'},
 {'Quests','INV_Misc_QuestionMark',
  {'Browse your zone','Open Quests to browse available quests in your current zone. Built-in guides must be enabled.','Quests  >  Zone quest list'},
  {'Choose your displays','World Map, Mob tooltips and Tracker HUD each have their own switch. Low-level includes trivial quests.','Quests  >  Display switches'},
  {'Check your objectives','Hover relevant creatures for supported objective progress, or enable the compact Tracker HUD.','Mob hover  /  Tracker HUD'},
  'Quest chains and availability depend on reference coverage. If pins are missing, use the zone list. Your quest log and the quest giver confirm what you can actually do.'},
 {'Taylan','INV_Misc_QuestionMark',
  {'Try the alert','Open Settings and find Taylan. Click Test to preview the image and sound without pulling a creature.','Settings  >  Taylan  >  Test'},
  {'Choose image and sound','Threat alert controls automatic flashes. The Sound button cycles the available sounds, including Off.','Settings  >  Threat alert / Sound'},
  {'Move or resize it','The Taylan button opens the movable image. Left-drag to move it; use its lower-right handle to resize.','Taylan  >  Drag / Resize'},
  'The smaller image keeps its proportions. Right-click the movable image for its options. Hide dismisses the image; Threat alert and Sound control future alerts.'},

}
table.sort(topics,function(a,b)
 if a[1]=='Start here' then return b[1]~='Start here' end
 if b[1]=='Start here' then return false end
 return a[1]<b[1]
end)
S.TutorialTopics=topics
local panel,buttons,cards,note
local function WithSettingsIcon(text)
 return (text:gsub('([Ss]ettings)','|TInterface\\Icons\\INV_Misc_Gear_01:14:14|t %1'))
end
local function Label(parent,font,x,y,width)
 local t=parent:CreateFontString(nil,'OVERLAY',font);t:SetPoint('TOPLEFT',x,y);t:SetWidth(width);t:SetJustifyH('LEFT');return t
end
function S.ShowTutorialTopic(index)
 local topic=topics[index];if not topic then return end
 for i,b in ipairs(buttons) do S.SetButtonSelected(b,i==index) end
 for i,card in ipairs(cards) do
  local step=topic[i+2]
  card.icon:SetTexture('Interface\\Icons\\'..topic[2])
  card.number:SetText(tostring(i));card.title:SetText(step[1]);card.body:SetText(WithSettingsIcon(step[2]));card.example:SetText(WithSettingsIcon(step[3]))
 end
 note:SetText(WithSettingsIcon(topic[6]));panel.topic=index
end
function S.OpenTutorial()
 if not panel then
  panel=CreateFrame('Frame',nil,UIParent);panel:SetSize(800,470)
  local title=Label(panel,'GameFontNormalLarge',18,-12,750);title:SetText('Your Smyrna guide')
  local help=Label(panel,'GameFontHighlightSmall',18,-38,750);help:SetText('Choose a feature. Follow the numbered steps. Illustrated examples are not live data.')
  buttons={};cards={}
  local nav=CreateFrame('ScrollFrame',nil,panel,'UIPanelScrollFrameTemplate');nav:SetPoint('TOPLEFT',18,-68);nav:SetSize(118,392)
  local list=CreateFrame('Frame',nil,nav);list:SetSize(118,#topics*35);nav:SetScrollChild(list)
  nav:EnableMouseWheel(true);nav:SetScript('OnMouseWheel',function(self,delta)
   self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*35)))
  end)
  for i,topic in ipairs(topics) do
   local index=i;local b=CreateFrame('Button',nil,list,'UIPanelButtonTemplate');b:SetSize(118,29);b:SetPoint('TOPLEFT',0,-(i-1)*35);b:SetText(topic[1]);S.StyleButton(b)
   b:SetScript('OnClick',function() S.ShowTutorialTopic(index) end);buttons[i]=b
  end
  for i=1,3 do
   local card=CreateFrame('Frame',nil,panel,'BackdropTemplate');card:SetSize(614,96);card:SetPoint('TOPLEFT',164,-68-(i-1)*103);S.StyleCard(card)
   S.SetCornerGlow(card,.84,.67,.31,.09)
   local tile=S.CreateIconTile(card,38);tile:SetPoint('TOPLEFT',12,-12);tile:SetBackdropBorderColor(.72,.58,.29,.9)
   card.icon=tile.icon
   card.number=Label(card,'GameFontNormalLarge',25,-56,24);card.number:SetTextColor(.93,.77,.40)
   local pointer=card:CreateTexture(nil,'ARTWORK');pointer:SetSize(20,20);pointer:SetPoint('TOPLEFT',56,-11)
   pointer:SetTexture('Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up')
   card.title=Label(card,'GameFontNormal',83,-12,512);card.title:SetTextColor(1,.88,.55)
   card.body=Label(card,'GameFontHighlightSmall',83,-33,512);card.body:SetTextColor(.88,.9,.94)
   card.example=Label(card,'GameFontHighlightSmall',14,-74,585);card.example:SetTextColor(.55,.82,1)
   cards[i]=card
  end
  note=Label(panel,'GameFontHighlightSmall',164,-384,614);note:SetTextColor(.72,.76,.82)
  S.TutorialPanel=panel
  S.ShowTutorialTopic(1)
 end
 panel:Show();return panel
end
