--
-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
    ["\\"] = "\\",
    ["\""] = "\"",
    ["\b"] = "b",
    ["\f"] = "f",
    ["\n"] = "n",
    ["\r"] = "r",
    ["\t"] = "t",
}

local escape_char_map_inv = { ["/"] = "/" }
for k, v in pairs(escape_char_map) do
    escape_char_map_inv[v] = k
end


local function escape_char(c)
    return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end


local function encode_nil(val)
    return "null"
end


local function encode_table(val, stack)
    local res = {}
    stack = stack or {}

    -- Circular reference?
    if stack[val] then error("circular reference") end

    stack[val] = true

    if rawget(val, 1) ~= nil or next(val) == nil then
        -- Treat as array -- check keys are valid and it is not sparse
        local n = 0
        for k in pairs(val) do
            if type(k) ~= "number" then
                error("invalid table: mixed or invalid key types")
            end
            n = n + 1
        end
        if n ~= #val then
            error("invalid table: sparse array")
        end
        -- Encode
        for i, v in ipairs(val) do
            table.insert(res, encode(v, stack))
        end
        stack[val] = nil
        return "[" .. table.concat(res, ",") .. "]"
    else
        -- Treat as an object
        for k, v in pairs(val) do
            if type(k) ~= "string" then
                error("invalid table: mixed or invalid key types")
            end
            table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
        end
        stack[val] = nil
        return "{" .. table.concat(res, ",") .. "}"
    end
end


local function encode_string(val)
    return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
    -- Check for NaN, -inf and inf
    if val ~= val or val <= -math.huge or val >= math.huge then
        error("unexpected number value '" .. tostring(val) .. "'")
    end
    return string.format("%.14g", val)
end


local type_func_map = {
    ["nil"] = encode_nil,
    ["table"] = encode_table,
    ["string"] = encode_string,
    ["number"] = encode_number,
    ["boolean"] = tostring,
}


encode = function(val, stack)
    local t = type(val)
    local f = type_func_map[t]
    if f then
        return f(val, stack)
    end
    error("unexpected type '" .. t .. "'")
end


function json.encode(val)
    return (encode(val))
end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do
        res[select(i, ...)] = true
    end
    return res
end

local space_chars  = create_set(" ", "\t", "\r", "\n")
local delim_chars  = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals     = create_set("true", "false", "null")

local literal_map  = {
    ["true"] = true,
    ["false"] = false,
    ["null"] = nil,
}


local function next_char(str, idx, set, negate)
    for i = idx, #str do
        if set[str:sub(i, i)] ~= negate then
            return i
        end
    end
    return #str + 1
end


local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
        col_count = col_count + 1
        if str:sub(i, i) == "\n" then
            line_count = line_count + 1
            col_count = 1
        end
    end
    error(string.format("%s at line %d col %d", msg, line_count, col_count))
end


local function codepoint_to_utf8(n)
    -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
    local f = math.floor
    if n <= 0x7f then
        return string.char(n)
    elseif n <= 0x7ff then
        return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then
        return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
    elseif n <= 0x10ffff then
        return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
            f(n % 4096 / 64) + 128, n % 64 + 128)
    end
    error(string.format("invalid unicode codepoint '%x'", n))
end


local function parse_unicode_escape(s)
    local n1 = tonumber(s:sub(1, 4), 16)
    local n2 = tonumber(s:sub(7, 10), 16)
    -- Surrogate pair?
    if n2 then
        return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
        return codepoint_to_utf8(n1)
    end
end


local function parse_string(str, i)
    local res = ""
    local j = i + 1
    local k = j

    while j <= #str do
        local x = str:byte(j)

        if x < 32 then
            decode_error(str, j, "control character in string")
        elseif x == 92 then -- `\`: Escape
            res = res .. str:sub(k, j - 1)
            j = j + 1
            local c = str:sub(j, j)
            if c == "u" then
                local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                    or str:match("^%x%x%x%x", j + 1)
                    or decode_error(str, j - 1, "invalid unicode escape in string")
                res = res .. parse_unicode_escape(hex)
                j = j + #hex
            else
                if not escape_chars[c] then
                    decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
                end
                res = res .. escape_char_map_inv[c]
            end
            k = j + 1
        elseif x == 34 then -- `"`: End of string
            res = res .. str:sub(k, j - 1)
            return res, j + 1
        end

        j = j + 1
    end

    decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then
        decode_error(str, i, "invalid number '" .. s .. "'")
    end
    return n, x
end


local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
        decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
end


local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
        local x
        i = next_char(str, i, space_chars, true)
        -- Empty / end of array?
        if str:sub(i, i) == "]" then
            i = i + 1
            break
        end
        -- Read token
        x, i = parse(str, i)
        res[n] = x
        n = n + 1
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "]" then break end
        if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
end


