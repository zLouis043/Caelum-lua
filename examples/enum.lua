local c = require "Caelum"

MyEnum = c.enum( "MyEnum", { "ONE", "TWO", "THREE", "FOUR" }, {
    default = "ONE"
})

MyClass = c.class "MyClass" {
    val = c.field(MyEnum, "TWO"),
}

local instance = MyClass:new()

print(instance.val)

print(MyEnum.get_index(instance.val))
print(MyEnum.get_next(instance.val))


instance.val = "FIVE"