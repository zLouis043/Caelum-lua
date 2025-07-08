local c = require "Caelum"

MyClass = c.class "MyClass" {
    val = c.int(50)
    .on_change(
        function(self) 
            print("Value changed to: " .. self.val)
        end
    ),

    __init = function(self, init_values)
        if type(init_values) == "number" then
            self.val = init_values
        end
    end
}

local instance = MyClass:new(20)

print(instance.val)

instance.val = 30