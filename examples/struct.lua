local c = require "Caelum"

MyStruct = c.struct "MyClass" {
    val = c.int(50),
    msg = c.string("")
}

local instance = MyStruct:new({val = 20, msg = "Hello World"})

print(instance.val)
print(instance.msg)