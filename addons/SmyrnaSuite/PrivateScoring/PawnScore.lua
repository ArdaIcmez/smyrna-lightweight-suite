-- PRIVATE NONCOMMERCIAL RESEARCH ADAPTATION. Pawn 2.14.8, Travis Spomer / VgerMods.
-- Original CC BY-NC-ND 3.0 notice and README retained in this directory.
-- Scoring function retained; local scope isolates it from installed Pawn.
-- This adapter deliberately excludes sockets/reforging: not applicable to this
-- Forever base-item reference scorer. No claims of complete Pawn UI/parser parity.
local _,S=...
local E={};S.PrivatePawn=E
local PawnCommon={Scales={active={}}}
local PawnIgnoreStatValue=-1000000
local PawnScaleBestGems={}
local PawnScaleTotals={}
local VgerCore={IsBattleOrLater=false,ReforgingExists=false,Assert=assert}
local function Score(Item, ItemLevel, SocketBonus, ScaleName, DebugMessages, NoNormalization, NoReforging)
	-- If either the item or scale is empty, exit now.
	if (not Item) or (not ScaleName) then return end
	local ScaleOptions = PawnCommon.Scales[ScaleName]
	if not ScaleOptions then return end
	local ScaleValues = ScaleOptions.Values
	if not ScaleValues then return end

	-- Calculate the value.
	local Total = 0
	local TotalSocketValue = 0
	local ProperSocketValue = 0
	local SocketBonusValue = 0
	local IsUnusable
	local ThisValue
	for Stat, Quantity in pairs(Item) do
		ThisValue = ScaleValues[Stat]
		if VgerCore.IsBattleOrLater then
			-- In Modern WoW, Attack Power gets converted into Strength or Agility, whichever is most valuable.
			if Stat == "Ap" then
				local StrengthValue = ScaleValues["Strength"] or 0
				local AgilityValue = ScaleValues["Agility"] or 0
				if AgilityValue > StrengthValue then
					Stat = "Agility"
				else
					Stat = "Strength"
				end
				ThisValue = ScaleValues[Stat]
			end
		end
		-- This isn't an unusable stat, is it?
		if ThisValue and ThisValue <= PawnIgnoreStatValue then
			Total = 0
			IsUnusable = true
			if DebugMessages then PawnDebugMessage(format(PawnLocal.UnusableStatMessage, Stat)) end
			break
		end
		-- Sockets need to be considered separately since their value depends on the item's level.
		if
			Stat ~= "PrismaticSocket" and
			Stat ~= "RedSocket" and
			Stat ~= "YellowSocket" and
			Stat ~= "BlueSocket" and
			Stat ~= "MetaSocket" and
			Stat ~= "MetaSocketEffect" and
			Stat ~= "CogwheelSocket" and
			Stat ~= "ShaTouchedSocket"
		then
			if ThisValue then
				-- This stat has a value; add it to the running total.
				if ScaleValues.SpeedBaseline and (
					Stat == "Speed" or
					Stat == "MeleeSpeed" or
					Stat == "MainHandSpeed" or
					Stat == "OffHandSpeed" or
					Stat == "OneHandSpeed" or
					Stat == "TwoHandSpeed" or
					Stat == "RangedSpeed"
				) then
					-- Speed is a special case; subtract SpeedBaseline from the speed value.
					Quantity = Quantity - ScaleValues.SpeedBaseline
				end
				Total = Total + Quantity * ThisValue
				if DebugMessages then PawnDebugMessage(format(PawnLocal.ValueCalculationMessage, Quantity, Stat, ThisValue, Quantity * ThisValue)) end
			end
		end
	end

	local ThisScaleBestGems = PawnScaleBestGems[ScaleName]
	if not IsUnusable then
		if ThisScaleBestGems then

			local ShouldIncludeSockets = (not PawnCommon.IgnoreGemsWhileLeveling) or (ItemLevel ~= nil and ItemLevel >= PawnMinimumItemLevelToConsiderGems)

			-- Decide what to do with sockets.
			if ShouldIncludeSockets and (
				Item.PrismaticSocket or
				Item.RedSocket or
				Item.YellowSocket or
				Item.BlueSocket or
				Item.MetaSocket or
				Item.MetaSocketEffect or
				Item.CogwheelSocket or
				Item.ShaTouchedSocket
			) then

				local GemQualityLevel = PawnGetGemQualityForItem(PawnGemQualityLevels, ItemLevel)
				local MetaGemQualityLevel = PawnGetGemQualityForItem(PawnMetaGemQualityLevels, ItemLevel)
				local CogwheelQualityLevel = PawnGetGemQualityForItem(PawnCogwheelQualityLevels, ItemLevel)
				local CrystalOfFearQualityLevel = PawnGetGemQualityForItem(PawnCrystalOfFearQualityLevels, ItemLevel)

				local SocketValue = function(Stat, QualityLevel)
					if QualityLevel == nil then return 0 end
					local Quantity = Item[Stat]
					if Quantity then
						local ThisValue2 = ThisScaleBestGems[Stat .. "Value"][QualityLevel]
						if ThisValue2 then
							if DebugMessages then PawnDebugMessage(format(PawnLocal.ValueCalculationMessage, Quantity, Stat, ThisValue2, Quantity * ThisValue2)) end
							return Quantity * ThisValue2
						else
							if DebugMessages then PawnDebugMessage("   No known value for " .. Quantity .. " " .. Stat) end
						end
					end
					return 0
				end

				local BasicSocketsCount = (Item.PrismaticSocket or 0) + (Item.RedSocket or 0) + (Item.YellowSocket or 0) + (Item.BlueSocket or 0)

				-- First, find the total value of the sockets assuming we ignore the socket bonus.
				local BestGemName = PawnGetGemListString(ScaleName, true, ItemLevel, "Prismatic")
				local BestGemValue = ThisScaleBestGems["PrismaticSocketValue"][GemQualityLevel] or 0
				local MissocketedValue = BasicSocketsCount * BestGemValue

				-- Then, see if we can get a better value by going for the socket bonus.
				if SocketBonus then
					for Stat, Quantity in pairs(SocketBonus) do
						ThisValue = ScaleValues[Stat]
						if ThisValue then
							SocketBonusValue = SocketBonusValue + ThisValue * Quantity
							if DebugMessages then PawnDebugMessage(format(PawnLocal.ValueCalculationMessage, Quantity, Stat, ThisValue, Quantity * ThisValue)) end
						end
					end
					if DebugMessages then PawnDebugMessage(format(PawnLocal.SocketBonusValueCalculationMessage, SocketBonusValue)) end
					ProperSocketValue =
						SocketValue("PrismaticSocket", GemQualityLevel) +
						SocketValue("RedSocket", GemQualityLevel) +
						SocketValue("YellowSocket", GemQualityLevel) +
						SocketValue("BlueSocket", GemQualityLevel) +
						SocketBonusValue
				end -- if SocketBonus

				if MissocketedValue > ProperSocketValue then
					if DebugMessages then PawnDebugMessage(string.format(PawnLocal.MissocketWorthwhileMessage, BestGemName)) end
					TotalSocketValue = MissocketedValue
					SocketBonusValue = 0
				else
					TotalSocketValue = ProperSocketValue
				end

				-- Finally, meta sockets are just kind of their own separate thing.
				TotalSocketValue = TotalSocketValue + SocketValue("MetaSocket", MetaGemQualityLevel)
				ThisValue = ScaleValues.MetaSocketEffect
				if ThisValue then
					Stat = "MetaSocketEffect"
					Quantity = Item[Stat]
					if Quantity then
						TotalSocketValue = TotalSocketValue + Quantity * ThisValue
						if DebugMessages then PawnDebugMessage(format(PawnLocal.ValueCalculationMessage, Quantity, Stat, ThisValue, Quantity * ThisValue)) end
					end
				end

				-- In Cataclysm there are also cogwheels for engineering goggles. Sigh.
				TotalSocketValue = TotalSocketValue + SocketValue("CogwheelSocket", CogwheelQualityLevel)

				-- Mists of Pandaria introduced the first expansion-specific socket type.
				TotalSocketValue = TotalSocketValue + SocketValue("ShaTouchedSocket", CrystalOfFearQualityLevel)

				Total = Total + TotalSocketValue
			end -- if ShouldIncludeSockets

		else
			-- This error case is acceptable if we're calculating data FOR the gems themselves.  (In that case, normalization will be off.)
			-- If it happens at any other time, we'd want to know about it.
			VgerCore.Assert(NoNormalization, "Item value calculation will be incomplete because we don't have best gem data and thus can't calculate values for sockets. /console scriptErrors 1 can help discover why.")
		end
	end

	-- Perform normalizations on the total if that option is enabled.
	if (not IsUnusable) and (not NoNormalization) and PawnScaleTotals[ScaleName] and PawnScaleTotals[ScaleName] > 0 then
		if ScaleOptions.NormalizationFactor and ScaleOptions.NormalizationFactor > 0 then
			if DebugMessages then PawnDebugMessage(format(PawnLocal.NormalizationMessage, PawnScaleTotals[ScaleName])) end
			Total = ScaleOptions.NormalizationFactor * Total / PawnScaleTotals[ScaleName]
		end
	end

	-- Decide if the item should be reforged.
	if VgerCore.ReforgingExists then
		if (not IsUnusable) and (not NoReforging) and (ItemLevel and ItemLevel >= 200) then
			local ReforgePotential = PawnFindOptimalReforgingCore(ScaleName, ScaleOptions, ScaleValues, Item, true)
			if ReforgePotential and ReforgePotential > 0 then
				if DebugMessages then PawnDebugMessage(format("   ---- Reforge item to gain +%g", ReforgePotential)) end
				Total = Total + ReforgePotential
			end
		end
	end

	if DebugMessages then PawnDebugMessage(format(PawnLocal.TotalValueMessage, Total)) end

	return Total, TotalSocketValue, SocketBonusValue
