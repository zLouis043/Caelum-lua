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
    if var ~= 10 then
        throw(DerivedError:new({"Testing Error System", 3}))
    end
end)
:catch(TestError, function(err)
    print("TestError: " .. err:what() .. " with error code: " .. err:code())
end)
:catch(DerivedError, function(err)
    print("DerivedError: " .. err:what() .. " with error code: " .. err:code())

    -- TODO: NESTED TRY-CATCHES 
    try(function() 
        print("Nested try-catch") 
        throw(TestError:new()) 
    end)
    :catch(function(err)
        print("Nested General catch:" .. err:what())
    end)

end)
:catch(function(err)
    print("General catch:" .. err:what())
end)
:finally(function()
    print("This should be called at the end!")
end)

try(function() throw(TestError:new()) end):catch(Test, function(err) print(err:what()) end) -- this should fail because Test is not a class derived from Caelum.Error