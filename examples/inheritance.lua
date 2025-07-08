local c = require "Caelum"

MyClass = c.class "MyClass" {
    val = c.int(50),

    __init = function(self, init_values)

        print("Calling MyClass Constructor")

        if type(init_values) == "number" then
            self.val = init_values
        end
    end
}

MyDerivedClass = c.class("MyDerivedClass", MyClass) {
    name = c.string("Steve"),

    __init = function(self, init_values)

        print("Calling MyDerivedClass Constructor")

        self:super(init_values)

        if type(init_values) == "string" then
            self.name = init_values
        end

        if type(init_values) == "table" then 
            self.name = init_values.name or self.name
            self.val  = init_values.val or self.val
        end
    end
}

local instance = MyDerivedClass:new({val = 20, name = "Bob"})

print(instance.val, instance.name)