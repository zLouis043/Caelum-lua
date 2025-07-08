local c = require "Caelum"

MyClass = c.class "MyClass" {
    arr = c.array(c.Int, {0,1,2,3,4})
}

local instance = MyClass:new()

print("Array len at start: " .. instance.arr.length)

instance.arr:push(5)

print("Array len after push: " .. instance.arr.length)

instance.arr:forEach(function(element, index)
    print("[" .. index .. "] = " .. element)
end)

instance.arr:pop()

print("Array len at end: " .. instance.arr.length)
