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

### ServerScript (Controller)  
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SimpleFramework = require(ReplicatedStorage.SimpleFramework)

SimpleFramework:Import({
    ServerScriptService.Services
})
```

---

## Usage

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