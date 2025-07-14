local c = require "Caelum"

local case = 3

switch(case) {
    [1] = function() 
        print("One") 
    end,
    [2] = function() 
        print("Two") 
    end,
    [3] = function() 
        print("Three") 
    end,
    [4] = function() 
        print("Four") 
    end,
    [5] = function() 
        print("Five") 
    end,
}