local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
        local key, val
        i = next_char(str, i, space_chars, true)
        -- Empty / end of object?
        if str:sub(i, i) == "}" then
            i = i + 1
            break
        end
        -- Read key
        if str:sub(i, i) ~= '"' then
            decode_error(str, i, "expected string for key")
        end
        key, i = parse(str, i)
        -- Read ':' delimiter
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) ~= ":" then
            decode_error(str, i, "expected ':' after key")
        end
        i = next_char(str, i + 1, space_chars, true)
        -- Read value
        val, i = parse(str, i)
        -- Set
        res[key] = val
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "}" then break end
        if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
end


local char_func_map = {
    ['"'] = parse_string,
    ["0"] = parse_number,
    ["1"] = parse_number,
    ["2"] = parse_number,
    ["3"] = parse_number,
    ["4"] = parse_number,
    ["5"] = parse_number,
    ["6"] = parse_number,
    ["7"] = parse_number,
    ["8"] = parse_number,
    ["9"] = parse_number,
    ["-"] = parse_number,
    ["t"] = parse_literal,
    ["f"] = parse_literal,
    ["n"] = parse_literal,
    ["["] = parse_array,
    ["{"] = parse_object,
}


parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then
        return f(str, idx)
    end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json.decode(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then
        decode_error(str, idx, "trailing garbage")
    end
    return res
end

-----------------------------------------------------------------------------------
settings.add("carapace.enable", false, "Enable carapace argument auto-completion")
settings.add("carapace.exclude", "scoop;cmd", "Exclude commands from carapace completion")
settings.add("carapace.timeout", 5, "Terminate carapace process on Timeout")

local isfile = os.isfile
local isdir = os.isdir
local getalias = os.getalias
local sleep = os.sleep
local clock = os.clock
local run = io.popenyield or io.popen
local pathjoin = path.join
local string_explode = string.explode
local get_setting = settings.get
local parsecolor = settings.parsecolor
local getbasename = path.getbasename
local carapace_execution = "carapace.exe"
local carapace_generator = clink.generator(1)
local carapace_exclude = get_setting("carapace.exclude")
local carapace_co = nil
local co_status = coroutine.status
local co_yield = coroutine.yield
local co_resume = coroutine.resume
local command_exclude = string_explode(carapace_exclude, ";", "\"")

local function commands_exists(...)
    local args = { ... }
    local paths = string_explode(os.getenv("path"), ";")
    local pathexts = string_explode(os.getenv("pathext"), ";")
    if not paths or not pathexts or not args then return true end
    for i = 1, #paths do
        for j = 1, #pathexts do
            for k = 1, #args do
                if #args[k] > 0 and not isfile(pathjoin(paths[i], args[k] .. pathexts[j])) then break end
                return true
            end
        end
    end
    return false
end

local function carapace_run(cmd, timeout)
    carapace_co = coroutine.create(function()
        local f = run(cmd .. " 2>nul")
        if f then
            for l in f:lines() do
                if #l > 0 then co_yield(l) end
            end
            co_yield(true)
            f:close()
        else
            co_yield(false)
        end
    end)
    local result = ""
    local begin = clock()
    while true do
        local ok, r = co_resume(carapace_co)
        if not ok or r == false then return false, nil end
        if r == true then break end
        if r then
            begin = clock()
            result = result .. r
        else
            if co_status(carapace_co) == "dead" then
                break
            end
            if clock() - begin > timeout then
                os.execute("taskkill /f /im " .. carapace_execution .. ">nul 2>nul")
                return false, "Timeout"
            end
            sleep(0.01)
        end
    end
    carapace_co = nil
    return true, result
end

function carapace_generator:generate(line_state, match_builder)
    if not get_setting("carapace.enable") then return false end
    if carapace_exclude ~= get_setting("carapace.exclude") then
        carapace_exclude = get_setting("carapace.exclude")
        command_exclude = string_explode(carapace_exclude, ";", "\"")
    end
    if line_state:getwordcount() < 2 then return false end
    local command = line_state:getword(1):lower()
    local alias = getalias(command)
    local alias_command = ""
    local alias_args = ""
    if alias then
        local n = #alias
        while n > 0 and alias:byte(n) == 32 do
            n = n - 1
        end
        alias = alias:sub(1, n)
        if alias:sub(-2) == "$*" then
            alias = alias:sub(1, -3)
            local start_pos = 0
            local end_pos = 0
            local quote = 0
            for i = 1, #alias do
                local b = alias:byte(i)
                if b ~= 32 then
                    if start_pos == 0 then
                        start_pos = i
                        if b == 34 or b == 39 then
                            quote = t
                        end
                    else
                        if quote ~= 0 and b == quote then
                            end_pos = i
                            break
                        end
                    end
                elseif start_pos > 0 then
                    if quote == 0 or i == #alias then
                        end_pos = i - 1
                        break
                    end
                end
            end
            if start_pos > 0 and end_pos > 0 then
                alias_command = alias:sub(start_pos, end_pos)
                if end_pos < #alias then
                    alias_args = alias:sub(end_pos + 1)
                end
            end
        else
            return false
        end
    end
    local c = getbasename((#alias_command > 0) and alias_command or command)
    if c == "cd" then
        local lw = line_state:getendword()
        if lw == "/" then
            match_builder:setnosort()
            match_builder:addmatches({ "/d", "/D", "/?" })
            return true
        else
            match_builder:addmatches({ clink.dirmatches(lw) })
            return false
        end
    elseif c == "clink" or c == "clink_x64" then
        if line_state:getwordcount() == 4 and line_state:getword(2) == "set" and line_state:getword(3) == "carapace.exclude" then
            local m = carapace_exclude:sub(-1) == ";" and carapace_exclude:sub(1, -2) or carapace_exclude
            match_builder:addmatches({ {
                match = m,
                description = "Commands Excluded from Autocompletion",
                type = "word",
                suppressappend = true
            }, {
                match = m .. ";",
                description = "Add Commands to Autocompletion Exclusion List",
                type = "word",
                suppressappend = true
            }, {
                match = "clear",
                description = "Clear List",
                type = "arg"
            } })
            return true
        else
            return false
        end
    end
    if #c == 0 or not commands_exists(c, carapace_execution) then return false end
    for i = 1, #command_exclude do
        if c == command_exclude[i] then return false end
    end
    local line = line_state:getline()
    local pos = line_state:getcursor()
    local args = line:sub(#command + line_state:getcommandoffset() + 1, pos - 1)
    if #alias_args > 0 then args = alias_args .. " " .. args end
    local cmd = ""
    local line_pos = line:sub(pos - 1, pos - 1)
    if line_pos == " " then
        cmd = carapace_execution .. " " .. c .. " export . " .. args .. " \"\""
    else
        cmd = carapace_execution .. " " .. c .. " export . " .. args
    end
    if carapace_co and co_status(carapace_co) ~= "dead" then
        os.execute("taskkill /f /im " .. carapace_execution .. ">nul 2>nul")
        clink.popuplist("Error", { {
            value = "",
            display = "Error",
            description = "The coroutine is still running; attempting to terminate the process.",
        } })
        return true
    end
    local ok, result = carapace_run(cmd, 5)
    if not ok then
        if result == "Timeout" then
            local timeout = get_setting("carapace.timeout")
            if not timeout then timeout = 5 end
            ok, result = carapace_run(cmd, timeout)
            if not ok then
                if result == "Timeout" then
                    clink.popuplist("Error", { {
                        value = "",
                        display = "Timeout",
                        description = "Execution timed out, terminating the process.",
                    } })
                else
                    return false
                end
            end
        else
            return false
        end
    end
    if #result < 3 then return false end
    local success, data = pcall(json.decode, result)
    if not success or not data then return false end
    local messages = data.messages
    if messages and #messages > 0 then
        clink.popuplist("Error", { {
            value = "",
            display = "Error",
            description = messages[1],
        } })
        return true
    end
    local values = data.values
    if not values or #values == 0 then return false end
    local match = {}
    local matches = {}
    for i = 1, #values do
        local item = values[i]
        local value = item.value
        local display = item.display
        local description = item.description
        local tag = item.tag
        local style = item.style
        local nospace = data.nospace
        local tp = "word"
        if (line_pos == "=" and clink.getargmatcher(command)) or (line_pos ~= "=" and value:find("=")) then
            local vs = string_explode(value, "=")
            if #vs > 1 then
                value = vs[#vs]
            end
        end
        if value:find(",") then
            vs = string_explode(value, ",")
            if #vs > 1 then
                value = vs[#vs]
            end
        end
        if value:find(";") then
            vs = string_explode(value, ";")
            if #vs > 1 then
                value = vs[#vs]
            end
        end
        if tag then
            if tag:sub(-5) == "files" or tag:sub(-11) == "directories"  then
                tp = "file"
                if display and display:sub(-1) == "/" then
                    tp = "dir"
                end
            elseif tag:sub(-5) == "flags" or tag:sub(-8) == "commands" then
                tp = "arg"
            elseif tag:sub(-7) == "changes" then
                if isdir(value) then
                    tp = "dir"
                else
                    tp = "file"
                end
            end
        end
        if style then
            local color = parsecolor(style)
            if color then
                display = "\x1b[" .. color .. "m" .. display
            end
        end
        match = {
            match = value,
            display = display,
            description = description,
            type = tp,
            suppressappend = nospace and nospace == "*" or (style == "yellow" and value:sub(1, 1) == "-") or
                nospace:find(value:sub(-1)) ~= nil
        }
        matches[#matches + 1] = match
    end
    if #matches == 0 then return false end
    if matchicons and matchicons.addicons then
        matchicons.addicons(matches)
    end
    match_builder:addmatches(matches)
    return true
end
