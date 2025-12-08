# SimpleFramework  

## Importing SimpleFramework  

### LocalScript
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimpleFramework = require(ReplicatedStorage.SimpleFramework)

SimpleFramework:Import({
    ReplicatedStorage.Controllers
})
```

### ServerScript
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SimpleFramework = require(ReplicatedStorage.SimpleFramework)

SimpleFramework:Import({
    ServerScriptService.Services
})
```

---

## Life Cycle Module Functions
```lua
function ExampleModule:Init(): ()
    -- Called when the module is first imported; used for setup.
end

function ExampleModule:Start(): ()
    -- Called after all modules have been initialized; used for starting processes.
end

function ExampleModule.PlayerAdded(player: Player): ()
    -- Called when a player joins the game
end

function ExampleModule.PlayerRemoving(player: Player): ()
    -- Called when a player leaves the game
end
```

---

## Example Usage

### Service Example
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SimpleFramework = require(ReplicatedStorage.SimpleFramework)

local Remote1 = SimpleFramework:CreateSignal("Remote1", "Reliable")

local Service = {}

function Service:Init()
    print("Server Init")
end

function Service:Start()
    print("Server Start")

    Remote1:Connect(function(player, var)
        print(player, var)
    end)
end

return Service
```

### Controller Example
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SimpleFramework = require(ReplicatedStorage.SimpleFramework)

local Remote1 = SimpleFramework.Remotes.Service.Remote1 :: SimpleFramework.ClientRemote

local Controller = {}

function Controller:Init()
    print("Controller Init")
end

function Controller:Start()
    print("Controller Start")
    Remote1:Fire('Hello')
end

return Controller
```

## Games made with Simple Framework
[Southern Mudding](https://www.roblox.com/games/79480724066456/Southern-Mudding-OffRoading)