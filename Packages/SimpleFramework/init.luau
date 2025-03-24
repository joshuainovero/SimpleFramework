--!strict

---------------------------------------------------------------------------------------
-- Services
---------------------------------------------------------------------------------------

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

---------------------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------------------

--[=[
    @type Reliable
    A constant indicating that a signal is reliable.
]=]
type Reliable = "Reliable"

--[=[
    @type Unreliable
    A constant indicating that a signal is unreliable.
]=]
type Unreliable = "Unreliable"

--[=[
    @type Returns
    A constant indicating that a signal returns a value.
]=]
type Returns = "Returns"

--[=[
    @type ClientRemote
    Represents a client-side remote communication object.

    @field Fire Function to send a remote event from the client.
    @field Connect Function to subscribe to remote events on the client.
]=]
export type ClientRemote = {
    Fire: (self: ClientRemote, ...any) -> (),
    Connect: (self: ClientRemote, func: (...any) -> ()) -> RBXScriptConnection,
}

--[=[
    @type ServerRemote
    Represents a server-side remote communication object.

    @field Fire -- Function to send a remote event to a specific client.
    @field FireAll -- Function to send a remote event to all clients.
    @field FireAllExcept  -- Function to send a remote event to all clients except one.
    @field Connect -- Function to subscribe to remote events on the server.
]=]
export type ServerRemote = {
    Fire: (self: ServerRemote, player: Player, ...any) -> (),
    FireAll: (self: ServerRemote, ...any) -> (),
    FireAllExcept: (self: ServerRemote, playerToExcept: Player, ...any) -> (),
    Connect: (self: ServerRemote, func: (player: Player, ...any) -> ()) -> RBXScriptConnection,
}

---------------------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------------------

--[=[
    @class SimpleFramework
    A framework for importing modules and managing remote signals (client/server) in a Roblox game.

    @field Remotes -- A table containing remote objects, organized by module.
    @field Modules -- A table containing imported ModuleScripts and their required modules.
    @field Importing -- A boolean flag indicating if module importing is in progress.
    @field Started -- A boolean flag indicating if the framework has been started.
]=]
local SimpleFramework = {}
SimpleFramework.Remotes = {} :: { [string]: ClientRemote | ServerRemote }
SimpleFramework.Modules = {} :: { [string]: { Object: ModuleScript, RequiredModule: { any } } }
SimpleFramework.Importing = false
SimpleFramework.Started = false

---------------------------------------------------------------------------------------
-- Variables
---------------------------------------------------------------------------------------

--[=[
    @private
    @var RemotesFolder
    A Folder instance that holds all remote signal instances for the framework.
]=]
local RemotesFolder: Folder

---------------------------------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------------------------------

--[=[
    Recursively requires ModuleScripts found in a given path.

    @param path Instance -- A ModuleScript or Folder from which to import modules.
    @throws An error if a module is already imported.
]=]
local function requireModule(path: Instance)
    if path:IsA("ModuleScript") then
        if SimpleFramework.Modules[path.Name] then
            error(`Cannot import! {path.Name} is already imported!`)
            return
        end

        SimpleFramework.Modules[path.Name] = { Object = path, RequiredModule = require(path) :: { any } }
    else
        for _, child in path:GetChildren() do
            requireModule(child)
        end
    end
end

--[=[
    Connects a client-side remote signal and adds it to the framework.

    @param moduleName string -- The name of the module grouping the remote.
    @param remote Instance -- The RemoteEvent, UnreliableRemoteEvent, or RemoteFunction instance.
    @return ClientRemote -- The constructed client remote object with Fire and Connect methods.
]=]
local function connectClientSignal(moduleName: string, remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction)
    if not SimpleFramework.Remotes[moduleName] then
        SimpleFramework.Remotes[moduleName] = {} :: ClientRemote | ServerRemote
    end

    local tbl: any = {}

    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        tbl.Fire = function(_self: ClientRemote, ...: any)
            (remote :: RemoteEvent):FireServer(...)
        end

        tbl.Connect = function(_self: ClientRemote, func: (...any) -> ())
            return (remote :: RemoteEvent).OnClientEvent:Connect(func)
        end
    elseif remote:IsA("RemoteFunction") then
        tbl.Fire = function(_self, ...: any): ...any
            return remote:InvokeServer(...)
        end
    end

    SimpleFramework.Remotes[moduleName][remote.Name] = tbl

    return tbl
end

