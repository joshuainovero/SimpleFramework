--!strict

---------------------------------------------------------------------------------------
-- Services
---------------------------------------------------------------------------------------
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

---------------------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------------------
type Reliable = 'Reliable'
type Unreliable = 'Unreliable'
type Returns = 'Returns'

export type ClientRemote = {
	Fire: (self: ClientRemote, ...any) -> ();
	Connect: (self: ClientRemote, func: (...any) -> ()) -> RBXScriptConnection
}

export type ServerRemote = {
	Fire: (self: ServerRemote, player: Player, ...any) -> ();
	FireAll: (self: ServerRemote, ...any) -> ();
	FireAllExcept: (self: ServerRemote, playerToExcept: Player, ...any) -> ();
	Connect: (self: ServerRemote, func: (player: Player, ...any) -> ()) -> RBXScriptConnection
}

---------------------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------------------
local SimpleFramework = {}
SimpleFramework.Remotes = {} :: {[string]: ClientRemote | ServerRemote}
SimpleFramework.Modules = {} :: {[string]: {Object: ModuleScript, RequiredModule: {any}}}
SimpleFramework.Importing = false
SimpleFramework.Started = false


---------------------------------------------------------------------------------------
-- Variables
---------------------------------------------------------------------------------------
local RemotesFolder: Folder

---------------------------------------------------------------------------------------
-- Helper functions
---------------------------------------------------------------------------------------

local function requireModule(path: Instance)
	if path:IsA('ModuleScript') then
		if SimpleFramework.Modules[path.Name] then
			error(`Cannot import! {path.Name} is already imported!`)
			return
		end
		
		SimpleFramework.Modules[path.Name] = {Object = path, RequiredModule = require(path) :: {any}}
	else
		for _, child in path:GetChildren() do
			requireModule(child)
		end
	end
end

local function connectClientSignal(moduleName: string, remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction)
	if not SimpleFramework.Remotes[moduleName] then
		SimpleFramework.Remotes[moduleName] = {} :: ClientRemote | ServerRemote
	end
	
	local tbl: any = {}
	
	if remote:IsA('RemoteEvent') or remote:IsA('UnreliableRemoteEvent') then
		tbl.Fire = function(self: ClientRemote, ...: any)
			(remote::RemoteEvent):FireServer(...)
		end
		
		tbl.Connect = function(self: ClientRemote, func: (...any) -> ())
			return (remote::RemoteEvent).OnClientEvent:Connect(func)	
		end
	elseif remote:IsA('RemoteFunction') then
		tbl.Fire = function(self, ... :any): ...any
			return remote:InvokeServer(...)
		end
	end
	
	SimpleFramework.Remotes[moduleName][remote.Name] = tbl
	
	return tbl
end

local function connectServerSignal(moduleName: string, remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction)
	if not SimpleFramework.Remotes[moduleName] then
		SimpleFramework.Remotes[moduleName] = {} :: ClientRemote | ServerRemote
	end

	local tbl: any = {}
	
	if remote:IsA('RemoteEvent') or remote:IsA('UnreliableRemoteEvent') then
		tbl.Fire = function(self, player: Player, ...: any)
			(remote::RemoteEvent):FireClient(player, ...)
		end
		
		tbl.FireAll = function(self, ...:any)
			(remote::RemoteEvent):FireAllClients(...)
		end
		
		tbl.FireAllExcept = function(self, playerToExcept: Player, ...:any)
			for _, player in Players:GetPlayers() do
				if playerToExcept == player then
					continue
				end
				
				(remote::RemoteEvent):FireClient(player, ...)
			end
		end
		
		tbl.Connect = function(self, func: (player: Player, ...any) -> ())
			return (remote::RemoteEvent).OnServerEvent:Connect(func)
		end
	elseif remote:IsA('RemoteFunction') then
		tbl.Connect = function(self, func: (player: Player, ...any) -> ())
			remote.OnServerInvoke = func
		end
	end

	SimpleFramework.Remotes[moduleName][remote.Name] = tbl
	
	return tbl
end

---------------------------------------------------------------------------------------
-- Public functions
---------------------------------------------------------------------------------------

function SimpleFramework:Import(paths: {Instance})
	if self.Importing then
		warn(`{debug.info(2, "s")} - Cannot import new modules!`)
		return
	end
	
	for _, path in paths do
		requireModule(path)
	end
	
	self.Importing = true
	
	-- Init
	for _, module in self.Modules do
		if module.RequiredModule.Init then
			local thread = task.spawn(module.RequiredModule.Init, module.RequiredModule)
			
			if coroutine.status(thread) ~= "dead" then
				error(`{module.Object:GetFullName()} Yielded`, 2)
			end
		else
			error(`{module.Object:GetFullName()} is not a valid module`, 2)
		end
	end
	
	-- Start
	for _, module in self.Modules do
		if module.RequiredModule.Start then
			task.spawn(module.RequiredModule.Start, module.RequiredModule)
		end
	end
	
	self.Started = true
end

function SimpleFramework:CreateSignal(SignalName: string, SignalType: Reliable? | Unreliable | Returns): ServerRemote
	if not RunService:IsServer() then
		error('Cannot create signal in client!')
	end
	
	if self.Started then
		error('Cannot create signal! Framework already started!')
	end
	
	if not RemotesFolder then
		error('Cannot create Signal! No remotes folder found')
	end
	
	if not SignalType then
		SignalType = 'Reliable'
	end
	
	local split = debug.info(2, "s"):split(".")
	local name = split[#split]

	local moduleFolder = RemotesFolder:FindFirstChild(name) or (function()
		local Folder = Instance.new('Folder')
		Folder.Name = name
		Folder.Parent = RemotesFolder
		return Folder
	end)()
	
	if moduleFolder:FindFirstChild(SignalName) then
		error(`{SignalName} is already found in {moduleFolder:GetFullName()}. Must not have duplicates!`)
	end
	
	local remote: any

	if SignalType == 'Reliable' then
		remote = Instance.new('RemoteEvent')
		
	elseif SignalType == 'Unreliable' then
		remote = Instance.new('UnreliableRemoteEvent')
	elseif SignalType == 'Returns' then
		remote = Instance.new('RemoteFunction')
	end
	
	remote.Name = SignalName
	local tbl = connectServerSignal(name, remote)
	
	remote.Parent = moduleFolder
	return tbl
end

do
	if RunService:IsServer() then		
		RemotesFolder = Instance.new('Folder')
		RemotesFolder.Name = 'SimpleFrameworkRemotes'
		RemotesFolder.Parent =	ReplicatedStorage
	elseif RunService:IsClient() then
		local ClientRemotesFolder = ReplicatedStorage:WaitForChild('SimpleFrameworkRemotes')
		
		for _, moduleFolder in ClientRemotesFolder:GetChildren() do
			for _, remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction in moduleFolder:GetChildren() do
				connectClientSignal(moduleFolder.Name, remote)
			end
		end
		
		ClientRemotesFolder.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA('RemoteEvent') or descendant:IsA('UnreliableRemoteEvent') or descendant:IsA('RemoteFunction') then
				if descendant.Parent then
					connectClientSignal(descendant.Parent.Name, descendant)
				end
			end
		end)
		
	end
end

return SimpleFramework
