local c = require "Caelum"

MyClass = c.class "MyClass" {
    val = c.int(50)
    .title("Value")
    .desc("Test Value")
    .category("Testing fields")
    .range(0, 50),

    we_dont_care_about_this_field = c.int(0)
    .title("Dont care")
    .desc("We add a description just for the sake of it")
    .category("We dont care")
    .nullable()
    .hidden()
    .readonly(),

    __init = function(self, init_values)
        if type(init_values) == "number" then
            self.val = init_values
        end
    end
}

local instance = MyClass:new(20)

print("====================================================================")
print("Field info for 'val':")
print("====================================================================")
local val_field_info = c.get_field_info(instance, "val")
print("\tValue: " .. instance.val)
print("\tTitle: " .. val_field_info.title)
print("\tDescription: " .. val_field_info.description)
print("\tCategory: " .. val_field_info.category)
print("\tMin: " .. val_field_info.min .. " and Max: " .. val_field_info.max)

print("====================================================================")
print("Field info for 'we_dont_care_about_this_field':")
print("====================================================================")
local wdc_field_info = c.get_field_info(instance, "we_dont_care_about_this_field")
print("\tValue: " .. instance.we_dont_care_about_this_field)
print("\tTitle: " .. wdc_field_info.title)
print("\tDescription: " .. wdc_field_info.description)
print("\tCategory: " .. wdc_field_info.category)
print("====================================================================")

print("Get all fields of MyClass")
print("====================================================================")
local allFields = c.get_all_fields(instance)
for fieldName, info in pairs(allFields) do
    print(string.format("\tField: %s, Type: %s, Category: %s", info.name, info.type, info.category))
end
print("====================================================================")

print("Get all category of MyClass")
print("====================================================================")
local allCategories = c.get_all_categories(instance)
for _, cat in ipairs(allCategories) do
    print("  - " .. cat)
end
print("====================================================================")


instance.we_dont_care_about_this_field = 20