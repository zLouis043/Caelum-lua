local TS = require "tests.test_suite"
local Caelum = require "src.Caelum"

local assert_equal = TS.assert_equal
local assert_not_equal = TS.assert_not_equal
local assert_true = TS.assert_true
local assert_false = TS.assert_false
local assert_nil = TS.assert_nil
local assert_not_nil = TS.assert_not_nil
local assert_type = TS.assert_type
local assert_contains = TS.assert_contains
local assert_throws = TS.assert_throws

-- =============================================================================
-- TEST COMMON DEFINITIONS 
-- =============================================================================

Caelum.enum("PlayerStatus", { "Idle", "Walking", "Running" }, { default = "Idle" })

local Vector2 = Caelum.struct "Vector2" {
    x = Caelum.float(0.0),
    y = Caelum.float(0.0)
}

local Entity = Caelum.class "Entity" {
    id = Caelum.int(0),
    position = Caelum.struct_field(Vector2)
}

local Player = Caelum.class("Player", Entity) {
    name = Caelum.string("Guest"),
    health = Caelum.int(100).range(0, 100),
    status = Caelum.enum_field("PlayerStatus"),
    inventory = Caelum.array("string")
}

local Colors = Caelum.enum("Colors", { "Red", "Green", "Blue" }, { default = "Red" })

local GrandParent = Caelum.class "GrandParent" {
    gp_val = Caelum.int(1),
    get_value = function(self) return self.gp_val end
}
    
local Parent = Caelum.class("Parent", GrandParent) {
    p_val = Caelum.int(2),
    get_value = function(self) return self.p_val end
}

local Child = Caelum.class("Child", Parent) {
    c_val = Caelum.int(3),
    get_value = function(self) return self.c_val end
}

local Animal = Caelum.class "Animal" {
    name = Caelum.string("")
}

local Dog = Caelum.class("Dog", Animal) {
    bark = function(self) return "Woof!" end
}

local Cat = Caelum.class("Cat", Animal) {
    meow = function(self) return "Meow!" end
}

local Zoo = Caelum.class "Zoo" {
    animal = Caelum.field(Animal, nil).nullable()
}

-- =============================================================================
-- UNIT TESTS
-- =============================================================================

TS.unit_test("Definition and instantiation of a struct", function()
    local vec = Vector2:new({ x = 10.5, y = -5 })
    assert_not_nil(vec)
    assert_equal(vec.x, 10.5)
    assert_equal(vec.y, -5)
    assert_equal(Caelum.get_name(vec), "Vector2")
end)

TS.unit_test("Definition and instantiation of a class", function()
    local player = Player:new({ name = "Luigi", health = 95 })
    assert_not_nil(player)
    assert_equal(player.name, "Luigi")
    assert_equal(player.health, 95)
    assert_equal(Caelum.get_name(player), "Player")
end)

TS.unit_test("Default values", function()
    local player = Player:new()
    assert_equal(player.name, "Guest")
    assert_equal(player.health, 100)
    assert_equal(player.status, "Idle")
    assert_equal(player.position.x, 0.0)
end)

TS.unit_test("Enum: Basic operations", function()
    local Test = Caelum.class "Test" {
        color = Caelum.field(Colors)
    }

    local test = Test:new()
    
    assert_equal(test.color, "Red")
    assert_equal(Colors.get_index("Green"), 2)
    assert_equal(Colors.get_next("Green"), "Blue")
    assert_equal(Colors.get_next("Blue"), "Red")
end)

TS.unit_test("Enum: Validation", function()
    local Test = Caelum.class "Test" {
        color = Caelum.field(Colors)
    }

    local test = Test:new()
    
    assert_throws(function() test.color = "Yellow" end, "Should reject invalid enum value")
end)

TS.unit_test("Inheritance'", function()
    local player = Player:new({ id = 123, position = { x = 10, y = 20 } })
    assert_equal(player.id, 123)
    assert_equal(player.position.x, 10) 
    assert_equal(Caelum.get_name(player), "Player")
end)


    
TS.unit_test("Inheritance: Method overriding", function()
    
    local b = Parent:new{ p_val = 5 }
    local d = Child:new{ c_val = 10 }
    
    assert_equal(b:get_value(), 5)
    assert_equal(d:get_value(), 10)
end)

