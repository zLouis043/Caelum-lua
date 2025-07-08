local c = require "Caelum"

MyClass = c.class "MyClass" {
    integer = c.int(50),
    float = c.float(1.2),
    boolean = c.bool(true),
    str = c.string("Hello World\n"),

    __init = function(self, init_values)
        if type(init_values) == "number" then
            if math.floor(init_values) == init_values then 
                self.integer = init_values
            else 
                self.float = init_values
            end
        elseif type(init_values) == "boolean" then
            self.boolean = init_values
        elseif type(init_values) == "string" then 
            self.str = init_values
        elseif type(init_values) == "table" then
            self.integer = init_values.integer or self.integer
            self.float = init_values.float or self.float
            self.boolean = init_values.boolean or self.boolean
            self.str = init_values.str or self.str
        end
    end
}

local instance = MyClass:new({
    integer = 1,
    boolean = false,
    str = "Hi there",
    float = 20.4
})

print(instance.integer)
print(instance.float)
print(instance.boolean)
print(instance.str)