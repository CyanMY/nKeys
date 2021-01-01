local e, L = unpack(select(2, ...))

local find, sub, strformat = string.find, string.sub, string.format
local BNSendGameData, SendAddonMessage, SendChatMessage = BNSendGameData, C_ChatInfo.SendAddonMessage, SendChatMessage

-- Variables for syncing information
-- Will only accept information from other clients with same version settings
local SYNC_VERSION = 'sync1'
e.UPDATE_VERSION = 'updateV1'

local versionList = {}
local highestSubVersion, highestMajorVersion = 0, 0

local messageStack = {}

local PrintVersion, CheckInstanceType

-- Interval times for syncing keys between clients
-- Two different time settings for in a raid or otherwise
-- Creates a random variance between +- [.001, .100] to help prevent
-- disconnects from too many addon messages
local SEND_VARIANCE = ((-1)^math.random(1,2)) * math.random(1, 100)/ 10^3 -- random number to space out messages being sent between clients
local SEND_INTERVAL = {}
SEND_INTERVAL[1] = 0.2 + SEND_VARIANCE -- Normal operations
SEND_INTERVAL[2] = 1 + SEND_VARIANCE -- Used when in a raiding environment
SEND_INTERVAL[3] = 2 -- Used for version checks

-- Current setting to be used
-- Changes when player enters a raid instance or not
local SEND_INTERVAL_SETTING = 1 -- What intervel to use for sending key information

nComs = CreateFrame('FRAME', 'nComs')

function nComs:RegisterPrefix(channel, prefix, f)
	local channel = channel or 'GUILD' -- Defaults to guild channel

	if self:IsPrefixRegistered(channel, prefix) then return end -- Did we register something to the same channel with the same name?

	if not self.dtbl[channel] then self.dtbl[channel] = {} end
	
	local obj = {}
	obj.method = f
	obj.prefix = prefix

	table.insert(self.dtbl[channel], obj)
end

function nComs:UnregisterPrefix(channel, prefix)
	local objs = self.dtbl[channel]
	if not objs then return end
	for id, obj in pairs(objs) do
		if obj.prefix == prefix then
			objs[id] = nil
			break
		end
	end
end

function nComs:IsPrefixRegistered(channel, prefix)
	local objs = self.dtbl[channel]
	if not objs then return false end
	for _, obj in pairs(objs) do
		if obj.prefix == prefix then
			return true
		end
	end
	return false
end

function nComs:OnEvent(event, prefix, msg, channel, sender)
	if not (prefix == 'nKeys') then return end

	if event == 'BN_CHAT_MSG_ADDON' then channel = 'BNET' end -- To handle BNET addon messages, they are actually WHISPER but I like to keep them seperate

	local objs = nComs.dtbl[channel]
	if not objs then return end

	local arg, content = msg:match("^(%S*)%s*(.-)$")

	for _, obj in pairs(objs) do
		if obj.prefix == arg then
			obj.method(content, sender, msg)
		end
	end
end

local msgs = setmetatable({}, {__mode='k'})

local function newMsg()
	local msg = next(msgs)
	if msg then
		msgs[msg] = nil
		return msg
	end
	return {}
end

local function delMsg(msg)
	msg[1] = nil
	msgs[msg] = true
end


