# 🌌 The Caelum Framework

[![Lua](https://img.shields.io/badge/Lua-5.1-blue)](https://www.lua.org/)
[![Luarocks](https://img.shields.io/luarocks/v/inluiz/caelum)](https://luarocks.org/modules/inluiz/caelum)
![Last Commit](https://img.shields.io/github/last-commit/zLouis043/Caelum-lua)

Caelum-Lua is your go-to framework for structured, safe, and strongly-typed Lua scripting — without giving up the simplicity and speed of Lua.

Originally crafted to embed Lua into custom engines with reflection and automatic UI inspectors, Caelum has grown into a complete toolset for the Lua Language

## ✨ Why Caelum?

✅ **Safer code** — catch type errors early  
✅ **Structured design** — Classes, Structs, Enums, Arrays, Maps  
✅ **Modern features** — Switch-case, try-catch, custom errors  
✅ **Embed-friendly** — Designed for engine integrations & live validation  

Caelum adds what Lua is missing — without changing what makes Lua great.

## 🛠️ Features at a Glance

- 🧱 **OOP System** — `class`, `struct`, `inheritance` with type-safe fields and methods.
- 🏷️ **Enums** — Clean enum handling with index/next helpers.
- 🔒 **Strong Type System** — Type checking with metatables and proxies.
- 🧩 **Advanced Data Types** — `Array`, `Map`, all fully type-checked.
- 📝 **Metadata Support** — Title, description, range, and custom metadata.
- 💾 **Serialization & Deserialization** — Easily convert objects to pure lua tables and restore them.
- ✅ **Validators & Events** — Automatic on-change triggers and custom validators.
- ↔️ **Language Features** — `switch`, `try-catch-finally`, and structured error handling.

## ⚡ Installation 

#### 🚀 **Via LuaRocks**:

- The framework can be easily installed with luarocks with the command

```sh
$ luarocks install caelum
```

> ⚠️ Note: The LuaRocks version may lag behind GitHub. For the latest updates, clone directly from GitHub.

#### 📝 **Manual**:
- Simply copy the [Caelum.lua](./src/Caelum.lua) file into your project’s ``src/`` folder.

## 💡 Simple Examples 

Other examples for every feature of the framework can be found in the ```examples/``` folder

#### 📦 Class creation: 

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

#### 🏷️ Enum: 

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

#### 🧩 Array:

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

#### ❌ Try-Catch: 

```lua
local TestError = c.class("TestError", c.Error){
    errCode = c.int(0),

    __init = function(self, init_values)
        if init_values then 
            self.msg = init_values[1] or self.msg
            self.errCode = init_values[2] or self.errCode
        end
    end,

    what = function(self) -- This is an overriden function from the Error base class
        return string.format("ERROR: %s", self.msg)
    end,

    code = function(self)
        return self.errCode
    end
}

try(function()
    local var = 5
    if var ~= 10 then
        throw(TestError:new({"Testing Error System", 3}))
    end
end)
:catch(TestError, function(err)
    print("TestError: " .. err:what() .. " with error code: " .. err:code())

end)
:catch(function(err)
    print("General catch:" .. err:what())
end)
:finally(function()
    print("This should be called at the end!")
end)

```

#### 💾 Serialization/Deserialization:

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

local serialized_table = c.serialize(instance)
local reconstructed_instance = c.deserialize(serialized_table)

```

## 🤝 Contributions

Caelum is built to be open and extensible.

🟢 Found a bug?
🟣 Have an idea?
🟠 Want to contribute?

👉 Issues and pull requests are welcome! Let’s make Lua structured together.

## 🔗 Links 

Link to the **luarocks module page** [here](https://luarocks.org/modules/inluiz/caelum)

## 📜 License

Caelum is released under the MIT License.