--[=[
    Connects a server-side remote signal and adds it to the framework.

    @param moduleName string -- The name of the module grouping the remote.
    @param remote Instance -- The RemoteEvent, UnreliableRemoteEvent, or RemoteFunction instance.
    @return ServerRemote -- The constructed server remote object with appropriate Fire, FireAll, FireAllExcept, and Connect methods.
]=]
local function connectServerSignal(moduleName: string, remote: RemoteEvent | UnreliableRemoteEvent | RemoteFunction)
    if not SimpleFramework.Remotes[moduleName] then
        SimpleFramework.Remotes[moduleName] = {} :: ClientRemote | ServerRemote
    end

    local tbl: any = {}

    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        tbl.Fire = function(_self, player: Player, ...: any)
            (remote :: RemoteEvent):FireClient(player, ...)
        end

        tbl.FireAll = function(_self, ...: any)
            (remote :: RemoteEvent):FireAllClients(...)
        end

        tbl.FireAllExcept = function(_self, playerToExcept: Player, ...: any)
            for _, player in Players:GetPlayers() do
                if playerToExcept == player then
                    continue
                end

                (remote :: RemoteEvent):FireClient(player, ...)
            end
        end

        tbl.Connect = function(_self, func: (player: Player, ...any) -> ())
            return (remote :: RemoteEvent).OnServerEvent:Connect(func)
        end
    elseif remote:IsA("RemoteFunction") then
        tbl.Connect = function(_self, func: (player: Player, ...any) -> ())
            remote.OnServerInvoke = func
        end
    end

    SimpleFramework.Remotes[moduleName][remote.Name] = tbl

    return tbl
end

---------------------------------------------------------------------------------------
-- Public Functions
---------------------------------------------------------------------------------------

--[=[
    Imports modules from the provided paths and initializes them.

    This function recursively requires all ModuleScripts found in the given paths. For each module:
      - If an `Init` function is defined, it is executed immediately. The function is expected not to yield.
      - If a module lacks an `Init` function, an error is thrown.
      - If a `Start` function is defined, it is spawned asynchronously after initialization.

    @param paths { Instance } -- A table containing ModuleScript or Folder instances.
    @throws If attempting to import after modules are already being imported, or if a module fails its initialization.
]=]
function SimpleFramework:Import(paths: { Instance })
    if self.Importing then
        warn(`{debug.info(2, "s")} - Cannot import new modules!`)
        return
    end

    for _, path in paths do
        requireModule(path)
    end

    self.Importing = true

    -- Initialize modules
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

    -- Start modules (if a Start function exists)
    for _, module in self.Modules do
        if module.RequiredModule.Start then
            task.spawn(module.RequiredModule.Start, module.RequiredModule)
        end
    end

    self.Started = true
end

--[=[
    Creates a new server-side remote signal for client-server communication.

    This function must be called on the server and before the framework has started. It creates a new remote 
    signal (RemoteEvent, UnreliableRemoteEvent, or RemoteFunction) under the appropriate module folder in ReplicatedStorage.
    The module folder is determined by the calling context's name (using debug.info).

    @param SignalName string -- The name of the signal to create.
    @param SignalType Reliable? | Unreliable | Returns -- The type of signal. Defaults to "Reliable" if not provided.
    @return ServerRemote -- The constructed server remote signal object.
    @throws If called on the client, after the framework has started, or if a duplicate signal is detected.
]=]
function SimpleFramework:CreateSignal(SignalName: string, SignalType: Reliable? | Unreliable | Returns): ServerRemote
    if not RunService:IsServer() then
        error("Cannot create signal in client!")
    end

    if self.Started then
        error("Cannot create signal! Framework already started!")
    end

    if not RemotesFolder then
        error("Cannot create Signal! No remotes folder found")
    end

    if not SignalType then
        SignalType = "Reliable"
    end

    local split = debug.info(2, "s"):split(".")
    local name = split[#split]

    local moduleFolder = RemotesFolder:FindFirstChild(name)
        or (function()
            local Folder = Instance.new("Folder")
            Folder.Name = name
            Folder.Parent = RemotesFolder
            return Folder
        end)()

    if moduleFolder:FindFirstChild(SignalName) then
        error(`{SignalName} is already found in {moduleFolder:GetFullName()}. Must not have duplicates!`)
    end

    local remote: any

    if SignalType == "Reliable" then
        remote = Instance.new("RemoteEvent")
    elseif SignalType == "Unreliable" then
        remote = Instance.new("UnreliableRemoteEvent")
    elseif SignalType == "Returns" then
        remote = Instance.new("RemoteFunction")
    end

    remote.Name = SignalName
    local tbl = connectServerSignal(name, remote)

    remote.Parent = moduleFolder
    return tbl
end

---------------------------------------------------------------------------------------
-- Framework Initialization
---------------------------------------------------------------------------------------

do
    if RunService:IsServer() then
        RemotesFolder = Instance.new("Folder")
        RemotesFolder.Name = "SimpleFrameworkRemotes"
        RemotesFolder.Parent = ReplicatedStorage
    elseif RunService:IsClient() then
        local ClientRemotesFolder = ReplicatedStorage:WaitForChild("SimpleFrameworkRemotes")

        for _, moduleFolder in ClientRemotesFolder:GetChildren() do
            for _, remote in moduleFolder:GetChildren() do
                if not remote:IsA("RemoteEvent") and not remote:IsA("UnreliableRemoteEvent") and not remote:IsA("RemoteFunction") then
                    continue
                end

                connectClientSignal(moduleFolder.Name, remote)
            end
        end

        ClientRemotesFolder.DescendantAdded:Connect(function(descendant: Instance)
            if descendant:IsA("RemoteEvent") or descendant:IsA("UnreliableRemoteEvent") or descendant:IsA("RemoteFunction") then
                if descendant.Parent then
                    connectClientSignal(descendant.Parent.Name, descendant)
                end
            end
        end)
    end
end

return SimpleFramework
