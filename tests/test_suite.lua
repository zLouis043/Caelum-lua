local TestFramework = {}

local config = {
    verbose = false,
    ci_mode = false,
    timeout = 30, -- seconds
    colors = {
        green = "\27[32m",
        red = "\27[31m",
        yellow = "\27[33m",
        blue = "\27[34m",
        reset = "\27[0m"
    }
}

-- Global Stats
local stats = {
    total = 0,
    passed = 0,
    failed = 0,
    skipped = 0,
    start_time = 0,
    results = {}
}

local function enableWindowsAnsi()
    local isWindows = package.config:sub(1,1) == '\\'
    if isWindows then
        os.execute("") 
    end
end

local function colorize(text, color)
    if config.ci_mode or os.getenv("CI") then
        return text
    end
    
    local isWindows = package.config:sub(1,1) == '\\'
    if isWindows then
        enableWindowsAnsi()
    end
    
    return (config.colors[color] or "") .. text .. config.colors.reset
end

local function getPrefix()
    local isWindows = package.config:sub(1,1) == '\\'
    
    if isWindows then
        return {
            INFO = colorize("INFO", "blue"),
            SUCCESS = colorize("OK", "green"),
            ERROR = colorize("ERR", "red"),
            WARNING = colorize("WARN", "yellow"),
            DEBUG = colorize("DBG", "blue")
        }
    else
        return {
            INFO = colorize("ℹ", "blue"),
            SUCCESS = colorize("✓", "green"),
            ERROR = colorize("✗", "red"),
            WARNING = colorize("⚠", "yellow"),
            DEBUG = colorize("🔍", "blue")
        }
    end
end


local function log(level, message)
    local prefix = getPrefix()
    
    if level == "DEBUG" and not config.verbose then
        return
    end
    
    print(string.format("[%s] %s", prefix[level] or level, message))
end

local function get_time()
    return os.clock()
end

local function assert_equal(actual, expected, message)
    message = message or string.format("Expected %s, got %s", tostring(expected), tostring(actual))
    if actual ~= expected then
        error(message, 2)
    end
end

local function assert_not_equal(actual, expected, message)
    message = message or string.format("Expected %s to not equal %s", tostring(actual), tostring(expected))
    if actual == expected then
        error(message, 2)
    end
end

local function assert_true(value, message)
    message = message or string.format("Expected true, got %s", tostring(value))
    if not value then
        error(message, 2)
    end
end

local function assert_false(value, message)
    message = message or string.format("Expected false, got %s", tostring(value))
    if value then
        error(message, 2)
    end
end

local function assert_nil(value, message)
    message = message or string.format("Expected nil, got %s", tostring(value))
    if value ~= nil then
        error(message, 2)
    end
end

local function assert_not_nil(value, message)
    message = message or "Expected non-nil value"
    if value == nil then
        error(message, 2)
    end
end

local function assert_type(value, expected_type, message)
    local actual_type = type(value)
    message = message or string.format("Expected type %s, got %s", expected_type, actual_type)
    if actual_type ~= expected_type then
        error(message, 2)
    end
end

local function assert_contains(table_or_string, value, message)
    if type(table_or_string) == "table" then
        for _, v in pairs(table_or_string) do
            if v == value then return end
        end
        error(message or string.format("Table does not contain %s", tostring(value)), 2)
    elseif type(table_or_string) == "string" then
        if not string.find(table_or_string, value, 1, true) then
            error(message or string.format("String '%s' does not contain '%s'", table_or_string, value), 2)
        end
    else
        error("assert_contains expects table or string", 2)
    end
end

local function assert_throws(func, message)
    local success, err = pcall(func)
    if success then
        error(message or "Expected function to throw an error", 2)
    end
end

TestFramework.assert_equal = assert_equal
TestFramework.assert_not_equal = assert_not_equal
TestFramework.assert_true = assert_true
TestFramework.assert_false = assert_false
TestFramework.assert_nil = assert_nil
TestFramework.assert_not_nil = assert_not_nil
TestFramework.assert_type = assert_type
TestFramework.assert_contains = assert_contains
TestFramework.assert_throws = assert_throws

local function run_test(name, test_func, category)
    category = category or "unit"
    stats.total = stats.total + 1
    
    local start_time = get_time()
    local success, error_msg = pcall(test_func)
    local duration = get_time() - start_time
    
    local result = {
        name = name,
        category = category,
        success = success,
        error = error_msg,
        duration = duration
    }
    
    table.insert(stats.results, result)
    
    if success then
        stats.passed = stats.passed + 1
        log("SUCCESS", string.format("%s [%s] (%.3fs)", name, category, duration))
    else
        stats.failed = stats.failed + 1
        log("ERROR", string.format("%s [%s] FAILED: %s", name, category, error_msg))
    end
    
    return success
