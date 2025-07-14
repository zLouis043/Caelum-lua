# The Caelum Framework
Caelum-Lua is a useful framework that adds to lua a structured and strongly typed aspect. 
The main object of the framework is to give programmers a secure, structured, and strongly-typed architecture to add to their lua scripts. 
Originally it was created to make possible embedding lua in a custom engine, it was not a difficult task if not for the lack of types and advanced structures in lua 
that made automatic reflection and an automatic inspector system for the ui possible. 

# Installation 

The framework can be easely installed with luarocks with the command

```sh
$ luarocks install caelum
```

Or by copy-pasting in your project the file [Caelum.lua](./src/Caelum.lua) in the ```src/``` folder

# Examples 

Class creation: 

```lua
local c = require "Caelum"

MyClass = c.class "MyClass" {
    val = c.int(50),

    __init = function(self, init_values)
        if type(init_values) == "number" then
            self.val = init_values
        end
    end
}

local instance = MyClass:new(20)

print(instance.val) -- Output: 20

```

Structs: 

```lua
local c = require "Caelum"

MyStruct = c.struct "MyClass" {
    val = c.int(50),
    msg = c.string("")
}

local instance = MyStruct:new({val = 20, msg = "Hello World"})

print(instance.val) -- Output: 20
print(instance.msg) -- Output: Hello World
```

Enum: 

```lua
local c = require "Caelum"

MyEnum = c.enum( "MyEnum", { "ONE", "TWO", "THREE", "FOUR" }, {
    default = "ONE"
})

MyClass = c.class "MyClass" {
    val = c.field(MyEnum, "TWO"),
}

local instance = MyClass:new()

print(instance.val) -- Output: TWO

print(MyEnum.get_index(instance.val)) -- Output: 2
print(MyEnum.get_next(instance.val))  -- Output: THREE


instance.val = "FIVE"
```

Array:

```lua
local c = require "Caelum"

MyClass = c.class "MyClass" {
    arr = c.array(c.Int, {0,1,2,3,4})
}

local instance = MyClass:new()

print("Array len at start: " .. instance.arr.length) -- Output: Array len at start: 5

instance.arr:push(5)

print("Array len after push: " .. instance.arr.length) -- Output: Array len after push: 6

instance.arr:forEach(function(element, index)
    print("[" .. index .. "] = " .. element) -- Output: [1] = 0 [2] = 1 ...
end)

instance.arr:pop()

print("Array len at end: " .. instance.arr.length)  -- Output: Array len at end: 5
```

Other examples for every feature of the framework can be found in the ```examples/``` folder

# Contributions

Dont hesitate to make issues and pull-requests, I am open to new features and bug-fixes.

# Links 

Link to the **luarocks module page** [here](https://luarocks.org/modules/inluiz/caelum)
