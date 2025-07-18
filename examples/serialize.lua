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

print("-------------------------------------------------")
print("Inspecting Serialized table")
print("-------------------------------------------------")
print(c.inspect(serialized_table))

local reconstructed_instance = c.deserialize(serialized_table)

print("-------------------------------------------------")
print("Inspecting Deserialized Instance")
print("-------------------------------------------------")
print(c.inspect(reconstructed_instance))