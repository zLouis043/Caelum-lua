-- The main table for the Caelum library..
local Caelum = {}
-- A cache for array metatables. This helps to avoid recreating metatables for the same
-- array type, improving performance. The metatables are weakly referenced ('v' mode),
-- allowing them to be garbage collected if they are no longer in use.
local array_metatable_cache = setmetatable({}, { __mode = "v" })

--@param constructor (function|table) The constructor to use.
--@param init_val (*) The initial value or table of values to pass to the constructor.
--@param expected_type_name (string) [Optional] The name of the type being constructed, used for error messages.
--@return (*) The newly constructed object.
--@error If the constructor fails or is of an invalid type.
local function safe_construct(constructor, init_val, expected_type_name)
    -- If no constructor is provided, just return the initial value.
    if constructor == nil then
        return init_val
    end
    
    if type(constructor) == "function" then
        local success, result = pcall(constructor, init_val)
        if success then
            return result
        else
            error(string.format("Failed to construct %s: %s", expected_type_name or "object", result))
        end
    end
    
    if type(constructor) == "table" and constructor.new then
        local success, result = pcall(constructor.new, constructor, init_val or {})
        if success then
            return result
        else
            error(string.format("Failed to construct %s via .new(): %s", expected_type_name or "object", result))
        end
    end
    
    local mt = getmetatable(constructor)
    if mt and mt.__call then
        local success, result = pcall(constructor,  init_val)
        if success then
            return result
        else
            error(string.format("Failed to construct %s via __call: %s", expected_type_name or "object", result))
        end
    end
    
    error(string.format("Invalid constructor for %s: expected function or table with .new method", expected_type_name or "object"))
end


--[[
Creates a deep copy of an object, typically a table.
It recursively copies all keys and values, including metatables.
It also handles cyclic references to prevent infinite loops.

@param obj (*) The object to copy.
@param seen (table) [Internal] A table used to track already copied objects to handle cycles.
@return (*) A deep copy of the object.
]]
local function deep_copy(obj, seen)
    seen = seen or {}
    
    if type(obj) ~= "table" then
        return obj
    end

    if seen[obj] then
        return seen[obj]
    end
    
    local copy = {}
    seen[obj] = copy
    
    local mt = getmetatable(obj)
    if mt then
        setmetatable(copy, deep_copy(mt, seen))
    end
    
    for k, v in pairs(obj) do
        copy[deep_copy(k, seen)] = deep_copy(v, seen)
    end
    
    return copy
end

--[[
Validates and potentially converts a single element for a Caelum array.
This function is the core of type safety for arrays. It checks if an element
matches the expected primitive type or complex type (struct/class). If it's a
plain table meant to be a struct, it attempts to construct the struct instance.

@param element (*) The element to validate.
@param element_type_info (table|function) The constructor or type information for the element.
@param element_type_name (string) The expected type name (e.g., "int", "MyStruct").
@param index (number) The index of the element in the array, for error reporting.
@return (*) The validated and possibly converted element.
@error If validation or conversion fails.
]]
local function validate_and_convert_element(element, element_type_info, element_type_name, index)
    -- Validation can be globally disabled for performance.
    if not Caelum._validation_enabled then
        return element
    end

    local element_type = type(element)
    local errors = {}

    if element_type_name == "int" then
        if element_type ~= "number" or element ~= math.floor(element) then
            table.insert(errors, string.format("expected int, got %s", element_type))
        end
    elseif element_type_name == "float" then
        if element_type ~= "number" then
            table.insert(errors, string.format("expected float, got %s", element_type))
        end
    elseif element_type_name == "string" then
        if element_type ~= "string" then
            table.insert(errors, string.format("expected string, got %s", element_type))
        end
    elseif element_type_name == "bool" then
        if element_type ~= "boolean" then
            table.insert(errors, string.format("expected boolean, got %s", element_type))
        end
    else
        if element_type == "table" then
            local element_mt = getmetatable(element)
            local element_class_table = element_mt and rawget(element_mt, "__class_table__")

            if element_class_table then
                local actual_type_name = element_class_table.__name
                if actual_type_name ~= element_type_name then
                    table.insert(errors, string.format("expected %s, got %s", element_type_name, actual_type_name))
                end
            else
                if element_type_info then
                    local success, converted = pcall(function()
                        return safe_construct(element_type_info, element, element_type_name)
                    end)
                    element = converted

                    local converted_mt = getmetatable(converted)
                    local converted_class_table = converted_mt and rawget(converted_mt, "__class_table__")
                    if converted_class_table then
                        local converted_type_name = converted_class_table.__name
                        if converted_type_name ~= element_type_name then
                            table.insert(errors, string.format("conversion failed: expected %s, got %s", element_type_name, converted_type_name))
                        end
                    end
                else
                    table.insert(errors, string.format("expected %s, got plain table", element_type_name))
                end
            end
        else
            table.insert(errors, string.format("expected %s, got %s", element_type_name, element_type))
        end
    end

    if #errors > 0 then
        local error_msg = string.format("Array element validation failed at index %d: %s", index, table.concat(errors, "; "))
        error(error_msg)
    end

    return element
end

--[[
Validates all existing elements in an array proxy.
This is typically called when an array is first created from a plain table,
to ensure all initial elements conform to the specified type.

@param proxy (table) The array proxy table.
]]
local function validate_existing_elements(proxy)
    if not Caelum._validation_enabled then
        return
    end

    local raw_array = rawget(proxy, "__array_data__")
    local element_type_info = rawget(proxy, "__element_type_info__")
    local element_type_name = rawget(proxy, "__element_type_name__")

    for i = 1, #raw_array do
        local element = raw_array[i]
        if element ~= nil then
            local validated_element = validate_and_convert_element(element, element_type_info, element_type_name, i)
            raw_array[i] = validated_element
        end
    end
end

--[[
Set the value of the element of an array at that index position.
@param proxy (table) The array proxy.
@param index (number) The index to set.
@param value (*) The new value for the element.
@error If element validation, or array-level validation fails.
]]
local function array_set_element(proxy, index, value)
    local raw_array = rawget(proxy, "__array_data__")
    local element_type_info = rawget(proxy, "__element_type_info__")
    local element_type_name = rawget(proxy, "__element_type_name__")
    local field_meta = rawget(proxy, "__field_meta__")
    local parent_instance = rawget(proxy, "__parent_instance__")
    local parent_field_name = rawget(proxy, "__parent_field_name__")

    if not raw_array then
        error("Array data not initialized")
    end

    local validated_element = validate_and_convert_element(value, element_type_info, element_type_name, index)
    
    local old_value = raw_array[index]
    raw_array[index] = validated_element

    if field_meta and field_meta.validate_fn and Caelum._validation_enabled then
        local pcall_returns = { pcall(field_meta.validate_fn, proxy, parent_instance) }
        local pcall_ok = pcall_returns[1]
        local validation_success = pcall_returns[2]
        local error_message = pcall_returns[3]

        if not pcall_ok then
            raw_array[index] = old_value
            error("Array validator script error: " .. tostring(validation_success))
        elseif not validation_success then
            raw_array[index] = old_value
            error(string.format("Array validation failed: %s", error_message or "invalid state"))
        end
    end

    if parent_instance and parent_field_name then
        local parent_mt = getmetatable(parent_instance)
        local parent_class_table = parent_mt and rawget(parent_mt, "__class_table__")
        if parent_class_table then
            local on_field_changed = rawget(parent_class_table, "__on_field_changed__")
            if on_field_changed and type(on_field_changed) == "function" then
                on_field_changed(parent_instance, parent_field_name, proxy)
            end
        end
    end
end

local array_push, array_pop, array_insert, array_remove, array_clear
local array_find, array_forEach, array_map, array_filter, validate_array_completely

local array_handlers = {
    push    = function(self, value) return array_push(self, value) end,
    pop     = function(self) return array_pop(self) end,
    insert  = function(self, index, value) return array_insert(self, index, value) end,
    remove  = function(self, index) return array_remove(self, index) end,
    clear   = function(self) return array_clear(self) end,
    find    = function(self, predicate) return array_find(self, predicate) end,
    forEach = function(self, callback) return array_forEach(self, callback) end,
    map     = function(self, callback) return array_map(self, callback) end,
    filter  = function(self, predicate) return array_filter(self, predicate) end,
    validate = function(self) return validate_array_completely(self) end,
}