TS.unit_test("Inheritance: Multiple levels", function()    
    local c = Child:new()
    assert_equal(c.gp_val, 1)
    assert_equal(c.p_val, 2)
    assert_equal(c.c_val, 3)
end)

TS.unit_test("Type Checking: Correct types", function()
    local p = Player:new()
    p.health = 50
    assert_equal(p.health, 50)
    p.name = "Mario"
    assert_equal(p.name, "Mario")
end)

TS.unit_test("Type Checking: Type errors", function()
    local p = Player:new()
    assert_throws(function() p.health = "full" end, "Should fail on assigning string to int")
    assert_throws(function() p.name = 12345 end, "Should fail on assigning number to string")
    assert_throws(function() p.position = { x = "a", y = "b" } end, "Should fail on assigning string to float in the struct")
end)

TS.unit_test("Type Validation: Polymorphic field assignment", function()
    
    local zoo = Zoo:new()
    zoo.animal = Dog:new{ name = "Fido" }
    assert_true(Caelum.instanceof(zoo.animal, Dog))
    
    zoo.animal = Cat:new{ name = "Whiskers" }
    assert_true(Caelum.instanceof(zoo.animal, Cat))
    
    assert_throws(function() zoo.animal = "Not an animal" end, "Should reject non-animal types")
end)

TS.unit_test("Validation: Range (min/max)", function()
    local p = Player:new()
    p.health = 0
    p.health = 100
    assert_throws(function() p.health = 101 end, "Health cannot be over 100")
    assert_throws(function() p.health = -10 end, "Health cannot be negative")
end)

TS.unit_test("Validation: Readonly field", function()
    local TestReadOnly = Caelum.struct "TestReadOnly" {
        id = Caelum.int().readonly()
    }
    local t = TestReadOnly:new({ id = 10 })
    assert_equal(t.id, 10)
    assert_throws(function() t.id = 20 end, "Readonly fields cannot be modified")
end)

TS.unit_test("Validation: Nullable field", function()
    local TestNullable = Caelum.struct "TestNullable" {
        value = Caelum.string("default").nullable()
    }
    local t = TestNullable:new()
    t.value = nil
    assert_nil(t.value)
end)

TS.unit_test("Validation: Custom Validator", function()
    local TestValidator = Caelum.struct "TestValidator" {
        name = Caelum.string("bob").validator(function(val)
            return #val >= 3, "Name must be longer than 2 characters"
        end)
    }
    local t = TestValidator:new()
    t.name = "abc"
    assert_throws(function() t.name = "ab" end, "Custom validator should fail")
end)

TS.unit_test("Error Handling: Basic try-catch", function()
    local success, err = pcall(function()
        try(function()
            throw("Test error")
        end):catch(function(e)
            error("Caught and rethrown")
        end):close()
    end)

    assert_false(success)
    assert_contains(err.error.msg, "Caught and rethrown")
end)

TS.unit_test("Error Handling: Custom error classes", function()
    local MyError = Caelum.class("MyError", Caelum.Error) {
        code = Caelum.int(0)
    }
    
    local success, err = pcall(function()
        try(function()
            throw(MyError:new({"Test", 123}))
        end):catch(MyError, function(e)
            assert_equal(e.code, 123)
            assert_equal(e.msg, "Test")
        end)
    end)
    
    assert_true(success)
end)

TS.unit_test("Auto Conversion from table to struct/class", function()
    local p = Player:new()
    p.position = { x = 50, y = 50 }
    assert_equal(Caelum.get_name(p.position), "Vector2")
    assert_equal(p.position.x, 50)
end)

