--[[
	Shine discord bridge plugin
]]

local Message = Shared.Message -- Overridden by Shine later for some dumb reason

local Shine = Shine
local Plugin = {}

Plugin.Version			= "4.0.0"
Plugin.HasConfig		= true
Plugin.ConfigName		= "DiscordBridge.json"
Plugin.DefaultState		= true
Plugin.NS2Only			= false
Plugin.CheckConfig		= true
Plugin.CheckConfigTypes = true
Plugin.DefaultConfig	= {
	SendPlayerAllChat = true,
	SendPlayerJoin	  = true,
	SendPlayerLeave   = true,
	SendAdminPrint	  = false,
}

local fieldSep = ""

function Plugin:Initialise()
	if self.Config.SendAdminPrint then
		self:SimpleTimer( 0.5, function()
			self.OldServerAdminPrint = ServerAdminPrint
			function ServerAdminPrint(client, message)
				self.OldServerAdminPrint(client, message)
				Plugin.SendToDiscord(self, "adminprint", message)
			end
		end)
	end

	Log("Discord Bridge Version %s loaded", Plugin.Version)
	self.StartTime = os.clock()
	self.lastGameStateChangeTime = Shared.GetTime()
	self.lastChatMessageSendTime = os.clock()

	self.Enabled = true
	return self.Enabled
end


function Plugin:HandleDiscordChatMessage(data)
	local chatMessage = string.UTF8Sub(data.msg, 1, kMaxChatLength)
	if not chatMessage or string.len(chatMessage) <= 0 then return end
	local playerName = data.user
	if not playerName then return end
	Shine:NotifyDualColour(nil, 114, 137, 218, "(Discord) " .. playerName .. ":", 181, 172, 229, chatMessage)
end

function Server.GetActiveModTitle(activeModNum)
	local activeId = Server.GetActiveModId( activeModNum )
	for modNum = 1, Server.GetNumMods() do
		local modId = Server.GetModId( modNum )
		if modId == activeId then
			return Server.GetModTitle( modNum )
		end
	end
	return "<unknown mod>"
end

local function CollectActiveMods()
	local modIds = {}
	for modNum = 1, Server.GetNumActiveMods() do
		table.insert(modIds, {
			id = Server.GetActiveModId( modNum ),
			name = Server.GetActiveModTitle( modNum ),
		})
	end
	return modIds
end

function Plugin:HandleDiscordInfoMessage(data)
	local gameTime = Shared.GetTime() - self.lastGameStateChangeTime

	local teams = {}
	for _, team in ipairs( GetGamerules():GetTeams() ) do
		local numPlayers, numRookies = team:GetNumPlayers()
		local teamNumber = team:GetTeamNumber()

		local playerList = {}
		local function addToPlayerlist(player)
			table.insert(playerList, player:GetName())
		end
		team:ForEachPlayer(addToPlayerlist)

		teams[teamNumber] = {numPlayers=numPlayers, numRookies=numRookies, players = playerList}
	end

	local message = {
		serverIp	   = IPAddressToString( Server.GetIpAddress() ),
		serverPort	   = Server.GetPort(),
		serverName	   = Server.GetName(),
		version		   = Shared.GetBuildNumber(),
		mods		   = CollectActiveMods(),
		map			   = Shared.GetMapName(),
		state		   = kGameState[GetGameInfoEntity():GetState()],
		gameTime	   = tonumber( string.format( "%.2f", gameTime ) ),
		numPlayers	   = Server.GetNumPlayersTotal(),
		maxPlayers	   = Server.GetMaxPlayers(),
		numRookies	   = teams[kTeamReadyRoom].numRookies + teams[kTeam1Index].numRookies + teams[kTeam2Index].numRookies + teams[kSpectatorIndex].numRookies,
		teams = teams,
	}

	local jsonData, jsonError = json.encode( message )
	if jsonData and not jsonError then
		self:SendToDiscord("info", data.msg, jsonData)
	end

	return true
end

Plugin.ResponseHandlers = {
	chat = Plugin.HandleDiscordChatMessage,
	info = Plugin.HandleDiscordInfoMessage,
}

function Plugin:SendToDiscord(type, ...)
	local message = "--DISCORD--|" .. type
	for i = 1, select('#', ...) do
		message = message .. fieldSep .. select(i, ...)
	end

	Notify(message)
end

function Plugin:PlayerSay(client, message)
	if not message.teamOnly and self.Config.SendPlayerAllChat and message.message ~= "" then
		local player = client:GetControllingPlayer()
		self:SendToDiscord("chat",
			player:GetName(),
			player:GetSteamId(),
			player:GetTeamNumber(),
			message.message
		)
	end
end


function Plugin:ClientConfirmConnect(client)
	if self.Config.SendPlayerJoin
		and (os.clock() - self.StartTime) > 120 -- prevent overflow
	then
		local player = client:GetControllingPlayer()
		local numPlayers = Server.GetNumPlayersTotal()
		local maxPlayers = Server.GetMaxPlayers()
		self:SendToDiscord("player", "join", player:GetName(), player:GetSteamId(), numPlayers .. "/" .. maxPlayers)
	end
end


function Plugin:ClientDisconnect(client)
	if self.Config.SendPlayerLeave then
		local player = client:GetControllingPlayer()
		local numPlayers = math.max(Server.GetNumPlayersTotal() -1, 0)
		local maxPlayers = Server.GetMaxPlayers()
		self:SendToDiscord("player", "leave", player:GetName(), player:GetSteamId(), numPlayers .. "/" .. maxPlayers)
	end
end


function Plugin:SetGameState(_, CurState)
	CurState = kGameState[CurState]
	local mapName = "'" .. Shared.GetMapName() .. "'"
	local numPlayers = Server.GetNumPlayersTotal()
	local maxPlayers = Server.GetMaxPlayers()
	local roundTime = Shared.GetTime()
	local playerCount = numPlayers .. "/" .. maxPlayers

	self.lastGameStateChangeTime = Shared.GetTime()

	self:SendToDiscord("status", CurState, mapName, playerCount)
end


function Plugin:Cleanup()
	if self.Config.SendAdminPrint then
		ServerAdminPrint = self.OldServerAdminPrint
	end

	self.BaseClass.Cleanup( self )
	self.Enabled = false
end


Shine:RegisterExtension("discordbridge", Plugin)
