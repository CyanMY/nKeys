local e, L = unpack(select(2, ...))

if not nAffixes then
	nAffixes = {}
	nAffixes.rotation = {}
	nAffixes.season_start_week = 0
	nAffixes.season_affix = 0
end

--[[
Affix names corresponding to ID
1 OVERFLOWING
2 SKITTISH
3 VOLCANIC
4 NECROTIC
5 TEEMING
6 RAGING
7 BOLSTERING
8 SANGUINE
9 TYRANNICAL
10 FORTIFIED
11 BURSTING
12 GRiEVOUS WOUNDS
13 EXPLOSIVE
14 QUAKING
15 RELENTLESS
16 Infested

Fortified	Bolstering	Grievous	Void
Tyrannical	Raging	Explosive	Tides
Fortified	Sanguine	Grievous	Enchanted
Tyrannical	Teeming	Volcanic	Void
Fortified	Bolstering	Skittish	Tides
Tyrannical	Bursting	Necrotic	Enchanted
Fortified	Sanguine	Quaking	Void
Tyrannical	Bolstering	Explosive	Tides
Fortified	Bursting	Volcanic	Enchanted
Tyrannical	Raging	Necrotic	Void
Fortified	Teeming	Quaking	Tides
Tyrannical	Bursting	Skittish	Enchanted

]]

local AFFIX_ROTATION = {
	{10, 8, 14}, -- FORTIFIED, SANGUINE, QUAKING
	{9, 7,13}, -- TYRANNICAL, BOLSTERING,EXPLOSIVE
	{10, 11, 3}, -- FORTIFIED, BURSTING, VOLCANIC
	{9, 6, 4}, -- TYRANNICAL, RAGING, NECROTIC
	{10, 5, 14}, -- FORTIFIED, TEEMING, QUAKING
	{9, 11, 2}, -- TYRANNICAL, BURSTING, SKITTISH
	{10, 7, 12}, -- FORTIFIED, BOLSTERING, GRiEVOUS
	{9, 6, 13}, -- TYRANNICAL, RAGING, EXPLOSIVE
	{10, 8, 12}, -- FORTIFIED, SANGUINE, GRiEVOUS
	{9, 5, 3}, -- TYRANNICAL, TEEMING, VOLCANIC
	{10, 7, 2}, -- FORTIFIED, BOLSTERING, SKITTISH
	{9, 11, 4}, -- TYRANNICAL, BURSTING, NECROTIC
}

local AFFIX_INFO = {}
local SEASON_AFFIX = 0
local ROTATION_WEEK_POSITION = 0
local AffixOneID, AffixTwoID, AffixThreeID = 0, 0, 0 -- Used to always show the current week's affixes irregardless if the rotation is known or not

-- Checks to see if the current week's affixes have been stored already
-- @param affixString string String representation of affixes, single digits are padded with leading 0's. ex. 100612 would be 10, 06, 12
-- @return Boolean False by default, true the affixes are found within the db
local function AreAffixesAlreadyStored(affixString)
	local rotation = nAffixes.rotation
	local rotationString

	for i = 1, #rotation do
		rotationString = string.format('%02d%02d%02d', rotation[i][1], rotation[i][2], rotation[i][3])
		if rotationString == affixString then
			return true
		end
	end

	return false
end


-- Finds the index of the current week's affixes in the table
-- @param affixOne Integers id for corresponding affix
-- @param affixTwo Integers id for corresponding affix
-- @param affixThree Integers id for corresponding affix
-- @return returnIndex integer defaults to 0 if the affixes are not found in the table, else returns the index the rotation is found
local function GetRotationPosition(affixOne, affixTwo, affixThree)
	local returnIndex = 0

	for i = 1, #AFFIX_ROTATION do
		if AFFIX_ROTATION[i][1] == affixOne and AFFIX_ROTATION[i][2] == affixTwo and AFFIX_ROTATION[i][3] == affixThree then
			returnIndex = i
			break
		end
	end

	return returnIndex
