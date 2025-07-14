local c = require "Caelum"

IdStruct = c.struct "IdStruct" {
    id = c.int(0),
    is_valid = c.bool(false)
}

TestStruct = c.struct "TestStruct" {
    integer = c.int(5),
    str = c.string("Hello World")
}

MyClass = c.class "MyClass" {
    primitive_map = c.map(c.String, c.Int, {
        ["One"] = 1,
        ["Two"] = 2,
        ["Three"] = 3,
        ["Four"] = 4
    }),

    complex_map = c.map(IdStruct, TestStruct, {
        [{id  = 1, is_valid = true}] = { integer = 20, str = "Hi There" },
        [{id = 2, is_valid = false}] = { integer = 69, str = "Whazzup" },
    })
}

local instance = MyClass:new()

instance.primitive_map:forEach(function(value, key) 
    print("Key: " .. key .. " Value: " .. value)
end)

instance.primitive_map:set("Five", 5)

print("Value in key 'Five': " .. instance.primitive_map["Five"])

instance.primitive_map:remove("Two")

instance.primitive_map:forEach(function(value, key) 
    print("Key: " .. key .. " Value: " .. value)
end)

print("Has 'Three': " .. tostring(instance.primitive_map:has("Three")))
print("Has 'Six': " .. tostring(instance.primitive_map:has("Six")))

instance.complex_map:forEach(function(value, key) 
    print("Key: {" .. key.id .. ", " .. tostring(key.is_valid) .. "} Value: {" .. value.integer .. ", " .. value.str .. "}")
end)

local map = c.Map(c.String, c.Int, {  -- This differs from the c.map because it declares a local variable of type Map<T> 
    ["One"] = 1,
    ["Two"] = 2,
    ["Three"] = 3
})

map:forEach(function(key, value)
    print(key, value)
end)

map["One"] = "Ho" -- Expected error