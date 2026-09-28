-- Local test runner, so busted doesn't have to be installed (on Windows it needs a C compiler).
-- It understands the subset of busted the *.test.lua files use: describe / it / before_each / after_each /
-- pending and assert.are.equal / are.same / are_not.equal / is_true / is_false / is_nil / is_not_nil /
-- is_truthy / is_falsy / has_error / has_no.errors / matches / near. CI uses the real busted.
--
-- Usage, from the repo root:  lua test/busted.lua [file.test.lua ...]
-- With no arguments it finds every *.test.lua (except under tools/ and .git/).

local function listTests()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd = isWindows and 'dir /s /b *.test.lua 2>nul' or 'find . -name "*.test.lua"'
    local pipe = io.popen(cmd)
    local cwd = (io.popen(isWindows and "cd" or "pwd"):read("*l") or ""):gsub("[\\/]$", "")
    for line in pipe:lines() do
        local rel = line:gsub("^" .. cwd:gsub("%p", "%%%0"), ""):gsub("^[\\/]", ""):gsub("\\", "/"):gsub("^%./", "")
        if not rel:match("^tools/") and not rel:match("^%.git/") then files[#files + 1] = rel end
    end
    pipe:close()
    table.sort(files)
    return files
end

-- deep comparison (assert.are.same)
local function deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do if not deepEqual(v, b[k], seen) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function show(v)
    if type(v) == "string" then return ("%q"):format(v) end
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, val in pairs(v) do
        parts[#parts + 1] = tostring(k) .. "=" .. (type(val) == "table" and "{...}" or tostring(val))
        if #parts > 8 then parts[#parts + 1] = "..." break end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function fail(msg) error(msg, 3) end

local function makeAssert()
    local a = setmetatable({}, { __call = function(_, v, msg, ...)
        if not v then error(msg or "assertion failed!", 2) end
        return v, msg, ...
    end })
    local function equal(expected, actual, msg)
        if expected ~= actual then fail((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual)) end
    end
    local function same(expected, actual, msg)
        if not deepEqual(expected, actual) then fail((msg and (msg .. ": ") or "") .. "expected same as " .. show(expected) .. ", got " .. show(actual)) end
    end
    local function notEqual(expected, actual, msg)
        if expected == actual then fail((msg and (msg .. ": ") or "") .. "expected something other than " .. show(expected)) end
    end
    local function notSame(expected, actual, msg)
        if deepEqual(expected, actual) then fail((msg and (msg .. ": ") or "") .. "expected different from " .. show(expected)) end
    end
    local function isTrue(v, msg) if v ~= true then fail((msg or "expected true") .. ", got " .. show(v)) end end
    local function isFalse(v, msg) if v ~= false then fail((msg or "expected false") .. ", got " .. show(v)) end end
    local function isNil(v, msg) if v ~= nil then fail((msg or "expected nil") .. ", got " .. show(v)) end end
    local function notNil(v, msg) if v == nil then fail(msg or "expected a value, got nil") end end
    local function truthy(v, msg) if not v then fail((msg or "expected truthy") .. ", got " .. show(v)) end end
    local function falsy(v, msg) if v then fail((msg or "expected falsy") .. ", got " .. show(v)) end end
    local function hasError(f, msg) if pcall(f) then fail(msg or "expected an error") end end
    local function noErrors(f, msg)
        local ok, err = pcall(f)
        if not ok then fail((msg and (msg .. ": ") or "") .. "unexpected error: " .. tostring(err)) end
    end
    local function near(expected, actual, tolerance, msg)
        if type(actual) ~= "number" or math.abs(expected - actual) > tolerance then
            fail((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. " +/- " .. tolerance .. ", got " .. show(actual))
        end
    end
    local function matches(pattern, s, msg)
        if type(s) ~= "string" or not s:find(pattern) then fail((msg or "no match") .. ": " .. show(pattern) .. " in " .. show(s)) end
    end
    a.are = { equal = equal, equals = equal, same = same }
    a.is = { equal = equal, same = same, ["true"] = isTrue, ["false"] = isFalse, ["nil"] = isNil, truthy = truthy, falsy = falsy }
    a.are_not = { equal = notEqual, same = notSame }
    a.is_not = { equal = notEqual, same = notSame, ["nil"] = notNil }
    a.equal, a.equals, a.same = equal, equal, same
    a.is_true, a.is_false, a.is_nil, a.is_not_nil = isTrue, isFalse, isNil, notNil
    a.True, a.False = isTrue, isFalse
    a.is_truthy, a.is_falsy, a.truthy, a.falsy = truthy, falsy, truthy, falsy
    a.has_error, a.has_errors = hasError, hasError
    a.has_no = { errors = noErrors, error = noErrors }
    a.matches = matches
    a.near, a.is_near, a.are.near = near, near, near
    return a
end

local results = { passed = 0, failed = 0, pending = 0, errors = {} }

local function runFile(path)
    -- every file with its own globals (like busted's "insulate")
    local saved = {}
    for k, v in pairs(_G) do saved[k] = v end

    local root = { name = "", children = {}, before = {}, after = {} }
    local current = root
    _G.describe = function(name, fn)
        local block = { name = name, children = {}, before = {}, after = {}, parent = current }
        table.insert(current.children, block)
        local prev = current
        current = block
        fn()
        current = prev
    end
    _G.context = _G.describe
    _G.it = function(name, fn) table.insert(current.children, { name = name, test = fn, parent = current }) end
    _G.pending = function(name) table.insert(current.children, { name = name, pending = true, parent = current }) end
    _G.before_each = function(fn) table.insert(current.before, fn) end
    _G.after_each = function(fn) table.insert(current.after, fn) end
    _G.setup, _G.teardown = function(fn) fn() end, function() end
    _G.assert = makeAssert()

    -- like busted: the file runs in its own environment (it reads the globals, but what it assigns without
    -- _G. stays in the file); what it loads with dofile (setupTests.lua, the mocks) and the addon use the real
    -- globals
    local env = setmetatable({}, { __index = _G })
    local ok, err = pcall(function() return assert(loadfile(path, "t", env))() end)
    if not ok then
        results.failed = results.failed + 1
        table.insert(results.errors, path .. ": error al cargar: " .. tostring(err))
    else
        local function chain(block, key)
            local list = {}
            local b = block
            while b do
                table.insert(list, 1, b[key])
                b = b.parent
            end
            return list
        end
        local function fullName(node)
            local parts = {}
            local b = node
            while b do
                if b.name ~= "" then table.insert(parts, 1, b.name) end
                b = b.parent
            end
            return table.concat(parts, " > ")
        end
        local function run(block)
            for _, node in ipairs(block.children) do
                if node.pending then
                    results.pending = results.pending + 1
                elseif node.test then
                    local okTest, errTest = pcall(function()
                        for _, list in ipairs(chain(block, "before")) do for _, f in ipairs(list) do f() end end
                        node.test()
                    end)
                    local lists = chain(block, "after")
                    for i = #lists, 1, -1 do for _, f in ipairs(lists[i]) do pcall(f) end end
                    if okTest then
                        results.passed = results.passed + 1
                    else
                        results.failed = results.failed + 1
                        table.insert(results.errors, path .. ": " .. fullName(node) .. "\n    " .. tostring(errTest))
                    end
                else
                    run(node)
                end
            end
        end
        run(root)
    end

    for k in pairs(_G) do if saved[k] == nil then _G[k] = nil end end
    for k, v in pairs(saved) do _G[k] = v end
end

local files = { ... }
if #files == 0 then files = listTests() end
local realPrint = print
for _, f in ipairs(files) do
    local before = results.passed + results.failed
    runFile(f)
    realPrint(("%-55s %d tests"):format(f, results.passed + results.failed - before))
end
realPrint("")
for _, e in ipairs(results.errors) do realPrint("FAIL " .. e) end
realPrint(("%d passed, %d failed, %d pending"):format(results.passed, results.failed, results.pending))
os.exit(results.failed == 0 and 0 or 1)