end

local test_suites = {
    unit = {},
    integration = {},
    performance = {}
}

function TestFramework.test(name, test_func, category)
    category = category or "unit"
    test_suites[category] = test_suites[category] or {}
    test_suites[category][name] = test_func
end

function TestFramework.unit_test(name, test_func)
    TestFramework.test(name, test_func, "unit")
end

function TestFramework.integration_test(name, test_func)
    TestFramework.test(name, test_func, "integration")
end

function TestFramework.performance_test(name, test_func)
    TestFramework.test(name, test_func, "performance")
end

local setup_funcs = {}
local teardown_funcs = {}

function TestFramework.setup(func)
    table.insert(setup_funcs, func)
end

function TestFramework.teardown(func)
    table.insert(teardown_funcs, func)
end

function TestFramework.run_suite(suite_name)
    local suite = test_suites[suite_name]
    if not suite then
        log("WARNING", "Test suite '" .. suite_name .. "' not found")
        return
    end
    
    log("INFO", "Running " .. suite_name .. " tests...")
    
    for test_name, test_func in pairs(suite) do
        for _, setup_func in ipairs(setup_funcs) do
            setup_func()
        end
        
        run_test(test_name, test_func, suite_name)
        
        for _, teardown_func in ipairs(teardown_funcs) do
            teardown_func()
        end
    end
end

function TestFramework.run_all()
    stats.start_time = get_time()
    
    for suite_name, _ in pairs(test_suites) do
        TestFramework.run_suite(suite_name)
    end
    
    TestFramework.print_summary()
end

function TestFramework.has_something_failed() 
    return stats.failed > 0
end

function TestFramework.mock(original_func)
    local mock = {
        calls = {},
        returns = nil,
        original = original_func
    }
    
    local function mock_func(...)
        local args = {...}
        table.insert(mock.calls, args)
        
        if mock.returns then
            return mock.returns
        end
        
        return original_func(...)
    end
    
    mock_func.set_return = function(value)
        mock.returns = value
        return mock_func
    end
    
    mock_func.get_calls = function()
        return mock.calls
    end
    
    mock_func.call_count = function()
        return #mock.calls
    end
    
    return mock_func
end

function TestFramework.print_summary()
    local total_time = get_time() - stats.start_time
    
    print("\n" .. string.rep("=", 50))
    print("TEST SUMMARY")
    print(string.rep("=", 50))
    
    print(string.format("Total tests: %d", stats.total))
    print(colorize(string.format("Passed: %d", stats.passed), "green"))
    print(colorize(string.format("Failed: %d", stats.failed), "red"))
    print(colorize(string.format("Skipped: %d", stats.skipped), "yellow"))
    print(string.format("Total time: %.3fs", total_time))
    
    if stats.failed > 0 then
        print(colorize("\nFAILED TESTS:", "red"))
        for _, result in ipairs(stats.results) do
            if not result.success then
                print(colorize(string.format("  - %s: %s", result.name, result.error), "red"))
            end
        end
    end

    local slow_tests = {}
    for _, result in ipairs(stats.results) do
        if result.duration > 1.0 then
            table.insert(slow_tests, result)
        end
    end
    
    if #slow_tests > 0 then
        print(colorize("\nSLOW TESTS (>1s):", "yellow"))
        table.sort(slow_tests, function(a, b) return a.duration > b.duration end)
        for _, result in ipairs(slow_tests) do
            print(colorize(string.format("  - %s: %.3fs", result.name, result.duration), "yellow"))
        end
    end
end

function TestFramework.parse_args(args)
    local suite_to_run = nil
    
    for _, arg in ipairs(args) do
        if arg == "--verbose" or arg == "-v" then
            config.verbose = true
        elseif arg == "--ci" then
            config.ci_mode = true
        elseif arg == "unit" or arg == "integration" or arg == "performance" then
            suite_to_run = arg
        elseif arg == "--help" or arg == "-h" then
            print("Usage: lua test_framework.lua [options] [suite]")
            print("Options:")
            print("  --verbose, -v    Verbose output")
            print("  --ci             CI mode (XML output)")
            print("  --help, -h       Show this help")
            print("Suites:")
            print("  unit             Run only unit tests")
            print("  integration      Run only integration tests")
            print("  performance      Run only performance tests")
            os.exit(0)
        end
    end
    
    return suite_to_run
end

return TestFramework