TS.unit_test("Array: Base Operation (push/pop)", function()
    local p = Player:new()
    p.inventory:push("sword")
    p.inventory:push("shield")
    assert_equal(#p.inventory, 2)
    assert_equal(p.inventory[1], "sword")
    
    local item = p.inventory:pop()
    assert_equal(item, "shield")
    assert_equal(#p.inventory, 1)
end)

TS.unit_test("Array: Element's Type-Checking", function()
    local p = Player:new()
    assert_throws(function() p.inventory:push(123) end, "String array cannot accept numbers")
end)

TS.unit_test("Array: Complex Types (Structs)", function()
    local Path = Caelum.struct "Path" {
        points = Caelum.array(Vector2)
    }
    local path = Path:new()
    path.points:push({ x = 1, y = 2 })
    path.points:push(Vector2:new({x = 3, y = 4}))
    
    assert_equal(#path.points, 2)
    assert_equal(Caelum.get_name(path.points[1]), "Vector2")
    assert_equal(path.points[1].y, 2)
end)

TS.unit_test("Array: Functional Methods (map, filter)", function()
    local Numbers = Caelum.struct "Numbers" { vals = Caelum.array("int") }
    local n = Numbers:new({ vals = {1, 2, 3, 4, 5} })
    
    local even = n.vals:filter(function(val) return val % 2 == 0 end)
    assert_equal(#even, 2)
    assert_equal(even[1], 2)
    assert_equal(even[2], 4)

    local doubled = n.vals:map(function(val) return val * 2 end)
    assert_equal(doubled[3], 6)
end)

TS.unit_test("Map: base Operations (set, get, remove)", function()
    local Scores = Caelum.class "Scores" {
        points = Caelum.map("string", "int")
    }
    local s = Scores:new()
    s.points:set("Luigi", 100)
    s.points["Mario"] = 150
    
    assert_equal(s.points:get("Luigi"), 100)
    assert_equal(s.points["Mario"], 150)
    assert_equal(#s.points, 2)
    
    local removed = s.points:remove("Luigi")
    assert_equal(removed, 100)
    assert_nil(s.points:get("Luigi"))
    assert_equal(#s.points, 1)
end)

TS.unit_test("Map: Key and Value Type-Checking", function()
    local Scores = Caelum.class "Scores" {
        points = Caelum.map("string", "int")
    }
    local s = Scores:new()
    assert_throws(function() s.points:set("Wario", "molti") end, "Map's value must be of type int")
    assert_throws(function() s.points:set(123, 100) end, "Map's key must be of type string")
end)

TS.unit_test("Map: Complex Types", function()
    local PlayerDB = Caelum.class "PlayerDB" {
        players = Caelum.map("int", Player)
    }
    local db = PlayerDB:new()
    
    db.players[1] = { name = "Peach", health = 80 }
    
    assert_equal(Caelum.get_name(db.players[1]), "Player")
    assert_equal(db.players[1].name, "Peach")
    assert_equal(db.players[1].id, 0)
end)

TS.unit_test("Map: Iteration and Methods (keys, values)", function()
    local Scores = Caelum.class "Scores" {
        points = Caelum.map("string", "int")
    }
    local s = Scores:new({ points = { a=1, b=2 } })
    
    local keys = s.points:keys()
    assert_equal(#keys, 2)
    assert_contains(keys, "a")
    assert_contains(keys, "b")
    
    local sum = 0
    s.points:forEach(function(value, key)
        sum = sum + value
    end)
    assert_equal(sum, 3)
end)


TS.unit_test("Reflection: get_field_info", function()
    local p = Player:new()
    local health_info = Caelum.get_field_info(p, "health")
    assert_equal(health_info.name, "health")
    assert_equal(health_info.type, "int")
    assert_equal(health_info.min, 0)
    assert_equal(health_info.max, 100)
end)

TS.unit_test("Reflection: get_all_fields", function()
    local p = Player:new()
    local all_fields = Caelum.get_all_fields(p)
    assert_not_nil(all_fields.name)
    assert_not_nil(all_fields.health)
    assert_not_nil(all_fields.id)
end)

TS.unit_test("Reflection: get_type e get_name", function()
    local p = Player:new()
    local v = Vector2:new()
    assert_equal(Caelum.get_type(p), "class")
    assert_equal(Caelum.get_name(p), "Player")
    assert_equal(Caelum.get_type(v), "struct")
    assert_equal(Caelum.get_name(v), "Vector2")
end)

TS.unit_test("Reflection: Instance information", function()    
    local t = Player:new()
    assert_equal(Caelum.get_name(t), "Player")
    assert_equal(Caelum.get_type(t), "class")
    assert_true(Caelum.instanceof(t, Player))
end)

TS.unit_test("Serialization: Basic struct", function()    
    local v = Vector2:new({ x = 1.5, y = 2.5 })

    local serialized = Caelum.serialize(v)
    local deserialized = Caelum.deserialize(serialized)

    assert_equal(deserialized.x, 1.5)
    assert_equal(deserialized.y, 2.5)
    assert_equal(Caelum.get_name(deserialized), "Vector2")
end)

TS.unit_test("Serialization: Class with inheritance", function()    
    local d = Child:new{ c_val = 10, p_val = 20}

    local serialized = Caelum.serialize(d)
    local deserialized = Caelum.deserialize(serialized)

    assert_equal(deserialized.c_val, 10)
    assert_equal(deserialized.p_val, 20)
    assert_true(Caelum.instanceof(deserialized, Child))
end)

TS.unit_test("Switch Statement: Basic functionality", function()
    local result
    local case = 2
    
    switch(case) {
        [1] = function() result = "one" end,
        [2] = function() result = "two" end,
        [3] = function() result = "three" end,
        default = function() result = "unknown" end
    }
    
    assert_equal(result, "two")
end)

TS.unit_test("Switch Statement: Default case", function()
    local result
    local case = 5
    
    switch(case) {
        [1] = function() result = "one" end,
        [2] = function() result = "two" end,
        default = function() result = "default" end
    }
    
    assert_equal(result, "default")
end)

-- =============================================================================
-- PERFORMANCE TESTS
-- =============================================================================

local NUM_ITERATIONS = 1000000

TS.performance_test(string.format("Instance Creation (Validation ON) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("strict")
    for i = 1, NUM_ITERATIONS do
        local v = Vector2:new({ x = i, y = -i })
    end
end)

TS.performance_test(string.format("Field assignments (Validation ON) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("strict")
    local p = Player:new()
    for i = 1, NUM_ITERATIONS do
        p.health = (i % 100)
    end
end)

TS.performance_test(string.format("Array Push (Validation ON) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("strict")
    local p = Player:new()
    for i = 1, NUM_ITERATIONS do
        p.inventory:push("item" .. i)
    end
end)

TS.performance_test(string.format("Map Set (Validation ON) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("strict")
    local Scores = Caelum.class "Scores" { points = Caelum.map("string", "int") }
    local s = Scores:new()
    for i = 1, NUM_ITERATIONS do
        s.points["player"..i] = i
    end
end)

TS.performance_test(string.format("Serialization/Deserialization (Validation ON) on %d iterations", NUM_ITERATIONS/10), function()
    Caelum.setValidationLevel("strict")
    local v = Vector2:new{ x = 1.5, y = 2.5 }
    
    for i = 1, NUM_ITERATIONS do
        local serialized = Caelum.serialize(v)
        local deserialized = Caelum.deserialize(serialized)
    end
end)

TS.performance_test(string.format("Instance Creation (Validation OFF) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("none")
    for i = 1, NUM_ITERATIONS do
        local v = Vector2:new({ x = i, y = -i })
    end
    Caelum.setValidationLevel("strict")
end)

TS.performance_test(string.format("Field assignments (Validation OFF) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("none")
    local p = Player:new()
    for i = 1, NUM_ITERATIONS do
        p.health = (i % 100)
    end
    Caelum.setValidationLevel("strict")
end)

TS.performance_test(string.format("Array Push (Validation OFF) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("none")
    local p = Player:new()
    for i = 1, NUM_ITERATIONS do
        p.inventory:push("item" .. i)
    end
    Caelum.setValidationLevel("strict")
end)

TS.performance_test(string.format("Map Set (Validation OFF) on %d iterations", NUM_ITERATIONS), function()
    Caelum.setValidationLevel("none")
    local Scores = Caelum.class "Scores" { points = Caelum.map("string", "int") }
    local s = Scores:new()
    for i = 1, NUM_ITERATIONS do
        s.points["player"..i] = i
    end
   Caelum.setValidationLevel("strict")
end)

TS.performance_test(string.format("Serialization/Deserialization (Validation OFF) on %d iterations", NUM_ITERATIONS/10), function()
    Caelum.setValidationLevel("none")
    local v = Vector2:new{ x = 1.5, y = 2.5 }
    
    for i = 1, NUM_ITERATIONS do
        local serialized = Caelum.serialize(v)
        local deserialized = Caelum.deserialize(serialized)
    end
    Caelum.setValidationLevel("strict")
end)

-- =============================================================================
-- RUN TESTS
-- =============================================================================

TS.parse_args(arg or {})
TS.run_all()

if TS.has_something_failed() then
    os.exit(1)
else
    os.exit(0)
end