end


local socketKeys={'PrismaticSocket','RedSocket','YellowSocket','BlueSocket','MetaSocket','CogwheelSocket','ShaTouchedSocket'}
function E.Score(stats,weights)
 if not stats or not weights then return end
 for _,key in ipairs(socketKeys) do if (stats[key] or 0)>0 then return nil,'Unsupported sockets' end end
 PawnCommon.Scales.active.Values=weights
 return Score(stats,0,nil,'active',false,true,true)
end
E.Version='2.14.8'
E.Scales={["11:1"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0.64,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.032,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.04,["NatureSpellDamage"]=0.43,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=7.2,["SpellDamage"]=1,["SpellHasteRating"]=6.4239999999999995,["SpellHitRating"]=9.68,["SpellPenetration"]=0.21,["SpellPower"]=0,["Spirit"]=0.7,["Stamina"]=0.1,["Strength"]=0},["11:2"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.4,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.02,["ArmorPenetration"]=1.5,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=5.1,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=1.4303462999999998,["FeralAp"]=0.4,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=3.4528999999999996,["Healing"]=0.025,["Health"]=0.03,["HitRating"]=5.7213791,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.1,["Mana"]=0.009,["MeleeDps"]=6,["MetaSocketEffect"]=36,["Mp5"]=0.3,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=1.3},["11:3"]={["Agility"]=0.48,["AllResist"]=1,["Ap"]=0.1,["ArcaneResist"]=0.2,["ArcaneSpellDamage"]=0,["Armor"]=0.1,["ArmorPenetration"]=0.75,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=3.4000000000000004,["DefenseRating"]=0.8999999999999999,["DodgeRating"]=3.5871999999999997,["Dps"]=0,["ExpertiseRating"]=0.703449,["FeralAp"]=0.1,["FireResist"]=0.2,["FireSpellDamage"]=0,["FrostResist"]=0.2,["FrostSpellDamage"]=0,["HasteRating"]=2.4892999999999996,["Healing"]=0.025,["Health"]=0.08,["HitRating"]=3.0013792,["HolySpellDamage"]=0,["Hp5"]=2,["Intellect"]=0.1,["Mana"]=0.009,["MeleeDps"]=5,["MetaSocketEffect"]=36,["Mp5"]=0.3,["NatureResist"]=0.2,["NatureSpellDamage"]=0.025,["ParryRating"]=0,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.2,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=1,["Strength"]=0.3},["11:4"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=1.21,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.8,["Mana"]=0.07,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1.4,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=4.8,["SpellDamage"]=0,["SpellHasteRating"]=4.015,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=1,["Stamina"]=0.1,["Strength"]=0},["1:1"]={["Agility"]=0.69,["AllResist"]=0.2,["Ap"]=0.45,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=1.875,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=7.225,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=2.34483,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=4.818,["Healing"]=0,["Health"]=0.03,["HitRating"]=7.503448000000001,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0,["Mana"]=0,["MeleeDps"]=6,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=1},["1:2"]={["Agility"]=0.57,["AllResist"]=0.2,["Ap"]=0.45,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=1.7625,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=6.800000000000001,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=1.641381,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=5.6209999999999996,["Healing"]=0,["Health"]=0.03,["HitRating"]=7.503448000000001,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0,["Mana"]=0,["MeleeDps"]=6,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=1.1327999999999998,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=1},["1:3"]={["Agility"]=0.5,["AllResist"]=1,["Ap"]=0.04,["ArcaneResist"]=0.2,["ArcaneSpellDamage"]=0,["Armor"]=0.02,["ArmorPenetration"]=0.7125,["BlockRating"]=4.071,["BlockValue"]=0.35,["CritRating"]=3.4000000000000004,["DefenseRating"]=1.2000000000000002,["DodgeRating"]=6.608,["Dps"]=0,["ExpertiseRating"]=1.5710361000000002,["FeralAp"]=0,["FireResist"]=0.2,["FireSpellDamage"]=0,["FrostResist"]=0.2,["FrostSpellDamage"]=0,["HasteRating"]=1.6863,["Healing"]=0,["Health"]=0.09,["HitRating"]=6.2841377000000005,["HolySpellDamage"]=0,["Hp5"]=2,["Intellect"]=0,["IsOffHand"]=-1000000,["Mana"]=0,["MeleeDps"]=5,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.2,["NatureSpellDamage"]=0,["ParryRating"]=5.475199999999999,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.2,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=1,["Strength"]=0.6},["2:1"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0.069,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0.54,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=1,["Mana"]=0.009,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=3.68,["SpellDamage"]=0,["SpellHasteRating"]=3.1317,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.4,["Stamina"]=0.1,["Strength"]=0},["2:2"]={["Agility"]=0.6,["AllResist"]=1,["Ap"]=0.13,["ArcaneResist"]=0.2,["ArcaneSpellDamage"]=0,["Armor"]=0.02,["ArmorPenetration"]=0.33749999999999997,["BlockRating"]=5.5200000000000005,["BlockValue"]=0.15,["CritRating"]=1.275,["DefenseRating"]=1.0499999999999998,["DodgeRating"]=6.608,["Dps"]=0,["ExpertiseRating"]=0.6331041000000001,["FeralAp"]=0,["FireResist"]=0.2,["FireSpellDamage"]=0,["FrostResist"]=0.2,["FrostSpellDamage"]=0,["HasteRating"]=4.015,["Healing"]=0,["Health"]=0.09,["HitRating"]=1.5006896,["HolySpellDamage"]=0.44,["Hp5"]=2,["Intellect"]=0.5,["IsOffHand"]=-1000000,["Mana"]=0.045,["MeleeDps"]=5,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.2,["NatureSpellDamage"]=0,["ParryRating"]=5.664,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.2,["ShadowSpellDamage"]=0,["SpellCritRating"]=4.8,["SpellDamage"]=0.44,["SpellHasteRating"]=0.9635999999999999,["SpellHitRating"]=6.24,["SpellPenetration"]=0.03,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=1,["Strength"]=0.4},["2:3"]={["Agility"]=0.4,["AllResist"]=0.2,["Ap"]=0.45,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.33749999999999997,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=5.949999999999999,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=1.406898,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=2.0075,["Healing"]=0,["Health"]=0.03,["HitRating"]=7.8786204,["HolySpellDamage"]=0.5,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.032,["MeleeDps"]=6,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0.96,["SpellDamage"]=0.5,["SpellHasteRating"]=0.3212,["SpellHitRating"]=1.68,["SpellPenetration"]=0.015,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=1},["3:1"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.43,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.6375000000000001,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=6.800000000000001,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0.1172415,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=4.015,["Healing"]=0,["Health"]=0.01,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.8,["Mana"]=0.075,["MeleeDps"]=2,["MetaSocketEffect"]=36,["Mp5"]=1.3,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=6,["Rap"]=0.43,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.7,["Stamina"]=0.1,["Strength"]=0.05},["3:2"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.55,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=1.3875,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=5.1,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0.1172415,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=3.2119999999999997,["Healing"]=0,["Health"]=0.01,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.8,["Mana"]=0.085,["MeleeDps"]=2,["MetaSocketEffect"]=36,["Mp5"]=1.3,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=6.5,["Rap"]=0.55,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.7,["Stamina"]=0.1,["Strength"]=0.05},["3:3"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.55,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=1.05,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=5.525,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0.937932,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=3.2119999999999997,["Healing"]=0,["Health"]=0.03,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.8,["Mana"]=0.075,["MeleeDps"]=6,["MetaSocketEffect"]=36,["Mp5"]=2,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=6,["Rap"]=0.55,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.35,["Stamina"]=0.3,["Strength"]=0.3},["4:1"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.8,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.8999999999999999,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=7.65,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=2.579313,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=5.6209999999999996,["Healing"]=0,["Health"]=0.03,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0,["IsFrill"]=-1000000,["IsOffHand"]=-1000000,["IsShield"]=-1000000,["Mana"]=0,["MeleeDps"]=6,["MeleeMaxDamage"]=1.25,["MeleeMinDamage"]=1.25,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=1.1327999999999998,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=0.9},["4:2"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.8,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.8999999999999999,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=7.65,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=2.579313,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=5.6209999999999996,["Healing"]=0,["Health"]=0.03,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0,["IsFrill"]=-1000000,["IsOffHand"]=-1000000,["IsShield"]=-1000000,["Mana"]=0,["MeleeDps"]=6,["MeleeMaxDamage"]=0.875,["MeleeMinDamage"]=0.875,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=1.1327999999999998,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=0.9},["4:3"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.8,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.8999999999999999,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=7.65,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=2.579313,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=5.6209999999999996,["Healing"]=0,["Health"]=0.03,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0,["IsFrill"]=-1000000,["IsOffHand"]=-1000000,["IsShield"]=-1000000,["Mana"]=0,["MeleeDps"]=6,["MeleeMaxDamage"]=1.25,["MeleeMinDamage"]=1.25,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=1.1327999999999998,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=0.9},["4:offhand"]={["Agility"]=1,["AllResist"]=0.2,["Ap"]=0.8,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.8999999999999999,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=7.65,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=2.579313,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=5.6209999999999996,["Healing"]=0,["Health"]=0.03,["HitRating"]=9.37931,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0,["IsCloth"]=-1000000,["IsFrill"]=-1000000,["IsLeather"]=-1000000,["IsMail"]=-1000000,["IsPlate"]=-1000000,["IsRanged"]=-1000000,["IsShield"]=-1000000,["MainHandDps"]=-1000000,["Mana"]=0,["MeleeDps"]=4,["MeleeSpeed"]=-80,["MetaSocketEffect"]=36,["Mp5"]=0,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=1.1327999999999998,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpeedBaseline"]=2.9,["SpellCritRating"]=0,["SpellDamage"]=0,["SpellHasteRating"]=0,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.05,["Stamina"]=0.3,["Strength"]=0.9},["5:1"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0.7,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.9,["Mana"]=0.08,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1.5,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=5.6,["SpellDamage"]=0,["SpellHasteRating"]=4.818,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=1,["Stamina"]=0.1,["Strength"]=0},["5:2"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0.7,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.9,["Mana"]=0.08,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1.5,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=5.6,["SpellDamage"]=0,["SpellHasteRating"]=4.818,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=1,["Stamina"]=0.1,["Strength"]=0},["5:3"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.5,["Mana"]=0.02,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1.5,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=1,["SpellCritRating"]=6.08,["SpellDamage"]=1,["SpellHasteRating"]=5.2195,["SpellHitRating"]=7.2,["SpellPenetration"]=0.08,["SpellPower"]=0,["Spirit"]=0.7,["Stamina"]=0.1,["Strength"]=0},["7:1"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0.069,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.024,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1.3,["NatureResist"]=0.04,["NatureSpellDamage"]=1,["ParryRating"]=1.1327999999999998,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=7.2,["SpellDamage"]=1,["SpellHasteRating"]=5.6209999999999996,["SpellHitRating"]=5.6,["SpellPenetration"]=0.28,["SpellPower"]=0,["Spirit"]=0.8,["Stamina"]=0.1,["Strength"]=0},["7:2"]={["Agility"]=0.3,["AllResist"]=0.2,["Ap"]=0.42,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0.6,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=7.65,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=3.517245,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=4.818,["Healing"]=0,["Health"]=0.03,["HitRating"]=6.565517,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.032,["MeleeDps"]=6,["MetaSocketEffect"]=36,["Mp5"]=1.2,["NatureResist"]=0.04,["NatureSpellDamage"]=0.3,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=2.608,["SpellDamage"]=0.3,["SpellHasteRating"]=0.6424,["SpellHitRating"]=1.784,["SpellPenetration"]=0.11,["SpellPower"]=0,["Spirit"]=0.5,["Stamina"]=0.3,["Strength"]=1},["7:3"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0.069,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0.9,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=1,["Mana"]=0.009,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1.4,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=4.8,["SpellDamage"]=0,["SpellHasteRating"]=5.9422,["SpellHitRating"]=0,["SpellPenetration"]=0,["SpellPower"]=0,["Spirit"]=0.9,["Stamina"]=0.1,["Strength"]=0},["8:1"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0.95,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0.1,["FrostResist"]=0.04,["FrostSpellDamage"]=0.1,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.035,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=0.75,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=4.8,["SpellDamage"]=1,["SpellHasteRating"]=4.737699999999999,["SpellHitRating"]=6.96,["SpellPenetration"]=0.09,["SpellPower"]=0,["Spirit"]=0.5,["Stamina"]=0.1,["Strength"]=0},["8:2"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0.168,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0.95,["FrostResist"]=0.04,["FrostSpellDamage"]=0.32,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.45,["Mana"]=0.035,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=0.75,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=7.2,["SpellDamage"]=1,["SpellHasteRating"]=6.584599999999999,["SpellHitRating"]=7.44,["SpellPenetration"]=0.09,["SpellPower"]=0,["Spirit"]=0.5,["Stamina"]=0.1,["Strength"]=0},["8:3"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0.13,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0.05,["FrostResist"]=0.04,["FrostSpellDamage"]=0.95,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.45,["Mana"]=0.035,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=0.75,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0,["SpellCritRating"]=5.6,["SpellDamage"]=1,["SpellHasteRating"]=5.0588999999999995,["SpellHitRating"]=9.76,["SpellPenetration"]=0.07,["SpellPower"]=0,["Spirit"]=0.5,["Stamina"]=0.1,["Strength"]=0},["9:1"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0.35,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.03,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0.91,["SpellCritRating"]=5.6,["SpellDamage"]=1,["SpellHasteRating"]=6.4239999999999995,["SpellHitRating"]=6.4,["SpellPenetration"]=0.2,["SpellPower"]=0,["Spirit"]=0.4,["Stamina"]=0.1,["Strength"]=0},["9:2"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0.8,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.03,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0.8,["SpellCritRating"]=5.6,["SpellDamage"]=1,["SpellHasteRating"]=5.6209999999999996,["SpellHitRating"]=6.4,["SpellPenetration"]=0.2,["SpellPower"]=0,["Spirit"]=0.4,["Stamina"]=0.1,["Strength"]=0},["9:3"]={["Agility"]=0.05,["AllResist"]=0.2,["Ap"]=0,["ArcaneResist"]=0.04,["ArcaneSpellDamage"]=0,["Armor"]=0.005,["ArmorPenetration"]=0,["BlockRating"]=0,["BlockValue"]=0,["CritRating"]=0,["DefenseRating"]=0.07500000000000001,["DodgeRating"]=0.472,["Dps"]=0,["ExpertiseRating"]=0,["FeralAp"]=0,["FireResist"]=0.04,["FireSpellDamage"]=0.6,["FrostResist"]=0.04,["FrostSpellDamage"]=0,["HasteRating"]=0,["Healing"]=0,["Health"]=0.01,["HitRating"]=0,["HolySpellDamage"]=0,["Hp5"]=1,["Intellect"]=0.6,["Mana"]=0.03,["MeleeDps"]=0,["MetaSocketEffect"]=36,["Mp5"]=1,["NatureResist"]=0.04,["NatureSpellDamage"]=0,["ParryRating"]=0.472,["RangedDps"]=0,["Rap"]=0,["ResilienceRating"]=0.2,["ShadowResist"]=0.04,["ShadowSpellDamage"]=0.8,["SpellCritRating"]=7.2,["SpellDamage"]=1,["SpellHasteRating"]=7.226999999999999,["SpellHitRating"]=6.4,["SpellPenetration"]=0.2,["SpellPower"]=0,["Spirit"]=0.4,["Stamina"]=0.1,["Strength"]=0}}
