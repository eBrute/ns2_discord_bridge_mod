--[[
    Shine discord bridge plugin
]]

local Shine = Shine
local Plugin = {}

Plugin.Version = "1.0"
Plugin.HasConfig = true --Does this plugin have a config file?
Plugin.ConfigName = "DiscordBridge.json" --What's the name of the file?
Plugin.DefaultState = true --Should the plugin be enabled when it is first added to the config?
Plugin.NS2Only = false --Set to true to disable the plugin in NS2: Combat if you want to use the same code for both games in a mod.
Plugin.CheckConfig = true --Should we check for missing/unused entries when loading?
Plugin.CheckConfigTypes = false --Should we check the types of values in the config to make sure they match our default's types?
Plugin.DefaultConfig = {
    DiscordBridgeURL = "",
    ServerIdentifier = "",
    SendPlayerJoin = true,
    SendPlayerLeave = true,
    SendMapChange = true,
    SendRoundWarmup = false,
    SendRoundPregame = false,
    SendRoundStart = true,
    SendRoundEnd = true,
    SendAdminPrint = true,
}


function Plugin:Initialise()
    if self.Config.DiscordBridgeURL == "" then
        return false, "You have not provided a path to the discord bridge server. See readme."
    end

    if string.UTF8Sub( self.Config.DiscordBridgeURL, 1, 7 ) ~= "http://" then
        return false, "The website url of your config is not legit, only http is supported."
    end

    if self.Config.ServerIdentifier == "" then
        return false, "You have not provided an identifier for the server. See readme."
    end

    if self.Config.SendAdminPrint then
        self:SimpleTimer( 0.5, function()
            local OldServerAdminPrint = ServerAdminPrint
            function ServerAdminPrint(client, message)
                OldServerAdminPrint(client, message)
                Plugin.SendToDiscord(self, "adminprint", {message = message})
            end
        end)
    end

    self:OpenConnection()

    self.Enabled = true
    return self.Enabled
end


function Plugin:HandleDiscordChatMessage(data)
    local chatMessage = string.UTF8Sub(data.content, 1, kMaxChatLength)
    if not chatMessage or string.len(chatMessage) <= 0 then return end
    local playerName = data.user
    if not playerName then return end
    Shine:Notify( nil, "Discord" , playerName, chatMessage )
end


function Plugin:HandleDiscordRconMessage(data)
    Shared.ConsoleCommand(data.content)
end


Plugin.ResponseHandlers = {
    chat = Plugin.HandleDiscordChatMessage,
    rcon = Plugin.HandleDiscordRconMessage,
}


function Plugin:ParseDiscordResponse(data)
    -- when the response is empty the server has another pending response and we can just close this connection
    if data == "" then
        return
    end

    local response, _, err = json.decode(data, 1, nil)
    if not err and response.type then
        local ResponseHandler = self.ResponseHandlers[response.type]
        if ResponseHandler then
            ResponseHandler(self, response)
        else
            Log("unknown response type %s", response.type)
        end
    end

    return self:OpenConnection()
end


function Plugin:SendToDiscord(type, payload)
    local params = {
        server = self.Config.ServerIdentifier,
        type = type,
    }
    for k, v in pairs(payload) do
        params[k] = v
    end
    local function responseParser(data)
        Plugin.ParseDiscordResponse(self, data)
    end
    Shared.SendHTTPRequest( self.Config.DiscordBridgeURL, "POST", params, responseParser)
end


function Plugin:OpenConnection()
    self:SendToDiscord("init", {})
end


function Plugin:PlayerSay(client, message)
	if not message.teamOnly and message.message ~= "" then
        local payload = {
            player = client:GetControllingPlayer().name,
            message = message.message
        }
        self:SendToDiscord("chat", payload)
	end
end


function Plugin:ClientConfirmConnect(client)
    if self.Config.SendPlayerJoin then
        local numPlayers = Server.GetNumPlayers()
        local maxPlayers = Server.GetMaxPlayers()
        local playerName = client:GetPlayer():GetName()
        self:SendToDiscord("status", {message = "Player '" .. playerName .. "' joined (" ..numPlayers .. "/" .. maxPlayers .. ")"})
    end
end


function Plugin:ClientDisconnect(client)
    if self.Config.SendPlayerLeave then
        local numPlayers = Server.GetNumPlayers() - 1
        local maxPlayers = Server.GetMaxPlayers()
        local playerName = client:GetPlayer():GetName()
        self:SendToDiscord("status", {message = "Player '" .. playerName .. "' left  (" ..numPlayers .. "/" .. maxPlayers .. ")"})
    end
end


function Plugin:SetGameState(GameRules, NewState, OldState)
    local CurState = kGameState[NewState]
    local mapName = "'" .. Shared.GetMapName() .. "'"
    local numPlayers = Server.GetNumPlayers()
    local maxPlayers = Server.GetMaxPlayers()
    local roundTime = Shared.GetTime()
    local playerCount = " (" .. numPlayers .. "/" .. maxPlayers .. ")"

    if self.Config.SendMapChange and CurState == 'NotStarted' and roundTime < 5 then
        self:SendToDiscord("status", {message = "Changed map to " .. mapName .. playerCount})
    end

    if self.Config.SendRoundWarmup and CurState == 'WarmUp' then
        self:SendToDiscord("status", {message = "WarmUp started on " .. mapName .. playerCount})
    end

    if self.Config.SendRoundPreGame and CurState == 'PreGame' then
        self:SendToDiscord("status", {message = "PreGame started on " .. mapName .. playerCount})
    end

    if self.Config.SendRoundStart and CurState == 'Started' then
        self:SendToDiscord("status", {message = "Round started on " .. mapName .. playerCount})
    end

    if self.Config.SendRoundEnd then
        if CurState == 'Team1Won' then
            self:SendToDiscord("status", {message = "Marines won on " .. mapName .. playerCount})
        elseif CurState == 'Team2Won' then
            self:SendToDiscord("status", {message = "Aliens won on " .. mapName .. playerCount})
        elseif CurState == 'Draw' then
            self:SendToDiscord("status", {message = "Draw on " .. mapName .. playerCount})
        end
    end
end


function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )

    self.Enabled = false
end


Shine:RegisterExtension("discordbridge", Plugin)