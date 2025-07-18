local c = require "Caelum"

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

    stack_trace = function(self)
        return "CUSTOM STACK TRACE: " .. self.stack_trace_string 
    end,

    code = function(self)
        return self.errCode
    end
}

local DerivedError = c.class("DerivedError", TestError){
    var = c.int(5),

    __init = function(self, init_values) 
        self.super(init_values)
    end
}

local Test  = c.class("Test") {
    var = c.int(4)
}

try(function()
    local var = 5

    try(function() 
        print("Entering nested try")

        throw(c.Error:new({msg = "Nested error"}))

    end):catch(function(err) 
        print("Nested catch with error: " .. err:what())
    end):finally(function() 
        print("Nested finally!")
    end):close()

    if var ~= 10 then
        throw(DerivedError:new({"Testing Error System", 3}))
    end
end)
:catch(TestError, function(err)
    print("TestError: " .. err:what() .. " with error code: " .. err:code())
end)
:catch(DerivedError, function(err)
    print("DerivedError: " .. err:what() .. " with error code: " .. err:code() .. "\n\t" .. err:stack_trace())
 
    try(function() 
        print("Nested try-catch") 
        throw(c.Error:new({msg = "Second nested try catch"})) 
    end)
    :catch(function(err)
        print("Nested General catch: " .. err:what() .. " " .. err:stack_trace())
    end):finally(function() print("Finally Nested Catch!") end)

end)
:catch(function(err)
    print("General catch:" .. err:what())
end):close()

try(function() throw(TestError:new()) end):catch(Test, function(err) print(err:what()) end):close() -- this should fail because Test is not a class derived from Caelum.Error