--[[
Creates and caches the metatable for a Caelum array proxy.
@param element_type_info (table|function) The constructor or type info for elements.
@param element_type_name (string) The name of the element type.
@param field_meta (table) Metadata about the field this array belongs to.
@return (table) The array metatable.
]]
local function create_array_metatable(element_type_info, element_type_name, field_meta)
    return {
        __index = function(proxy, key)
            if key == "length" or key == "size" then
                return #rawget(proxy, "__array_data__")
            elseif array_handlers[key] then
                return array_handlers[key]
            elseif type(key) == "number" and key > 0 and key == math.floor(key) then
                local raw_array = rawget(proxy, "__array_data__")
                return raw_array[key]
            else
                return rawget(proxy, key)
            end
        end,

        __newindex = function(proxy, key, value)
            if type(key) == "number" and key > 0 and key == math.floor(key) then
                array_set_element(proxy, key, value)
            else
                if type(key) == "string" and key:match("^__.*__$") then
                    error("Cannot modify array metadata: " .. key)
                end
                rawset(proxy, key, value)
            end
        end,

        __len = function(proxy)
            local raw_array = rawget(proxy, "__array_data__")
            return #raw_array
        end,

        __pairs = function(proxy)
            local raw_array = rawget(proxy, "__array_data__")
            return pairs(raw_array)
        end,
        __ipairs = function(proxy)
            local raw_array = rawget(proxy, "__array_data__")
            return ipairs(raw_array)
        end,

        __tostring = function(proxy)
            local raw_array = rawget(proxy, "__array_data__")
            local element_type_name = rawget(proxy, "__element_type_name__")
            local elements = {}
            for i = 1, #raw_array do
                local elem_str = tostring(raw_array[i])
                table.insert(elements, elem_str)
            end
            return string.format("[%s]<%s>", table.concat(elements, ", "), element_type_name)
        end,

        __eq = function(proxy_a, proxy_b)
            if type(proxy_b) ~= "table" or not rawget(proxy_b, "__array_data__") then return false end
            local raw_a = rawget(proxy_a, "__array_data__")
            local raw_b = rawget(proxy_b, "__array_data__")
            if #raw_a ~= #raw_b then return false end

            for i = 1, #raw_a do
                if raw_a[i] ~= raw_b[i] then return false end
            end
            return true
        end,

        __concat = function(proxy_a, proxy_b)
            local raw_a = rawget(proxy_a, "__array_data__")
            local element_type_info = rawget(proxy_a, "__element_type_info__")
            local element_type_name = rawget(proxy_a, "__element_type_name__")
            local field_meta = rawget(proxy_a, "__field_meta__")

            local result = {}

            for i = 1, #raw_a do
                table.insert(result, raw_a[i])
            end

            local raw_b = type(proxy_b) == "table" and (rawget(proxy_b, "__array_data__") or proxy_b) or {proxy_b}
            
            for i = 1, #raw_b do
                local validated_element = validate_and_convert_element(raw_b[i], element_type_info, element_type_name, #result + 1)
                table.insert(result, validated_element)
            end

            return create_array_proxy(result, element_type_info, element_type_name, field_meta)
        end
    }
end

--[[
Creates a proxy table that wraps a raw Lua table to behave like a typed array.
It sets up the metatable and all necessary internal data for validation and functionality.

@param raw_array (table) The initial table of elements. Can be empty.
@param element_type_info (table|function) The constructor or type info for elements.
@param element_type_name (string) The name of the element type.
@param field_meta (table) Metadata about the class field this array belongs to.
@param parent_instance (table) The instance that holds this array.
@param field_name (string) The name of the field on the parent instance.
@return (table) The newly created array proxy.
]]
local function create_array_proxy(raw_array, element_type_info, element_type_name, field_meta, parent_instance, field_name)
    if type(raw_array) ~= "table" then
        raw_array = {}
    end

    local cache_key = element_type_name .. (field_meta and field_meta.__field_name_for_validation or "")

    local array_mt = array_metatable_cache[cache_key]
    if not array_mt then
        array_mt = create_array_metatable(element_type_info, element_type_name, field_meta)
        array_metatable_cache[cache_key] = array_mt
    end
    local proxy = {
        __array_data__ = raw_array,
        __element_type_info__ = element_type_info,
        __element_type_name__ = element_type_name,
        __field_meta__ = field_meta,
        __parent_instance__ = parent_instance, 
        __parent_field_name__ = field_name
    }

    setmetatable(proxy, array_mt)

    -- If validation is enabled, check all the initial elements provided in `raw_array`.
    if Caelum._validation_enabled then
        validate_existing_elements(proxy)
    end

    return proxy
end

--[[
Performs a complete and deep validation of the array.

@param proxy (table) The array proxy to validate.
@return (boolean) `true` if the entire array is valid, `false` otherwise.
@return (table) A list of error messages if validation fails.
]]
function validate_array_completely(proxy)
    local raw_array = rawget(proxy, "__array_data__")
    local element_type_info = rawget(proxy, "__element_type_info__")
    local element_type_name = rawget(proxy, "__element_type_name__")
    local field_meta = rawget(proxy, "__field_meta__")
    local parent_instance = rawget(proxy, "__parent_instance__")
    local parent_field_name = rawget(proxy, "__parent_field_name__")
    local all_errors = {}

    for i = 1, #raw_array do
        local element = raw_array[i]
        if element ~= nil then
            local success, errors = pcall(validate_and_convert_element, element, element_type_info, element_type_name, i)
            if not success then
                table.insert(all_errors, string.format("Element %d: %s", i, errors))
            else
                if type(element) == "table" then
                    local element_mt = getmetatable(element)
                    local element_class_table = element_mt and rawget(element_mt, "__class_table__")
                    if element_class_table then
                        local element_validation_success, element_validation_errors = pcall(Caelum.validate_instance, element)
                        if not element_validation_success then
                            table.insert(all_errors, string.format("Element %d internal validation: %s", i, table.concat(element_validation_errors, "; ")))
                        end
                    end
                end
            end
        end
    end

    if field_meta and parent_instance and parent_field_name then
        local valid, errors = Caelum.validate_field(parent_instance, parent_field_name, raw_array, field_meta)
        if not valid then
            for _, err in ipairs(errors) do
                table.insert(all_errors, err)
            end
        end
    end

    return #all_errors == 0, all_errors
end

--[[ Implementation of the `push` method for Caelum arrays. ]]
array_push = function(proxy, value)
    local raw_array = rawget(proxy, "__array_data__")
    local index = #raw_array + 1
    -- Use array_set_element to ensure the new value is validated.
    array_set_element(proxy, index, value)
    return proxy -- Allow chaining.
end

--[[ Implementation of the `pop` method. ]]
array_pop = function(proxy)
    local raw_array = rawget(proxy, "__array_data__")
    if #raw_array == 0 then return nil end

    local value = table.remove(raw_array)
    
    local field_meta = rawget(proxy, "__field_meta__")
    local parent_instance = rawget(proxy, "__parent_instance__")
    local parent_field_name = rawget(proxy, "__parent_field_name__")
    if field_meta and field_meta.validate_fn and Caelum._validation_enabled then
        local valid, errors = Caelum.validate_field(parent_instance, parent_field_name, proxy, field_meta)
        if not valid then
            error(string.format("Array validation failed after pop for field '%s': %s", parent_field_name, table.concat(errors, "; ")))
        end
    end

    if parent_instance and parent_field_name then
        local parent_mt = getmetatable(parent_instance)
        local parent_class_table = parent_mt and rawget(parent_mt, "__class_table__")
        if parent_class_table then
            local on_field_changed = rawget(parent_class_table, "__on_field_changed__")
            if on_field_changed and type(on_field_changed) == "function" then
                on_field_changed(parent_instance, parent_field_name, proxy)
            end
        end
    end
    
    return value
end

--[[ Implementation of the `insert` method. ]]
array_insert = function(proxy, index, value)
    local raw_array = rawget(proxy, "__array_data__")
    if index < 1 or index > #raw_array + 1 then
        error(string.format("Invalid index %d for insert (array size %d)", index, #raw_array))
    end

    table.insert(raw_array, index, nil) 
    array_set_element(proxy, index, value) 
    
    return proxy
end

--[[ Implementation of the `remove` method. ]]
array_remove = function(proxy, index)
    local raw_array = rawget(proxy, "__array_data__")
    if index < 1 or index > #raw_array then
        error(string.format("Invalid index %d for remove (array size %d)", index, #raw_array))
    end
    local value = table.remove(raw_array, index)

    local field_meta = rawget(proxy, "__field_meta__")
    local parent_instance = rawget(proxy, "__parent_instance__")
    local parent_field_name = rawget(proxy, "__parent_field_name__")
    if field_meta and field_meta.validate_fn and Caelum._validation_enabled then
        local valid, errors = Caelum.validate_field(parent_instance, parent_field_name, proxy, field_meta)
        if not valid then
            error(string.format("Array validation failed after remove for field '%s': %s", parent_field_name, table.concat(errors, "; ")))
        end
    end
    if parent_instance and parent_field_name then
        local parent_mt = getmetatable(parent_instance)
        local parent_class_table = parent_mt and rawget(parent_mt, "__class_table__")
        if parent_class_table then
            local on_field_changed = rawget(parent_class_table, "__on_field_changed__")
            if on_field_changed and type(on_field_changed) == "function" then
                on_field_changed(parent_instance, parent_field_name, proxy)
            end
        end
    end
    
    return value
end

--[[ Implementation of the `clear` method. ]]
array_clear = function(proxy)
    local raw_array = rawget(proxy, "__array_data__")
    for i = #raw_array, 1, -1 do
        raw_array[i] = nil
    end

    local field_meta = rawget(proxy, "__field_meta__")
    local parent_instance = rawget(proxy, "__parent_instance__")
    local parent_field_name = rawget(proxy, "__parent_field_name__")
    if field_meta and field_meta.validate_fn and Caelum._validation_enabled then
        local valid, errors = Caelum.validate_field(parent_instance, parent_field_name, proxy, field_meta)
        if not valid then
            error(string.format("Array validation failed after clear for field '%s': %s", parent_field_name, table.concat(errors, "; ")))
        end
    end
    if parent_instance and parent_field_name then
        local parent_mt = getmetatable(parent_instance)
        local parent_class_table = parent_mt and rawget(parent_mt, "__class_table__")
        if parent_class_table then
            local on_field_changed = rawget(parent_class_table, "__on_field_changed__")
            if on_field_changed and type(on_field_changed) == "function" then
                on_field_changed(parent_instance, parent_field_name, proxy)
            end
        end
    end
end

--[[
Implementation of the `find` method.
Iterates the array and returns the first element for which the predicate function returns true.

@param proxy (table) The array proxy.
@param predicate (function) A function that takes `(element, index, array)` and returns boolean.
@return (*) The found element, or `nil`.
]]
array_find = function(proxy, predicate)
    local raw_array = rawget(proxy, "__array_data__")
    for i = 1, #raw_array do
        if predicate(raw_array[i], i, proxy) then
            return raw_array[i]
        end
    end
    return nil
end

--[[
Implementation of the `forEach` method.
Executes a callback function for each element in the array.

@param proxy (table) The array proxy.
@param callback (function) A function that takes `(element, index, array)`.
]]
array_forEach = function(proxy, callback)
    local raw_array = rawget(proxy, "__array_data__")
    for i = 1, #raw_array do
        callback(raw_array[i], i, proxy)
    end
end

--[[
Implementation of the `map` method.
Creates a new Caelum array containing the results of calling a callback function
on every element in the original array.

@param proxy (table) The array proxy.
@param callback (function) A function that takes `(element, index, array)` and returns a new value.
@return (table) A new Caelum array proxy.
]]
array_map = function(proxy, callback)
    local raw_array = rawget(proxy, "__array_data__")
    local new_array_data = {}
    local element_type_info = rawget(proxy, "__element_type_info__")
    local element_type_name = rawget(proxy, "__element_type_name__")
    local field_meta = rawget(proxy, "__field_meta__")

    for i = 1, #raw_array do
        local transformed_element = callback(raw_array[i], i, proxy)
        local validated_element = validate_and_convert_element(transformed_element, element_type_info, element_type_name, i)
        table.insert(new_array_data, validated_element)
    end
    return create_array_proxy(new_array_data, element_type_info, element_type_name, field_meta)
end

--[[
Implementation of the `filter` method.
Creates a new Caelum array with all elements that pass the test implemented
by the provided predicate function.

@param proxy (table) The array proxy.
@param predicate (function) A function that takes `(element, index, array)` and returns boolean.
@return (table) A new Caelum array proxy.
]]
array_filter = function(proxy, predicate)
    local raw_array = rawget(proxy, "__array_data__")
    local new_array_data = {}
    local element_type_info = rawget(proxy, "__element_type_info__")
    local element_type_name = rawget(proxy, "__element_type_name__")
    local field_meta = rawget(proxy, "__field_meta__")

    for i = 1, #raw_array do
        if predicate(raw_array[i], i, proxy) then
            table.insert(new_array_data, raw_array[i])
        end
    end
    return create_array_proxy(new_array_data, element_type_info, element_type_name, field_meta)
end

--[[
Public API function to get basic information about a Caelum array proxy.

@param array_proxy (table) The Caelum array.
@return (table|nil) A table with info (`length`, `element_type`, etc.), or `nil` if not a Caelum array.
]]
function Caelum.get_array_info(array_proxy)
    if type(array_proxy) ~= "table" then
        return nil
    end

    -- Check for the internal marker field.
    local raw_array = rawget(array_proxy, "__array_data__")
    if not raw_array then
        return nil
    end

    return {
        length = #raw_array,
        element_type = rawget(array_proxy, "__element_type_name__"),
        parent_field = rawget(array_proxy, "__parent_field_name__"),
        parent_instance = rawget(array_proxy, "__parent_instance__")
    }
end

--------------------------------------------------------------------------------
-- MAP
--------------------------------------------------------------------------------
local map_set, map_get, map_remove, map_clear, map_has, map_keys, map_values, map_forEach, validate_map_completely
local create_map_proxy

--[[
Validates and converts a single key or value for a Caelum map.

@param item (*) The key or value to validate.
@param item_type_info (table|function) The constructor or type information for the item.
@param item_type_name (string) The expected type name (e.g., "int", "MyStruct").
@param item_role_name (string) The role of the item ("key" or "value") for error messages.
@return (*) The validated and possibly converted item.
@error If validation or conversion fails.
]]
local function validate_and_convert_single_item(item, item_type_info, item_type_name, item_role_name)
    if not Caelum._validation_enabled then
        return item
    end

    local item_type = type(item)
    local errors = {}
    
    local function format_error(expected, got)
        return string.format("for map %s: expected %s, got %s", item_role_name, expected, got)
    end

    if item_type_name == "int" then
        if item_type ~= "number" or item ~= math.floor(item) then table.insert(errors, format_error("int", item_type)) end
    elseif item_type_name == "float" then
        if item_type ~= "number" then table.insert(errors, format_error("float", item_type)) end
    elseif item_type_name == "string" then
        if item_type ~= "string" then table.insert(errors, format_error("string", item_type)) end
    elseif item_type_name == "bool" then
        if item_type ~= "boolean" then table.insert(errors, format_error("bool", item_type)) end
    else
        if item_type == "table" then
            local item_mt = getmetatable(item)
            local item_class_table = item_mt and rawget(item_mt, "__class_table__")

            if item_class_table then
                local actual_type_name = item_class_table.__name
                if actual_type_name ~= item_type_name then
                    table.insert(errors, format_error(item_type_name, actual_type_name))
                end
            else
                if item_type_info then
                    local success, converted = pcall(safe_construct, item_type_info, item, item_type_name)
                    if not success then
                        error(string.format("Failed to construct map %s: %s", item_role_name, tostring(converted)))
                    end
                    item = converted
                else
                    table.insert(errors, format_error(item_type_name, "plain table"))
                end
            end
        else
            table.insert(errors, format_error(item_type_name, item_type))
        end
    end

    if #errors > 0 then
        error(table.concat(errors, "; "))
    end
    
    return item
end

--[[
Validates and converts a key-value pair for a Caelum map.

@param key (*) The key to validate.
@param value (*) The value to validate.
@param ... (type info) Metadata for keys and values.
@param skip_value_validation (boolean) If true, only the key is validated.
@return validated_key, validated_value
]]
local function validate_and_convert_entry(key, value, key_type_name, key_type_info, value_type_name, value_type_info, skip_value_validation)
    local validated_key = validate_and_convert_single_item(key, key_type_info, key_type_name, "key")
    
    if skip_value_validation then
        return validated_key, nil
    end

    local validated_value = validate_and_convert_single_item(value, value_type_info, value_type_name, "value")
    
    return validated_key, validated_value
end

--[[
Validates all existing entries in a map proxy. This is called on creation.
It creates a new data table to handle cases where keys themselves are converted 
]]
local function validate_existing_entries(proxy)
    if not Caelum._validation_enabled then
        return
    end

    local raw_map = rawget(proxy, "__map_data__")
    local key_type_info = rawget(proxy, "__key_type_info__")
    local key_type_name = rawget(proxy, "__key_type_name__")
    local value_type_info = rawget(proxy, "__value_type_info__")
    local value_type_name = rawget(proxy, "__value_type_name__")
    
    local new_map_data = {}
    for key, value in pairs(raw_map) do
        local validated_key, validated_value = validate_and_convert_entry(key, value, key_type_name, key_type_info, value_type_name, value_type_info)
        new_map_data[validated_key] = validated_value
    end
    rawset(proxy, "__map_data__", new_map_data)
end

--[[ Core function for setting a key-value pair in a map, handling validation, rollback, and notifications. ]]
local function map_set_entry(proxy, key, value)
    local raw_map = rawget(proxy, "__map_data__")
    local key_type_info = rawget(proxy, "__key_type_info__")
    local key_type_name = rawget(proxy, "__key_type_name__")
    local value_type_info = rawget(proxy, "__value_type_info__")
    local value_type_name = rawget(proxy, "__value_type_name__")
    local field_meta = rawget(proxy, "__field_meta__")
    local parent_instance = rawget(proxy, "__parent_instance__")
    local parent_field_name = rawget(proxy, "__parent_field_name__")

    if not raw_map then error("Map data not initialized") end

    local validated_key, validated_value = validate_and_convert_entry(key, value, key_type_name, key_type_info, value_type_name, value_type_info)
    
    local old_value = raw_map[validated_key]
    raw_map[validated_key] = validated_value

    if field_meta and field_meta.validate_fn and Caelum._validation_enabled then
        local pcall_returns = { pcall(field_meta.validate_fn, proxy, parent_instance) }
        if not pcall_returns[1] then
            raw_map[validated_key] = old_value
            error("Map validator script error: " .. tostring(pcall_returns[2]))
        elseif not pcall_returns[2] then
            raw_map[validated_key] = old_value
            error(string.format("Map validation failed: %s", pcall_returns[3] or "invalid state"))
        end
    end
    
    if parent_instance and parent_field_name then
        local parent_mt = getmetatable(parent_instance)
        local parent_class_table = parent_mt and rawget(parent_mt, "__class_table__")
        if parent_class_table then
            local on_field_changed = rawget(parent_class_table, "__on_field_changed__")
            if on_field_changed and type(on_field_changed) == "function" then
                on_field_changed(parent_instance, parent_field_name, proxy)
            end
        end
    end
end

-- A table of standard methods for Caelum map proxies.
map_handlers = {
    set     = function(self, key, value) map_set_entry(self, key, value); return self end,
    get     = function(self, key) return self[key] end, 
    remove  = function(self, key) return map_remove(self, key) end,
    clear   = function(self) return map_clear(self) end,
    has     = function(self, key) return self[key] ~= nil end,
    keys    = function(self) return map_keys(self) end,
    values  = function(self) return map_values(self) end,
    forEach = function(self, callback) return map_forEach(self, callback) end,
    validate = function(self) return validate_map_completely(self) end,
}

--[[ Creates and caches the metatable for a Caelum map proxy. ]]
local function create_map_metatable(key_type_info, key_type_name, value_type_info, value_type_name, field_meta)
    return {
        __index = function(proxy, key)
            if map_handlers[key] then
                return map_handlers[key]
            else
                local validated_key, _ = validate_and_convert_entry(key, nil, key_type_name, key_type_info, value_type_name, value_type_info, true)
                return rawget(proxy, "__map_data__")[validated_key]
            end
        end,

        __newindex = function(proxy, key, value)
            if map_handlers[key] then error("Cannot overwrite map method: " .. key) end
            map_set_entry(proxy, key, value)
        end,

        __len = function(proxy)
            local raw_map = rawget(proxy, "__map_data__")
            local count = 0
            for _ in pairs(raw_map) do count = count + 1 end
            return count
        end,

        __pairs = function(proxy)
            return pairs(rawget(proxy, "__map_data__"))
        end,

        __tostring = function(proxy)
            local elements = {}
            for k, v in pairs(rawget(proxy, "__map_data__")) do
                table.insert(elements, tostring(k) .. ": " .. tostring(v))
            end
            return string.format("{%s}<%s, %s>", table.concat(elements, ", "), rawget(proxy, "__key_type_name__"), rawget(proxy, "__value_type_name__"))
        end,

        __eq = function(proxy_a, proxy_b)
            if type(proxy_b) ~= "table" or not rawget(proxy_b, "__map_data__") then return false end
            local raw_a = rawget(proxy_a, "__map_data__")
            local raw_b = rawget(proxy_b, "__map_data__")
            
            if #proxy_a ~= #proxy_b then return false end

            for k, v_a in pairs(raw_a) do
                if v_a ~= raw_b[k] then return false end
            end
            return true
        end,
    }
end

local map_metatable_cache = {}

--[[ Creates a proxy table that wraps a raw Lua table to behave like a typed map. ]]
create_map_proxy = function(raw_map, key_type_info, key_type_name, value_type_info, value_type_name, field_meta, parent_instance, field_name)
    if type(raw_map) ~= "table" then raw_map = {} end

    local cache_key = key_type_name .. "," .. value_type_name .. (field_meta and field_meta.__field_name_for_validation or "")
    local map_mt = map_metatable_cache[cache_key]
    if not map_mt then
        map_mt = create_map_metatable(key_type_info, key_type_name, value_type_info, value_type_name, field_meta)
        map_metatable_cache[cache_key] = map_mt
    end

    local proxy = {
        __map_data__ = raw_map,
        __key_type_info__ = key_type_info,
        __key_type_name__ = key_type_name,
        __value_type_info__ = value_type_info,
        __value_type_name__ = value_type_name,
        __field_meta__ = field_meta,
        __parent_instance__ = parent_instance,
        __parent_field_name__ = field_name
    }
    setmetatable(proxy, map_mt)

    if Caelum._validation_enabled then
        validate_existing_entries(proxy)
    end

    return proxy
end

--[[ Performs a complete and deep validation of a map proxy. ]]
function validate_map_completely(proxy)
    local all_errors = {}
    local success, err = pcall(validate_existing_entries, proxy)
    if not success then
        table.insert(all_errors, "Map contains invalid entries: " .. tostring(err))
    end
    return #all_errors == 0, all_errors
end

--[[ Implementation of map utility methods ]]
map_remove = function(proxy, key)
    local key_type_info = rawget(proxy, "__key_type_info__")
    local key_type_name = rawget(proxy, "__key_type_name__")
    local validated_key = validate_and_convert_single_item(key, key_type_info, key_type_name, "key")

    local raw_map = rawget(proxy, "__map_data__")
    local old_value = raw_map[validated_key]
    raw_map[validated_key] = nil

    return old_value
end

map_clear = function(proxy)
    rawset(proxy, "__map_data__", {})
end

map_keys = function(proxy)
    local keys_array = {}
    for k, _ in pairs(rawget(proxy, "__map_data__")) do table.insert(keys_array, k) end
    return keys_array
end

map_values = function(proxy)
    local values_array = {}
    for _, v in pairs(rawget(proxy, "__map_data__")) do table.insert(values_array, v) end
    return values_array
end

map_forEach = function(proxy, callback)
    for k, v in pairs(rawget(proxy, "__map_data__")) do callback(v, k, proxy) end
end

--[[ Public API function to get basic information about a Caelum map proxy. ]]
function Caelum.get_map_info(map_proxy)
    if type(map_proxy) ~= "table" or not rawget(map_proxy, "__map_data__") then return nil end
    local raw_map = rawget(map_proxy, "__map_data__")
    local count = 0
    for _ in pairs(raw_map) do count = count + 1 end
    
    return {
        size = count,
        key_type = rawget(map_proxy, "__key_type_name__"),
        value_type = rawget(map_proxy, "__value_type_name__"),
        parent_field = rawget(map_proxy, "__parent_field_name__"),
        parent_instance = rawget(map_proxy, "__parent_instance__")
    }
end


-- Internal list of base type names supported by Caelum.
local base_types = {
    "float", "int", "bool", "string", "reference", "enum", "struct", "class", "array"
}

-- A global registry for all defined Enum types.
Caelum.Enums = {}

-- A registry for primitive type handlers.
local Primitives = {}
Caelum.Primitives = Primitives

-- Helper function to register a primitive type.
local function primitive(name)
    local t = { __caelum_type = "primitive", __type_name = name }
    Primitives[name] = t
    return t
end

-- Register the built-in primitive types.
primitive("int")
primitive("float") 
primitive("bool")
primitive("string")

-- Create convenient public aliases for the primitive types (e.g., Caelum.Int).
Caelum.Int = Primitives.int
Caelum.Float = Primitives.float
Caelum.Bool = Primitives.bool
Caelum.String = Primitives.string

-- A global registry for all defined Caelum types (structs and classes).
-- This allows resolving types by name.
Caelum._type_registry = {}

-- A global flag to enable or disable validation.
-- Can be turned off in performance-critical sections of code.
Caelum._validation_enabled = true

--[[
Public API to globally enable or disable Caelum's validation.
Disabling validation can improve performance but sacrifices type safety.

@param enabled (boolean) `true` to enable validation, `false` to disable.
]]
function Caelum.setValidationEnabled(enabled)
    Caelum._validation_enabled = enabled
end

-- Forward declaration needed for mutual recursion.
local precompute_class_metadata

--[[
Registers a type constructor in the Caelum registry and also makes it a global variable.
This makes the type easily accessible from anywhere in the Lua state.

@param type_name (string) The name of the type.
@param type_constructor (table) The Caelum constructor table (the one with the `.new` method).
@return (table) The type constructor.
]]
local function register_type_global(type_name, type_constructor)
    Caelum._type_registry[type_name] = type_constructor
    _G[type_name] = type_constructor -- Make it global

    if type_constructor.__class_table then
        precompute_class_metadata(type_constructor.__class_table)
    end

    return type_constructor
end

--[[
Registers a type constructor in the Caelum registry only (does not make it global).

@param type_name (string) The name of the type.
@param type_constructor (table) The Caelum constructor table.
@return (table) The type constructor.
]]
local function register_type(type_name, type_constructor)
    Caelum._type_registry[type_name] = type_constructor

    if type_constructor.__class_table then
        precompute_class_metadata(type_constructor.__class_table)
    end

    return type_constructor
end

-- A cache for the metatables of Caelum instances (structs/classes).
-- Weak values ('v') ensure that if a class is no longer used, its metatable can be GC'd.
local metatable_cache = setmetatable({}, { __mode = "v" })

--[[
Validates a value against the rules defined in a field's metadata.
This is used by `__newindex` before assigning a value.

@param instance (table) The instance the field belongs to (for context in validators).
@param field_name (string) The name of the field.
@param value (*) The value to validate.
@param field_meta (table) The metadata for the field.
@return (boolean) `true` if valid, `false` otherwise.
@return (table) A list of error messages if invalid.
]]
function Caelum.validate_field(instance, field_name, value, field_meta)
    local errors = {}
    
    if field_meta.is_required and (value == nil or (type(value) == "string" and value == "")) then
        table.insert(errors, field_name.." is required")
    end

    if value ~= nil and (field_meta.__type == "float" or field_meta.__type == "int") then
        if field_meta.minval and value < field_meta.minval then
            table.insert(errors, field_name.." must be >= "..tostring(field_meta.minval))
        end
        if field_meta.maxval and value > field_meta.maxval then
            table.insert(errors, field_name.." must be <= "..tostring(field_meta.maxval))
        end
    end
    
    if value ~= nil and field_meta.__type == "enum" and field_meta.enum_values then
       local valid = false
        for _, enum_val in ipairs(field_meta.enum_values) do
            if value == enum_val then valid = true; break end
        end
        if not valid then
            table.insert(errors, field_name.." has invalid value '"..tostring(value).."'. Must be one of: "..table.concat(field_meta.enum_values, ", "))
        end
    end

    if field_meta.validate_fn then
        local pcall_returns = { pcall(field_meta.validate_fn, value, instance) }
        local pcall_ok = pcall_returns[1]
        local validation_success = pcall_returns[2]
        local error_message = pcall_returns[3]

        if not pcall_ok then
            table.insert(errors, "Validator script error: " .. tostring(validation_success))
        elseif not validation_success then
            table.insert(errors, error_message or (field_name .. " validation failed"))
        end
    end
    
    return #errors == 0, errors
end

--[[
Validates an entire instance by checking all its fields.
Also calls the class-level `__validate` method if it exists.

@param instance (table) The instance to validate.
@return (boolean) `true` if the instance is valid.
@return (table) A list of all validation errors.
]]
function Caelum.validate_instance(instance)
    local all_errors = {}
    local class_table = rawget(getmetatable(instance) or {}, "__class_table")
    if not class_table then
        table.insert(all_errors, "Not a valid Caelum instance.")
        return false, all_errors
    end

    local fields = rawget(class_table, "__fields__")
    if fields then
        for field_name, field_meta in pairs(fields) do
            local value = instance[field_name]
            local ok, errors = Caelum.validate_field(instance, field_name, value, field_meta)
            if not ok then
                for _, err in ipairs(errors) do
                    table.insert(all_errors, err)
                end
            end
        end
    end
    
    local validate_func = rawget(class_table, "__validate")
    if validate_func then
        local ok, err = pcall(validate_func, instance)
        if not ok then
            table.insert(all_errors, "Instance-level validator script failed: " .. tostring(err))
        elseif type(err) == "string" then
            table.insert(all_errors, "Instance validation failed: " .. err)
        end
    end
    
    return #all_errors == 0, all_errors
end

--[[
Creates the `__newindex` metamethod for a Caelum class/struct.
It's called every time a field is assigned a value (e.g., `instance.my_field = 10`).

@param class_table (table) The internal definition table for the class.
@return (function) The `__newindex` function.
]]
local function create_validating_newindex(class_table)
    return function(instance, field_name, value)

        if not Caelum._validation_enabled then
            rawset(instance.__data_storage__ or instance, field_name, value)
            return
        end

        local current_mt = getmetatable(instance)
        if not current_mt or rawget(current_mt, "__class_table") == nil then
            setmetatable(instance, get_cached_metatable(class_table))
        end

        local fields = rawget(class_table, "__fields__")
        local field_meta_table = fields and fields[field_name]

        if field_meta_table.is_readonly then
            local current_value = Caelum.get_field_value(instance, field_name)
            if current_value ~= nil then
                error("Field '" .. field_name .. "' is readonly")
            end
        end

        if field_meta_table then
            local expected_type = field_meta_table.__type
            
            local is_nullable = field_meta_table.is_nullable
            local value_type = type(value)
            local type_mismatch = false

            if is_nullable and value == nil then
                type_mismatch = false
            elseif (expected_type == "struct" or expected_type == "class") and value_type == "table" then
                local value_mt = getmetatable(value)
                local is_caelum_instance = value_mt and rawget(value_mt, "__class_table") ~= nil
                if not is_caelum_instance then
                    local constructor = field_meta_table.__type_table 
                    value = safe_construct(constructor, value, expected_type)
                end

                if value then
                    local actual_type_display = Caelum.get_name(value)
                    local expected_type_name = field_meta_table.__type_name
                    if actual_type_display ~= expected_type_name then
                        type_mismatch = true 
                    end 
                end

            elseif expected_type == "array" and value_type == "table" then
                local element_type_info = field_meta_table.__type_table
                local element_type_name = field_meta_table.__type_name

                local max_index = 0
                local non_numeric_keys = {}

                local array_data = rawget(value, "__array_data__") or value

                if type(array_data) ~= "table" then
                    error(string.format("Type mismatch for field '%s': Expected an array (table), got %s", field_name, type(value)))
                end

                for k, v in pairs(array_data) do
                    if type(k) == "number" and k > 0 and k == math.floor(k) then
                        max_index = math.max(max_index, k)
                    else
                        table.insert(non_numeric_keys, tostring(k))
                    end
                end
                
                if #non_numeric_keys > 0 then
                    error(string.format("Array field '%s' contains non-numeric keys: %s", 
                        field_name, table.concat(non_numeric_keys, ", ")))
                end
                value = create_array_proxy(array_data, element_type_info, element_type_name, field_meta_table, instance, field_name)
                type_mismatch = false
            elseif expected_type == "map" and value_type == "table" then
                if not rawget(value, "__map_data__") then
                    value = create_map_proxy(
                        value,
                        field_meta_table.__key_type_table,
                        field_meta_table.__key_type_name,
                        field_meta_table.__value_type_table,
                        field_meta_table.__value_type_name,
                        field_meta_table,
                        instance,
                        field_name
                    )
                end
                type_mismatch = false
            elseif expected_type == "int" then
                type_mismatch = value_type ~= "number" or value ~= math.floor(value)
            elseif expected_type == "float" then
                type_mismatch = value_type ~= "number"
            elseif expected_type == "bool" then
                type_mismatch = value_type ~= "boolean"
            elseif expected_type == "string" then
                type_mismatch = value_type ~= "string"
            elseif expected_type == "reference" then
                type_mismatch = not (value == nil or value_type == "table" or value_type == "userdata" or value_type == "thread" or value_type == "function")
            elseif expected_type == "enum" then
                type_mismatch = value_type ~= "string" and value_type ~= "number"
            else
                local actual_type_name = Caelum.get_name(value)
                if actual_type_name == "Unknown" then
                    type_mismatch = value_type ~= expected_type
                    type_mismatch = actual_type_name ~= field_meta_table.__type_name
                end
            end

            if type_mismatch then
                local actual_type_display = value_type
                if value_type == "table" then
                    
                    local instance_mt = getmetatable(value)
                    local instance_class_table = instance_mt and rawget(instance_mt, "__class_table")
                    if instance_class_table and instance_class_table.__name then
                        actual_type_display = instance_class_table.__name
                    end
                end
                error("Type mismatch for field '" .. field_name .. "': Expected '" .. (field_meta_table.__type_name or expected_type) .. "', got '" .. actual_type_display .. "'") --
            end

            local valid, errors = Caelum.validate_field(instance, field_name, value, field_meta_table)
            if not valid then
                error("Validation failed for field '" .. field_name .. "': " .. table.concat(errors, "; "))
            end
        end
        
        local data_storage = rawget(instance, "__data_storage__")
        if not data_storage then
            data_storage = {}
            rawset(instance, "__data_storage__", data_storage)
        end
        data_storage[field_name] = value

        if not rawget(instance, "__is_constructing") then
            local on_field_change = field_meta_table.on_field_change
            if on_field_change and type(on_field_change) == "function" then
                on_field_change(instance)
            end 
        end 
    end
end

--[[
Creates the `__index` metamethod for a Caelum class/struct.
This is called when a field is accessed (e.g., `local x = instance.my_field`).
The lookup order is:
1. The instance's private data storage (`__data_storage__`).
2. Methods defined in the class table.
3. "Simple fields" (non-Caelum fields) defined in the class table.

@param class_table (table) The internal definition table for the class.
@return (function) The `__index` function.
]]
local function create_validating_index(class_table)
    return function(instance, field_name)
        if field_name == "__class_table__" then
            return class_table
        end

        local data_storage = rawget(instance, "__data_storage__")
        if data_storage and data_storage[field_name] ~= nil then
          return data_storage[field_name]
        end

        local current_class = class_table
        while current_class do

            local class_method = rawget(current_class, field_name)
            if class_method ~= nil then
                return class_method
            end
            
            local simple_fields = rawget(current_class, "__simple_fields__")
            if simple_fields and simple_fields[field_name] ~= nil then
                return simple_fields[field_name]
            end
            
            current_class = rawget(current_class, "__base_class") and 
                          rawget(current_class, "__base_class").__class_table
        end
        
        -- Field not found.
        return nil
    end
end

--[[
Pre-computes and caches metadata for a class when it's first defined.
This avoids doing expensive lookups every time an instance is created or a field is accessed.

@param class_table (table) The class definition table to process.
]]
function precompute_class_metadata(class_table)
    local class_name = class_table.__name

    -- If the metatable for this class is already cached, we're done.
    if metatable_cache[class_name] then
        return
    end
    
    -- Create and cache the metatable.
    metatable_cache[class_name] = {
        __index = create_validating_index(class_table),
        __newindex = create_validating_newindex(class_table),
        __class_table = class_table,
        __tostring = function(instance)
            return string.format("<%s: %p>", class_name, instance)
        end,
        __eq = function(a, b)
            return rawequal(a, b)
        end
    }
end

--[[
Retrieves the cached metatable for a given class. If it doesn't exist,
it triggers the pre-computation step.

@param class_table (table) The class definition.
@return (table) The cached metatable.
]]
local function get_cached_metatable(class_table)
    local class_name = class_table.__name
    if not metatable_cache[class_name] then
        precompute_class_metadata(class_table)
    end
    return metatable_cache[class_name]
end

--[[
    @param class_table (table) The class definition.
    @param init_values_from_user (table) [Optional] A table of initial values for fields.
    @return (table) The new Caelum instance.
]]
local function instance_constructor(class_table, init_values_from_user) 
    
    local instance = {}
    
    rawset(instance, "__is_constructing", true)

    rawset(instance, "__data_storage__", {})
    setmetatable(instance, get_cached_metatable(class_table))

    local is_table_init = type(init_values_from_user) == "table"

    local fields = rawget(class_table, "__fields__")
    if fields then
        for field_name, field_meta in pairs(fields) do
            if is_table_init and init_values_from_user[field_name] ~= nil then
                instance[field_name] = init_values_from_user[field_name]
            else
                local field_type = field_meta.__type
                if (field_type == "struct" or field_type == "class") then
                    local constructor = field_meta.__type_table
                    local default_value = deep_copy(field_meta.__default_value)
                    instance[field_name] = safe_construct(constructor, default_value, field_type)
                elseif field_type == "array" then
                    local initial_array_values = deep_copy(field_meta.__default_value) or {}
                    local element_type_info = field_meta.__type_table
                    local element_type_name = field_meta.__type_name
                    instance[field_name] = create_array_proxy(initial_array_values, element_type_info, element_type_name, field_meta, instance, field_name)
                elseif field_type == "map" then
                    local initial_map_values = deep_copy(field_meta.__default_value) or {}
                    instance[field_name] = create_map_proxy(
                        initial_map_values,
                        field_meta.__key_type_table,
                        field_meta.__key_type_name,
                        field_meta.__value_type_table,
                        field_meta.__value_type_name,
                        field_meta,
                        instance,
                        field_name
                    )
                else
                    instance[field_name] = deep_copy(field_meta.__default_value)
                end
            end
        end
    end

    local simple_fields = rawget(class_table, "__simple_fields__")
    if simple_fields then
        for k, v in pairs(simple_fields) do
            if instance[k] == nil then 
                instance[k] = v
            end
        end
    end

    local current_class = class_table
    while current_class do
        local init_func = rawget(current_class, "__init")
        if init_func and type(init_func) == "function" then
            init_func(instance, init_values_from_user)
        end
        current_class = rawget(current_class, "__base_class") and rawget(current_class, "__base_class").__class_table
    end

    local validate_func = rawget(class_table, "__validate")
    if validate_func and type(validate_func) == "function" then
        validate_func(instance)
    end

    rawset(instance, "__is_constructing", nil)

    return instance
end

--[[
The base factory for all field types.
It creates a table holding the field's metadata and provides chainable
methods to configure it (e.g., `.title()`, `.min()`, `.validator()`).

@param field_type (string) The base type of the field (e.g., "int", "string", "array").
@param default_value (*) The default value for this field.
@return (table) A field definition table.
]]
local function base_field(field_type, default_value)
    local field = {
        __type = field_type,
        __default_value = default_value,
        __is_caelum_field = true
    }
    
    function field.title(val) field.field_title = val; return field end
    function field.desc(val) field.description = val; return field end
    function field.min(val) field.minval = val; return field end
    function field.max(val) field.maxval = val; return field end
    function field.range(min_val, max_val) field.minval = min_val; field.maxval = max_val; return field end
    function field.required() field.is_required = true; return field end
    function field.readonly() field.is_readonly = true; return field end
    function field.hidden() field.is_hidden = true; return field end
    function field.validator(fn) field.validate_fn = fn; return field end
    function field.nullable() field.is_nullable = true; return field end
    function field.category(category) field.categ = category; return field end
    function field.on_change(event_to_file) field.on_field_change = event_to_file; return field end 
    
    return setmetatable(field, {
        __call = function(tbl, props)
            for k, v in pairs(props) do
                rawset(tbl, k, v)
            end
            return tbl
        end
    })
end

--[[
Helper function to determine if a value exists in a list.
@param list (table) The list to search in.
@param val (*) The value to find.
@return (boolean) True if the value is in the list.
]]
local function tbl_contains(list, val)
    for _, v in ipairs(list) do
        if v == val then return true end
    end
    return false
end

local function precompute_field_metadata(class_table)
    local computed_fields = {}
    local fields = class_table.__fields__
    
    for field_name, field_meta in pairs(fields) do
        computed_fields[field_name] = {
            type = field_meta.__type,
            default_value = field_meta.__default_value,
            is_struct = field_meta.__type == "struct",
            is_class = field_meta.__type == "class",
            is_array = field_meta.__type == "array",
            constructor = field_meta.__type_table,
            validator = field_meta.validate_fn
        }
    end
    
    class_table.__computed_fields__ = computed_fields
end

--[[
Processes the fields definition table provided by the user when creating a class or struct.
It separates Caelum-defined fields from simple Lua fields/methods and stores them
in the appropriate internal tables (`__fields__` or `__simple_fields__`).

@param name (string) The name of the class being defined.
@param class_table (table) The class definition table to populate.
@param fields_definition (table) The user-provided table of fields.
]]
local function process_fields(name, class_table, fields_definition)
    if type(fields_definition) ~= "table" then return end

    for field_name, field_value in pairs(fields_definition) do
        if type(field_value) == "table" and field_value.__is_caelum_field then
            class_table.__fields__[field_name] = field_value
            field_value.__field_name_for_validation = field_name
            if not field_value.__type_name then
                field_value.__type_name = field_value.__type
            end
            
        elseif field_name ~= "__init" and field_name ~= "__validate" and not array_handlers[field_name] then
            class_table[field_name] = field_value
        end
    end
end

function Caelum.export_to_global(name, constructor)
    _G[name] = constructor
    return constructor
end

function Caelum.on_field_changed(instance, field_name, callback)
    local callbacks = rawget(instance, "__field_callbacks__") or {}
    callbacks[field_name] = callbacks[field_name] or {}
    table.insert(callbacks[field_name], callback)
    rawset(instance, "__field_callbacks__", callbacks)
end

function Caelum.field(type_definition, default_value)
    if type(type_definition) == "string" then
        local constructor = Caelum[type_definition]
        if type(constructor) == "function" then
            local test_field = safe_construct(constructor)
            if test_field and test_field.__is_caelum_field then
                return safe_construct(constructor, default_value)
            end
        end

        error("Caelum.field: Unsupported primitive type or unregistered class/struct name: '" .. tostring(type_definition) .. "'")
        
    elseif type(type_definition) == "table" then
        local caelum_type = type_definition.__caelum_type

        if caelum_type == "primitive" then
            local type_name = type_definition.__type_name
            local constructor = Caelum[type_name]
            if type(constructor) == "function" then
                return safe_construct(constructor, default_value)
            end

        elseif caelum_type == "struct" then
            return Caelum.struct_field(type_definition, default_value)

        elseif caelum_type == "class" then
            return Caelum.class_field(type_definition, default_value)

        elseif type_definition.values and type_definition.name then
            return Caelum.enum_field(type_definition, default_value or type_definition.default)
        end
    end

    error("Caelum.field: Invalid type passed. Expected a primitive name (e.g., 'string'), a primitive type (e.g., Caelum.String), or a Caelum class/struct/enum definition.")
end

--[[
Creates an Enum definition.

@param name (string) The global name for this enum.
@param values (table) An array of string or number values for the enum.
@param config (table) [Optional] Configuration, e.g., `{ default = "value" }`.
@return (table) The enum definition table.
]]
function Caelum.enum(name, values, config)
    config = config or {}
    local enum_def = {
        name = name,
        values = values,
        default = config.default or values[1],
        description = config.description or "",
        is_valid = function(value)
            for _, v in ipairs(values) do
                if v == value then return true end
            end
            return false
        end,
        get_index = function(value)
            for i, v in ipairs(values) do
                if v == value then return i end
            end
            return nil
        end,
        get_next = function(value)
            local idx = Caelum.Enums[name].get_index(value)
            if idx and idx < #values then
                return values[idx + 1]
            end
            return values[1]
        end
    }
    
    -- Register the enum and make it globally available.
    Caelum.Enums[name] = enum_def
    _G[name] = enum_def
    return enum_def
end

--[[
Defines a new Struct type.

Usage:
MyVector = Caelum.struct "MyVector" {
    x = Caelum.float(),
    y = Caelum.float(),
}
local vec = MyVector.new({ x = 10, y = 20 })

@param name (string) The name of the struct.
@return (function) A function that takes the fields definition table.
]]
function Caelum.struct(name)
    return function(fields_definition)
        local class_table = {
            __name = name,
            __fields__ = {},
            __caelum_class_table_type = "struct",
            __is_caelum_type = true
        }

        process_fields(name, class_table, fields_definition)

        if type(fields_definition) == "table" and fields_definition.__init then
            class_table.__init = fields_definition.__init
        end
        
        local constructor = function(self, init_values)
            return instance_constructor(class_table, init_values)
        end

        local public_constructor_table = {
            new = constructor,
            __type_name = name,
            __caelum_type = "struct",
            __class_table = class_table
        }
        
        if not fields_definition.__export_global or (fields_definition.__export_global and fields_definition.__export_global == true) then
            return register_type_global(name, public_constructor_table)
        elseif not fields_definition.__export_global and fields_definition.__export_global == false then
            return register_type(name, public_constructor_table)
        end
    end
end

--[[
Defines a new Class type.

Usage:
MyCharacter = Caelum.class "MyCharacter" {
    name = Caelum.string "Player",
    health = Caelum.int(100),
    
    take_damage = function(self, amount)
        self.health = self.health - amount
    end
}
local char = MyCharacter.new()
char:take_damage(10)

@param name (string) The name of the class.
@param base_class (table) [Optional] The base class to inherit from.
@return (function) A function that takes the fields definition table.
]]
function Caelum.class(name, base_class)
    return function(fields_definition)
        local class_table = {
            __name = name,
            __fields__ = {},
            __simple_fields__ = {},
            __caelum_class_table_type = "class", -- Marker
            __is_caelum_type = true,
            __base_class = base_class
        }

        if base_class then

            if base_class.__is_caelum_type ~= true then 
                error("Base class given is not a Caelum Class")
            end

            setmetatable(class_table, { __index = base_class.__class_table })

            --class_table.super = base_class.__init or function(self, init_values) end
            
            if base_class.__class_table.__init then
                class_table.super = function(self, init_values)
                    base_class.__class_table.__init(self, init_values)
                end
            else
                class_table.super = function(self, init_values) end
            end

            for k, v in pairs(base_class.__class_table.__fields__) do
                class_table.__fields__[k] = deep_copy(v)
            end

            -- Copy simple fields (methods and non-Caelum fields) from base class
            for k, v in pairs(base_class.__class_table.__simple_fields__ or {}) do
                if not class_table.__simple_fields__[k] then
                    class_table.__simple_fields__[k] = deep_copy(v)
                end
            end

            -- Copy methods from base class
            for k, v in pairs(base_class.__class_table) do
                if not class_table[k] and type(v) == "function" and 
                   k ~= "__index" and k ~= "__newindex" and 
                   k ~= "__fields__" and k ~= "__simple_fields__" then
                    class_table[k] = v
                end
            end
        end

        process_fields(name, class_table, fields_definition)

        rawset(class_table, "instanceof", function(self, Class)
            return Caelum.instanceof(self, Class)
        end)


        if type(fields_definition) == "table" then
            if fields_definition.__init then class_table.__init = fields_definition.__init end
            if fields_definition.__validate then class_table.__validate = fields_definition.__validate end
        end

        local constructor = function(self, init_values_from_user) 
            return instance_constructor(class_table, init_values_from_user)
        end
        
        local public_constructor_table = {
            new = constructor,
            __type_name = name,
            __caelum_type = "class",
            __class_table = class_table
        }
        
        setmetatable(public_constructor_table, {__index = class_table})
        
        if not fields_definition.__export_global or (fields_definition.__export_global and fields_definition.__export_global == true) then
            return register_type_global(name, public_constructor_table)
        elseif not fields_definition.__export_global and fields_definition.__export_global == false then
            return register_type(name, public_constructor_table)
        end
    end
end


--[[ Creates a float field definition. ]]
function Caelum.float(default_value)
    return base_field("float", default_value or 0.0)
end

--[[ Creates an integer field definition. ]]
function Caelum.int(default_value)
    return base_field("int", default_value or 0)
end

--[[ Creates a boolean field definition. ]]
function Caelum.bool(default_value)
    return base_field("bool", default_value or false)
end

--[[ Creates a string field definition. ]]
function Caelum.string(default_value)
    return base_field("string", default_value or "")
end


function Caelum.reference(default_value)
    local field = base_field("reference", default_value)
    return setmetatable(field, {
        __call = function(tbl, props)
            for k, v in pairs(props) do
                rawset(tbl, k, v)
            end
            return tbl
        end
    })
end

--[[ Creates a field for an enum type. ]]
function Caelum.enum_field(enum_def, default_value)
    local field
    if type(enum_def) == "string" then
        local registered_enum = Caelum.Enums[enum_def]
        if not registered_enum then error("Enum not found: " .. enum_def) end
        field = base_field("enum", default_value or registered_enum.default)
        field.enum_values = registered_enum.values
        field.__type_name = enum_def
    elseif type(enum_def) == "table" and enum_def.values then
        field = base_field("enum", default_value or enum_def.default)
        field.enum_values = enum_def.values
        field.__type_name = enum_def.name
    else
        error("Invalid enum definition for field.")
    end
    return field
end

--[[ Creates a field for a nested struct. ]]
function Caelum.struct_field(struct_constructor, default_value)
    local field = base_field("struct", default_value)
    field.__type_table = struct_constructor
    field.__type_name = struct_constructor.__type_name
    return field
end

--[[ Creates a field for a nested class. ]]
function Caelum.class_field(class_constructor, default_value)
    local field = base_field("class", default_value)
    field.__type_table = class_constructor
    field.__type_name = class_constructor.__type_name
    return field
end

--[[ Creates a field for an array of a specific type. ]]
function Caelum.array(element_type, default_values)
    local field = base_field("array", default_values or {})
    
    if type(element_type) == "string" then
        local primitive_info = Primitives[element_type]
        if primitive_info then
            field.__type_name = element_type 
            field.__type_table = nil
        else
            local registered_type = Caelum._type_registry[element_type] or _G[element_type]
            if registered_type then
                field.__type_name = registered_type.__type_name
                field.__type_table = registered_type
            else
                error("Type not found for array element: " .. element_type)
            end
        end
    elseif type(element_type) == "table" and element_type.__caelum_type then
        field.__type_name = element_type.__type_name
        field.__type_table = element_type
    else
        error("Invalid element type for array. Must be a primitive name or a Caelum type.")
    end
    
    return field
end

function Caelum.Array(element_type, initial_values)
    local element_type_info = {
        name = element_type.__type_name or tostring(element_type),
        constructor = element_type
    }

    local proxy = create_array_proxy(
        initial_values or {},
        element_type_info.constructor,
        element_type_info.name
    )

    return proxy
end


--[[ Creates a field for a map of a specific key and value type. ]]
function Caelum.map(key_type, value_type, default_values)
    local field = base_field("map", default_values or {})

    local function resolve_type_info(type_def, type_name_for_error)
        local info = { name = "unknown", constructor = nil }
        if type(type_def) == "string" then
            if Primitives[type_def] then
                info.name = type_def
            else
                local registered_type = Caelum._type_registry[type_def] or _G[type_def]
                if registered_type then
                    info.name = registered_type.__type_name
                    info.constructor = registered_type
                else
                    error("Type not found for map " .. type_name_for_error .. ": " .. type_def)
                end
            end
        elseif type(type_def) == "table" and type_def.__caelum_type then
            info.name = type_def.__type_name
            info.constructor = type_def
        else
            error("Invalid type for map " .. type_name_for_error .. ". Must be a primitive name or a Caelum type.")
        end
        return info
    end

    local key_type_info = resolve_type_info(key_type, "key")
    local value_type_info = resolve_type_info(value_type, "value")

    field.__key_type_name = key_type_info.name
    field.__key_type_table = key_type_info.constructor
    field.__value_type_name = value_type_info.name
    field.__value_type_table = value_type_info.constructor
    field.__type_name = string.format("map<%s, %s>", key_type_info.name, value_type_info.name)

    return field
end

function Caelum.Map(key_type, value_type, initial_values)
    local key_type_info = {
        name = key_type.__type_name or tostring(key_type),
        constructor = key_type
    }
    local value_type_info = {
        name = value_type.__type_name or tostring(value_type),
        constructor = value_type
    }

    local proxy = create_map_proxy(
        initial_values or {},
        key_type_info.constructor,
        key_type_info.name,
        value_type_info.constructor,
        value_type_info.name
    )

    return proxy
end


--------------------------------------------------------------------------------
-- REFLECTION AND UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- A cache for field metadata to speed up repeated lookups.
local field_info_cache = setmetatable({}, { __mode = "k" })

--[[
Gets detailed information about a specific field of a Caelum instance.

@param instance (table) The Caelum instance.
@param field_name (string) The name of the field to inspect.
@return (table|nil) A table containing metadata like title, description, type, min/max values, etc.
]]
function Caelum.get_field_info(instance, field_name)
    if type(instance) ~= "table" then
        error("get_field_info expects a table instance, got " .. type(instance))
    end

    local class_table = rawget(getmetatable(instance) or {}, "__class_table")
    if not class_table then return nil end

    local cache_key = class_table.__name .. ":" .. field_name
    if field_info_cache[cache_key] then
        return field_info_cache[cache_key]
    end

    local field_meta = (rawget(class_table, "__fields__") or {})[field_name]
    if not field_meta then return nil end

    local info = {}
    info.name = field_name
    info.title = field_meta.field_title or field_name
    info.description = field_meta.description or ""
    info.type = field_meta.__type or "unknown"
    info.subType = field_meta.__type_name or ""
    info.category = field_meta.categ or "General"
    info.hasDefaultValue = field_meta.__default_value ~= nil
    info.defaultValue = field_meta.__default_value
    info.min = field_meta.minval
    info.max = field_meta.maxval
    info.enumValues = field_meta.enum_values or {}
    info.hidden = field_meta.is_hidden or false
    info.readonly = field_meta.is_readonly or false
    
    field_info_cache[cache_key] = info
    return info
end

--[[
Gets the value of a field from an instance.

@param instance (table) The Caelum instance.
@param field_name (string) The name of the field.
@return (*) The value of the field.
]]
function Caelum.get_field_value(instance, field_name)
    return instance[field_name]
end

--[[
Sets the value of a field on an instance.
This is a safe way to set a value, as it will trigger the `__newindex`
metamethod which handles all validation.

@param instance (table) The Caelum instance.
@param field_name (string) The name of the field.
@param value (*) The new value to set.
]]
function Caelum.set_field_value(instance, field_name, value)
    instance[field_name] = value
end

function Caelum.set_field_change_callback(class_table, callback)
    class_table.__on_field_changed__ = callback
end

function Caelum.debug_instance_data(instance)
    local data_storage = rawget(instance, "__data_storage__")
    print("=== Instance Data Storage ===")
    if data_storage then
        for k, v in pairs(data_storage) do
            print(k, "=", v)
        end
    else
        print("No data storage found")
    end
    print("=============================")
end

function Caelum.call_method(instance, method_name, ...)
    local mt = getmetatable(instance)
    if mt and mt.__index then
        local method = mt.__index[method_name]
        if type(method) == "function" then
            return { pcall(method, instance, ...) }
        end
    end
    error("Method '" .. method_name .. "' not found or not a function for instance of type " .. Caelum.get_name(instance))
end

--[[
Gets information for all defined fields of a Caelum instance.

@param instance (table) The Caelum instance.
@return (table) A map where keys are field names and values are field info tables.
]]
function Caelum.get_all_fields(instance)
    local fields_info = {}
    local class_table = rawget(getmetatable(instance) or {}, "__class_table")
    if class_table then
        local fields_data = rawget(class_table, "__fields__")
        if fields_data then
            for field_name, _ in pairs(fields_data) do
                fields_info[field_name] = Caelum.get_field_info(instance, field_name)
            end
        end
    end
    return fields_info 
end

--[[
Gets a list of unique category names used by the fields of an instance.

@param instance (table) The Caelum instance.
@return (table) A list of category name strings.
]]
function Caelum.get_all_categories(instance)
    local categories = {}
    local categories_set = {}
    local allFields = Caelum.get_all_fields(instance)
    for _, info in pairs(allFields) do
        categories_set[info.category] = true
    end

    for cat_name, _ in pairs(categories_set) do
        table.insert(categories, cat_name)
    end
    table.sort(categories) -- Sort for consistent order.
    return categories
end

--[[
Checks if the given instance is an instance of a Caelum Class
@param instance (table) The instance to check
@param Class (table|string) The supposed Class of the instance
@return (boolean)  
]]
function Caelum.instanceof(instance, Class)
    if type(instance) ~= "table" then return false end
    local instance_mt = getmetatable(instance)
    if not instance_mt then return false end

    local instance_class_table = rawget(instance_mt, "__class_table")
    if not instance_class_table then return false end

    if type(Class) == "string" then
        Class = Caelum._type_registry[Class] or _G[Class]
        if not Class then return false end
    end
    
    if type(Class) ~= "table" or not Class.__is_caelum_type or not Class.__class_table then
        return false
    end
    
    local target_class_table = Class.__class_table
    
    local current_class = instance_class_table
    
    while current_class do
        if current_class == target_class_table then
            return true
        end
        
        local base_class = rawget(current_class, "__base_class")
        current_class = base_class and base_class.__class_table
    end
    
    return false
end

--[[
Checks if the given class is a subclass of another Caelum Class
@param instance (table) The class to check
@param Class (table|string) The base Class
@return (boolean)  
]]
function Caelum.issubclass(derived_class, base_class_or_name)
    if type(derived_class) ~= "table" or not derived_class.__is_caelum_type or not derived_class.__caelum_class_table_type == "class" then
        return false
    end

    local target_base_class_table

    if type(base_class_or_name) == "string" then
        target_base_class_table = Caelum._type_registry[base_class_or_name] or _G[base_class_or_name]
        if not target_base_class_table then
            return false
        end
    else
        target_base_class_table = base_class_or_name
    end

    if type(target_base_class_table) ~= "table" or not target_base_class_table.__is_caelum_type or not target_base_class_table.__caelum_class_table_type == "class" then
        return false
    end
    
    local current_class = derived_class
    
    while current_class do
        if current_class == target_base_class_table then
            return true
        end
        local base_class = rawget(rawget(current_class, "__class_table"), "__base_class")
        
        current_class = base_class
    end
    
    return false
end

--[[
Gets the Caelum type of an instance ("struct", "class", or "unknown").

@param instance (table) The object to inspect.
@return (string) The Caelum type name.
]]
function Caelum.get_type(instance)
    if type(instance) ~= "table" then return "unknown" end
    local class_table = rawget(getmetatable(instance) or {}, "__class_table")
    return class_table and class_table.__caelum_class_table_type or "unknown"
end

--[[
Gets the specific name of a Caelum instance (e.g., "MyVector", "Player").

@param instance (table) The object to inspect.
@return (string) The instance's defined name, or "Unknown".
]]
function Caelum.get_name(instance)
    if type(instance) ~= "table" then return "Unknown" end
    local class_table = rawget(getmetatable(instance) or {}, "__class_table")
    return class_table and class_table.__name or "Unknown"
end


-- TODO: needs to be revised, this was an old implementation for the cpp api, now it needs to be 
--       made consistent with the rest of the framework
function Caelum.create_instance(typeName, init_values)
    local global_type = _G[typeName]
    if global_type and global_type.new then
        local instance = safe_construct(global_type.new, init_values, typeName)
        if getmetatable(instance) == nil then
            setmetatable(instance, { __index = global_type })
        end
        return instance
    end
    error("Type not found: " .. typeName)
end

--------------------------------------------------------------------------------
-- Serialization / Deserialization 
--------------------------------------------------------------------------------

--[[
Serialize an instance of a Caelum type or a table in a pure lua-table. 
It handles nested types, array, maps and cycle-refs.

@param instance (*) The object to serialize.
@return (table) Pure lua Table representation of the instance.
]]
function Caelum.serialize(instance)
    local seen = {}

    local function serialize_recursive(value)
        if type(value) ~= "table" then
            return value
        end

        if seen[value] then
            return { __is_cycle = true, ref = tostring(value) }
        end
        seen[value] = true

        local result = {}
        
        if rawget(value, "__array_data__") then
            local raw_array = rawget(value, "__array_data__")
            for i = 1, #raw_array do
                table.insert(result, serialize_recursive(raw_array[i]))
            end
            
        elseif rawget(value, "__map_data__") then
            local raw_map = rawget(value, "__map_data__")
            for k, v in pairs(raw_map) do
                result[serialize_recursive(k)] = serialize_recursive(v)
            end

        elseif Caelum.get_name(value) ~= "Unknown" then
            result.__caelum_type_name = Caelum.get_name(value)
            result.data = {}
            
            local fields = Caelum.get_all_fields(value)
            for field_name, _ in pairs(fields) do
                result.data[field_name] = serialize_recursive(value[field_name])
            end
            
        else
            for k, v in pairs(value) do
                result[serialize_recursive(k)] = serialize_recursive(v)
            end
        end
        
        seen[value] = nil
        return result
    end

    return serialize_recursive(instance)
end

--[[
Deserialize a pure lua table into a Caelum instance.
Reconstruct the object through the field metadata.

@param data (table) The table to deserialize.
@return (*) The constructed Caelum instance.
@error If the type is not a Caelum Type.
]]
function Caelum.deserialize(data)

    local function deserialize_recursive(sub_data)
        if type(sub_data) ~= "table" then
            return sub_data
        end
        
        if sub_data.__caelum_type_name then
            local type_name = sub_data.__caelum_type_name
            local constructor = Caelum._type_registry[type_name]

            if not constructor or not constructor.new then
                error("Deserialization failed: Type '" .. type_name .. "' is not registered or has no .new() method.")
            end

            local init_values = {}
            if sub_data.data then
                for k, v in pairs(sub_data.data) do
                    init_values[k] = deserialize_recursive(v)
                end
            end
            
            return constructor.new(init_values)
        else
            local result = {}
            local is_array_like = true
            local max_index = 0
            for k, _ in pairs(sub_data) do
                if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                    is_array_like = false
                    break
                end
                max_index = math.max(max_index, k)
            end
            if #sub_data ~= max_index then is_array_like = false end

            if is_array_like then
                for i = 1, #sub_data do
                    table.insert(result, deserialize_recursive(sub_data[i]))
                end
            else
                 for k, v in pairs(sub_data) do
                    result[deserialize_recursive(k)] = deserialize_recursive(v)
                end
            end
            return result
        end
    end

    return deserialize_recursive(data)
end

--------------------------------------------------------------------------------
-- Language Additions 
--------------------------------------------------------------------------------

-- found in the forum https://devforum.roblox.com/t/switch-case-in-lua/1758606/2 @Shoop goldenstein64
function switch(value)
    return function(cases)
        local case = cases[value] or cases.default
        if case then
            return case(value)
        else
            error(string.format("Unhandled case (%s)", value), 2)
        end
    end
end

Caelum.Error = Caelum.class("Error"){
    msg = Caelum.string("Unknown message").nullable(),
    stack_trace_string = Caelum.string("").nullable(),

    __init = function(self, init_values) 
        if init_values and init_values[1] then
            self.msg = init_values[1]
        elseif init_values and init_values.msg then 
            self.msg = init_values.msg
        end
    end,

    __tostring = function(self)
        return self:what()
    end,

    what = function(self)
        return string.format("ERROR: %s", self.msg)
    end,

    stack_trace = function(self)
        return self.stack_trace_string
    end
}

local try_catch_stack = {}

-- Function to throw an error 
function throw(err)
    local stack = debug.traceback("", 2)
    if #try_catch_stack > 0 then
        if type(err) ~= "table" or not debug.getmetatable(err) then
            err = Caelum.Error:new({msg = tostring(err), stack_trace_string = stack})
        end
        err.stack_trace_string = stack
        error({error = err, is_caelum_error = true})
    else
        if type(err) == "table" and getmetatable(err) and getmetatable(err).__class_table then
            error(err:what().."\n"..stack, 2)
        else
            error(tostring(err).."\n"..stack, 2)
        end
    end
end

-- Try-Catch-Finally block chain

local function find_handler(catches, error_obj)
    if not error_obj then return nil end

    if type(error_obj) == "string" then
        return nil
    end

    local error_mt = debug.getmetatable(error_obj)
    local error_type_name = error_mt.__class_table.__name
    
    local first_superclass_catch  = nil

    for _, catch in ipairs(catches) do
        if catch.exact_type and catch.exact_type == error_type_name then
            return catch
        end
        if catch.type and error_obj:instanceof(catch.type) then
            if not first_superclass_catch  then
                first_superclass_catch  = catch
            end
        end
    end

    if first_superclass_catch  then 
        return first_superclass_catch 
    end

    return nil
end

function try(try_func)
    local handler = {
        _error = nil,
        _catches = {},
        _finally = nil,
        _generic_catch = nil,
        _parent_handler = try_catch_stack[#try_catch_stack] or nil,
        _executed = false,
        _is_nested = #try_catch_stack > 0,
        _in_catch_block = false
    }

    table.insert(try_catch_stack, handler)

    local success, err = xpcall(try_func, debug.traceback)

    table.remove(try_catch_stack)

    if not success then
        if type(err) == "table" and err.is_caelum_error then
            handler._error = err.error
        else
            handler._error = Caelum.Error:new({msg = tostring(err), stack_trace_string = debug.traceback("", 2)})
        end
    end

    function handler:catch(error_type, fn)

        if type(error_type) == "function" and not fn then
            if self._generic_catch then
                error("Only one generic catch block allowed")
            end
            self._generic_catch = { fn = error_type }
            return self
        end

        if type(error_type) ~= "table" or not error_type.__type_name then
            error("Catch type must be a Caelum class")
        end

        if not Caelum.issubclass(error_type, Caelum.Error) then
            error("Error type must be of type Caelum.Error or a derived class")
        end

        table.insert(self._catches, {
            type = error_type,
            fn = fn,
            exact_type = error_type.__type_name
        })

        return self
    end

    function handler:finally(fn)
        self._finally = fn
        if not handler._executed then
            handler:_execute()
        end
        return self
    end

    function handler:close()
        if not handler._executed then
            handler:_execute()
        end
        return self
    end

    function handler:_execute()

        if self._executed then return end
        self._executed = true

        if self._error then
            local catch = find_handler(self._catches, self._error) or
                         self._generic_catch
            if catch then

                self._in_catch_block = true
                local success, catch_err = pcall(function()
                    catch.fn(self._error)
                end)
                self._in_catch_block = false

                if not success then
                    if self._parent_handler and not self._parent_handler._executed then
                        self._parent_handler._error = Caelum.Error:new({msg = tostring(catch_err), stack_trace_string = debug.traceback("", 2)})
                        self._parent_handler:_execute()
                    else
                        error({error = Caelum.Error:new({msg = tostring(catch_err), stack_trace_string = debug.traceback("", 2)}), 
                            is_caelum_error = true})
                    end
                end

            else
                if self._is_nested and self._parent_handler and not self._in_catch_block then
                    error({error = self._error, is_caelum_error = true})
                else
                    
                    if type(self._error) == "table" and getmetatable(self._error) and getmetatable(self._error).__class_table then
                        error(self._error:what().."\n"..self._error:stack_trace(), 2)
                    else
                        error(tostring(self._error).."\n"..self._error:stack_trace(), 2)
                    end
                end
            end
        end
        if self._finally then
            local success, finally_err = pcall(self._finally)
            if not success and self._parent_handler and not self._parent_handler._executed then
                self._parent_handler._error = Caelum.Error:new({msg = tostring(finally_err), stack_trace_string = debug.traceback("", 2)})
                self._parent_handler:_execute()
            end
        end
    end

    return handler
end

return Caelum