end

local function UpdateMythicPlusAffixes()
	local affixes = C_MythicPlus.GetCurrentAffixes()
	if not affixes or not C_ChallengeMode.GetAffixInfo(1) then -- affixes have not loaded, re-request the info
		C_MythicPlus.RequestMapInfo()
		C_MythicPlus.RequestCurrentAffixes()
		return
	end
	
	SEASON_AFFIX = affixes[4].id -- Set the season affix id
	AffixOneID = affixes[1].id
	AffixTwoID = affixes[2].id
	AffixThreeID = affixes[3].id

	ROTATION_WEEK_POSITION = GetRotationPosition(affixes[1].id, affixes[2].id, affixes[3].id)

	if SEASON_AFFIX ~= nAffixes.season_affix then -- Season has changed
		nAffixes.rotation = {} -- Wipe the table
		nAffixes.season_affix = SEASON_AFFIX -- Change the season affix
		nAffixes.season_start_week = e.Week -- Set the starting week
	end

	-- Store the affix info for all the affixes, name, description
	for affixId = 1, 300 do
		local name, desc = C_ChallengeMode.GetAffixInfo(affixId)
		AFFIX_INFO[affixId] = {name = name, description = desc}
	end

	-- Store the season affix info
	local name, desc = C_ChallengeMode.GetAffixInfo(SEASON_AFFIX)
	AFFIX_INFO[SEASON_AFFIX] = {name = name, description = desc}
	
	nEvents:Unregister('CHALLENGE_MODE_MAPS_UPDATE', 'updateAffixes')
	nEvents:Unregister('MYTHIC_PLUS_CURRENT_AFFIX_UPDATE', 'updateAffixes')
end
nEvents:Register('CHALLENGE_MODE_MAPS_UPDATE', UpdateMythicPlusAffixes, 'updateAffixes')
nEvents:Register('MYTHIC_PLUS_CURRENT_AFFIX_UPDATE', UpdateMythicPlusAffixes, 'UpdateAffixes')

function e.AffixOne(weekOffSet)
	local offSet = weekOffSet or 0

	if offSet == 0 then
		return AffixOneID
	end

	local week = (ROTATION_WEEK_POSITION + weekOffSet) % 12
	--local week = (e.Week + offSet) % 12
	if week == 0 then week = 12 end
	return AFFIX_ROTATION[week][1]
end

function e.AffixTwo(weekOffSet)
	local offSet = weekOffSet or 0

	if offSet == 0 then
		return AffixTwoID
	end
	local week = (ROTATION_WEEK_POSITION + weekOffSet) % 12
--	local week = (e.Week + offSet) % 12
	if week == 0 then week = 12 end
	return AFFIX_ROTATION[week][2]
end

function e.AffixThree(weekOffSet)
	local offSet = weekOffSet or 0

	if offSet == 0 then
		return AffixThreeID
	end

	local week = (ROTATION_WEEK_POSITION + weekOffSet) % 12	
--	local week = (e.Week + offSet) % 12
	if week == 0 then week = 12 end
	return AFFIX_ROTATION[week][3]

end

-- This is always the season affix, this doesn't get changed in a rotation
function e.AffixFour()
	return SEASON_AFFIX
end

function e.AffixName(id)
	if id ~= 0 then
		return AFFIX_INFO[id] and AFFIX_INFO[id].name
	else
		return nil
	end
end

function e.AffixDescription(id)
	if id ~= -1 then
		return AFFIX_INFO[id] and AFFIX_INFO[id].description
	else
		return nil
	end
end

function e.GetAffixID(id, weekOffSet)
	local offSet = weekOffSet or 0
	--local week = (e.Week + offSet) % 12
	local week = (ROTATION_WEEK_POSITION + weekOffSet) % 12	
	if week == 0 then week = 12 end
	return AFFIX_ROTATION[week][id] or SEASON_AFFIX
end