function nComs:NewMessage(prefix, text, channel, target)
	if channel == 'GUILD' then
		if not IsInGuild() then
			return
		end
	end

	local msg = newMsg()

	if channel == 'BNET' then
		msg.method = BNSendGameData
		msg[1] = target
		msg[2] = prefix
		msg[3] = text
	else
		msg.method = SendAddonMessage
		msg[1] = prefix
		msg[2] = text
		msg[3] = channel
		msg[4] = channel == 'WHISPER' and target or ''
	end

	--Let's add it to queue
	self.queue[#self.queue + 1] = msg

	if not self:IsShown() then
		self:Show()
	end
end

function nComs:SendMessage()
	local msg = table.remove(self.queue, 1)
	if msg[3] == 'BNET' then
		if select(3, BNGetGameAccountInfo(msg[4])) == 'WoW' and BNConnected() then -- Are they logged into WoW and are we connected to BNET?
			msg.method(unpack(msg, 1, #msg))
		end
	elseif msg[3] == 'WHISPER' then
		if e.IsFriendOnline(msg[4]) then -- Are they still logged into that toon
			msg.method(unpack(msg, 1, #msg))
		end
	else-- Guild/raid message, just send it
		msg.method(unpack(msg, 1, #msg))
		delMsg(msg)
	end
end

function nComs:OnUpdate(elapsed)
	self.delay = self.delay + elapsed

	if self.delay < SEND_INTERVAL[SEND_INTERVAL_SETTING] + self.loadDelay then
		return
	end

	self.loadDelay = 0

	if self.versionPrint then
		CheckInstanceType()
		self.versionPrint = false
		PrintVersion()
	end

	self.delay = 0

	if #self.queue < 1 then -- Don't have any messages to send
		self:Hide()
		return
	end

	self:SendMessage()
end

function nComs:Init()
	self:RegisterEvent('CHAT_MSG_ADDON')
	self:RegisterEvent('BN_CHAT_MSG_ADDON')

	self:SetScript('OnEvent', self.OnEvent)
	self:SetScript('OnUpdate', self.OnUpdate)

	self.dtbl = {}
	self.queue = {}

	self:Hide()
	self.delay = 0
	self.loadDelay = 0
	self.versionPrint = false
end
nComs:Init()

-- Version checking

local function VersionRequest()
	SendAddonMessage('nKeys', 'versionPush ' .. e.CLIENT_VERSION .. ':' .. e.PlayerClass(), 'GUILD') -- Bypass the queue, shouldn't cause any issues, very little data is being pushed
end
nComs:RegisterPrefix('GUILD', 'versionRequest', VersionRequest)

local function VersionPush(msg, sender)
	local majorVersion, subVersion, class = msg:match('(%d+).(%d+):(%a+)')
	if tonumber(subVersion) > highestSubVersion then
		highestSubVersion = tonumber(subVersion)
	end
	if tonumber(majorVersion) > highestMajorVersion then
		highestMajorVersion = tonumber(majorVersion)
	end
	versionList[sender] = {subVersion = tonumber(subVersion), majorVersion = tonumber(majorVersion), class = class}
end
nComs:RegisterPrefix('GUILD', 'versionPush', VersionPush)

PrintVersion = function()
	local outOfDate = 'Out of date: '
	local upToDate = 'Up to date: '
	local notInstalled = 'Not installed: '

	local i = 1
	for k,v in pairs(versionList) do
		if v.majorVersion <= highestMajorVersion and tonumber(v.subVersion) < highestSubVersion then
			outOfDate = outOfDate .. strformat('%s(%d.%d) ', WrapTextInColorCode(Ambiguate(k, 'GUILD'), select(4, GetClassColor(v.class))), v.majorVersion, v.subVersion)
		else
			upToDate = upToDate .. strformat('%s(%d.%d) ', WrapTextInColorCode(Ambiguate(k, 'GUILD'), select(4, GetClassColor(v.class))), v.majorVersion, v.subVersion)
		end
	end

	local _, numGuildMembers = GetNumGuildMembers()
	for i = 1, numGuildMembers do
		local unit = GetGuildRosterInfo(i)
		local class = select(11, GetGuildRosterInfo(i))
		if not versionList[unit] then
			notInstalled = notInstalled .. WrapTextInColorCode(Ambiguate(unit, 'GUILD'), select(4, GetClassColor(class))) .. ' '
		end
	end
	ChatFrame1:AddMessage(upToDate)
	ChatFrame1:AddMessage(outOfDate)
	ChatFrame1:AddMessage(notInstalled)
end

function e.CheckGuildVersion()
	if not IsInGuild() then return end

	highestVersion = 0
	wipe(versionList)
	SendAddonMessage('nKeys', 'versionRequest', 'GUILD') -- Bypass the queue, very little data is being pushed, shouldn't cause any issues.
	nComs.versionPrint = true
	SEND_INTERVAL_SETTING = 3
	nComs.delay = 0
	nComs:Show()
end

-- Testing
local function GuildVersionCheckOnLogin()
	nComs:NewMessage('nKeys', 'versionCheck ' .. e.CLIENT_VERSION, 'GUILD')
end
--nEvents:Register('PLAYER_LOGIN', GuildVersionCheckOnLogin, 'versionCheck_login_guild')

local function GroupVersionCheckOnJoin()
	if IsInRaid() then
		nComs:NewMessage('nKeys', 'versionCheck ' .. e.CLIENT_VERSION, 'RAID')
	elseif (IsInGroup() and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) == 'INSTANCE_CHAT') then
		nComs:NewMessage('nKeys', 'versionCheck ' .. e.CLIENT_VERSION, 'PARTY')
	end
end
--nEvents:Register('GROUP_ROSTER_UPDATE', GroupVersionCheckOnJoin, 'versionCheck_login_group')

local receivedVersionMessage = false
local function VersionCheck(version, sender)
	if sender == e.Player() then return end
	if not version then return end
	if not receivedVersionMessage and (tonumber(version) > tonumber(e.CLIENT_VERSION)) then
		receivedVersionMessage = true
		print('You\'re version is out of date, the current version is', version)
	else
		local messageChannel
		if IsInRaid() then
			messageChannel = (not IsInRaid(LE_PARTY_CATEGORY_HOME) and IsInRaid(LE_PARTY_CATEGORY_INSTANCE)) and "INSTANCE_CHAT" or "RAID"
		elseif IsInGroup() then
			messageChannel = (not IsInGroup(LE_PARTY_CATEGORY_HOME) and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) and "INSTANCE_CHAT" or "PARTY"
		elseif IsInGuild() then
			messageChannel = 'GUILD'
		end
		if messageChannel then
			--nComs:NewMessage('nKeys', 'versionCheck ' .. e.CLIENT_VERSION, messageChannel)
		end
	end
end
--nComs:RegisterPrefix('GUILD', 'versionCheck', VersionCheck)

-- Let's just disable sending information if we are doing a boss fight
-- but keep updating individual keys if we receive them
-- keep the addon channel overhead low
nEvents:Register('ENCOUNTER_START', function()
	nComs:UnregisterPrefix('GUILD', 'request')
	end, 'encStart')

nEvents:Register('ENCOUNTER_END', function()
	nComs:RegisterPrefix('GUID', 'request', PushKeyList)
	end, 'encStop')

-- Checks to see if we zone into a raid instance,
-- Let's increase the send interval if we are raiding, client sync can wait, dc's can't
CheckInstanceType = function()
	nComs.loadDelay = 3
	local inInstance, instanceType = IsInInstance()
	if inInstance and instanceType == 'raid' then
		SEND_INTERVAL_SETTING = 2
	else
		SEND_INTERVAL_SETTING = 1
	end
end
nEvents:Register('PLAYER_ENTERING_WORLD', CheckInstanceType, 'entering_world')

function e.AnnounceCharacterKeys(channel)
	for i = 1, #nCharacters do
		local id = e.UnitID(strformat('%s-%s', e.CharacterName(i), e.CharacterRealm(i)))

		if id then
			local link = e.CreateKeyLink(e.UnitMapID(id), e.UnitKeyLevel(id))
			if channel == 'PARTY' and not IsInGroup() then return end
			SendChatMessage(strformat('%s %s',e.CharacterName(i), link), channel)
		end
	end
end

function e.AnnounceNewKey(keyLink)
	if nKeysSettings.general.announce_party.isEnabled and IsInGroup() then
		SendChatMessage(strformat(L['ANNOUNCE_NEW_KEY'], keyLink), 'PARTY')
	end
	if nKeysSettings.general.announce_guild.isEnabled and IsInGuild() then
		SendChatMessage(strformat(L['ANNOUNCE_NEW_KEY'], keyLink), 'GUILD')
	end
end

local function ParseGuildChatCommands(text)
	if UnitLevel('player') ~= e.EXPANSION_LEVEL then return end -- Don't bother checking anything if the unit is unable to acquire a key
	if text == '!keys' then
		local guild = GetGuildInfo('player')
		if nKeysSettings.general.report_on_message['guild'] or (guild == 'n' and e.PlayerRealm() == 'Turalyon') then -- Guild leader for n desires this setting to be foreced on for members.
			local unitID = e.UnitID(e.Player())
			if unitID then
				local keyLink = e.CreateKeyLink(e.UnitMapID(unitID), e.UnitKeyLevel(unitID))
				if not keyLink then return end -- Something went wrong
				SendChatMessage(string.format('n Keys: %s', keyLink), 'GUILD')
			else
				if nKeysSettings.general.report_on_message.no_key then
					SendChatMessage(strformat('%s: %s', 'n Keys', L['NO_KEY']), 'GUILD')
				end
			end
		end
	end
end
nEvents:Register('CHAT_MSG_GUILD', ParseGuildChatCommands, 'parseguildchat')

local function ParsePartyChatCommands(text)
	if UnitLevel('player') ~= e.EXPANSION_LEVEL then return end -- Don't bother checking anything if the unit is unable to acquire a key
	if text == '!keys' then
		if nKeysSettings.general.report_on_message['party'] then
			local unitID = e.UnitID(e.Player())
			if unitID then
				local keyLink = e.CreateKeyLink(e.UnitMapID(unitID), e.UnitKeyLevel(unitID))
				if not keyLink then return end -- Something went wrong
				SendChatMessage(string.format('n Keys: %s', keyLink), 'PARTY')
			else
				if nKeysSettings.general.report_on_message.no_key then
					SendChatMessage(strformat('%s: %s', 'n Keys', L['NO_KEY']), 'PARTY')
				end
			end
		end
	end
end
nEvents:Register('CHAT_MSG_PARTY', ParsePartyChatCommands, 'parsepartychat')
nEvents:Register('CHAT_MSG_PARTY_LEADER', ParsePartyChatCommands, 'parsepartychat')

local function ParseRaidChatCommands(text)
	if UnitLevel('player') ~= e.EXPANSION_LEVEL then return end -- Don't bother checking anything if the unit is unable to acquire a key
	if text == '!keys' then
		if nKeysSettings.general.report_on_message['raid'] then
			local unitID = e.UnitID(e.Player())
			if unitID then
				local link
				for bag = 0, NUM_BAG_SLOTS do
					local numSlots = GetContainerNumSlots(bag)
					for slot = 1, numSlots do
						if (GetContainerItemID(bag, slot) == e.MYTHICKEY_ITEMID) then
							link = GetContainerItemLink(bag, slot)
							break
						end
					end
				end
				if not link then return end -- something went wrong
				SendChatMessage(string.format('n Keys: %s', link), 'RAID')	
			else
				if nKeysSettings.general.report_on_message.no_key then
					SendChatMessage(strformat('%s: %s', 'n Keys', L['NO_KEY']), 'RAID')
				end
			end
		end
	end
end
nEvents:Register('CHAT_MSG_RAID', ParseRaidChatCommands, 'parseraidchat')
nEvents:Register('CHAT_MSG_RAID_LEADER', ParseRaidChatCommands, 'parseraidchat')