local c = require "Caelum"
local inspect = require "inspect"

MyStruct = c.struct "MyStruct" {
    val = c.int(50),
    msg = c.string("")
}

MyClassForField = c.class "MyClassForField" {
    val = c.int(50),

    __init = function(self, init_values)
        if type(init_values) == "number" then
            self.val = init_values
        end
    end
}

MyClass = c.class "MyClass" {
    struct = c.field(MyStruct, {val = 20, msg = "Hello World"}),
    class = c.field(MyClassForField, 20),
    val = c.int(50)
}

local instance = MyClass:new()

print("instance.struct.val: " .. instance.struct.val)
print("instance.struct.msg: " .. instance.struct.msg)
print("instance.class.val: " .. instance.class.val)
print("instance.val: " .. instance.val)