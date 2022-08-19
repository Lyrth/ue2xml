
local bit = require 'bit'


---@class ParserBase
---@field buf ByteBuffer
---@field names string[]
---@field imports table
---@field exports table
---@field expOffset integer
local base = {}


---@class Parser
---@field readProperty fun(buf: ByteBuffer, base: ParserBase, expectedLength: integer)
---@field readValue fun(buf: ByteBuffer, base: ParserBase)

---@type table<string, Parser>
local parsers = {}
base.parsers = parsers

for _, v in ipairs { "primitive", "object", "container" } do
    local c = require("parsers/"..v)
    for name, parser in pairs(c) do
        parsers[name] = parser
    end
end


---@param buf ByteBuffer
---@param names string[]
---@param imports table
---@param exports table
---@param expOffset integer
function base.parseExports(buf, names, imports, exports, exportHeaders, expOffset)
    local self = setmetatable({}, {__index = base})
    self.buf = buf
    self.names = names
    self.imports = imports
    self.exports = exports
    self.expOffset = expOffset  -- uasset size

    local exportObjects = base.newOrderedTable('uexp')
    for i = 0, #exportHeaders do
        exportObjects[i+1] = self:parseExport(exportHeaders[i])
    end

    return exportObjects
end


function base:parseExport(exportInfo)
    local exportSize = exportInfo.serialSize
    local exportOffset = exportInfo.serialOffset - self.expOffset

    self.buf:seek(exportOffset)

    local out = self.newOrderedTable('Export')
    out._name = exportInfo.objectName

    local i = 1
    for prop in self:readFields() do
        out[i] = prop
        i = i + 1
        if self.buf.pos >= exportOffset + exportSize then
            break
        end
    end

    local remaining = exportOffset + exportSize - self.buf.pos
    if remaining > 0 then
        -- extra data
        -- TODO check if image etc
        local extra = self:readRaw(remaining)
        extra._name = 'ExtraData'
        out[i] = extra
    end

    return out
end

function base:readField()
    local name = self.names[tonumber(self.buf:read_u32())]; self.buf:read_u32()
    if name == nil then error("Invalid name at "..bit.tohex(self.buf.pos - 8)) end
    if name == 'None' then return nil, nil, nil end

    local class = self.names[tonumber(self.buf:read_u32())]; self.buf:read_u32()
    class = self:checkClass(class, name)

    local len = self.buf:read_u32(); self.buf:read_u32()
    local prop = self.parsers[class].readProperty(self.buf, self, len)
    prop._name = name

    return prop
end

function base:readFields() return base.readField, self end

function base:readRaw(len)
    local raw = self.buf:read_bytes(len)
    local bytes = {}
    for i = 1, #raw do
        bytes[i] = bit.tohex(raw:sub(i,i):byte(), 2)
    end

    return self.newOrderedTable('raw', table.concat(bytes, ' '))
end


function base:ensureLength(len, fn, ...)
    local startOffset = self.buf.pos
    local result = fn(...)
    local endOffset = self.buf.pos

    if endOffset - startOffset < len then
        print("Warning: extra data at "..endOffset)
        local extra = self:readRaw(len - (endOffset - startOffset))
        if type(result) == 'table' then
            local endIndex = 1
            while result[endIndex] ~= nil do endIndex = endIndex + 1 end
            result[endIndex] = extra
        else
            return result, extra
        end
    elseif endOffset - startOffset > len then
        -- read too much
        error(("ERROR: Overread at start: %s, end: %s, excess: %s"):format(
            bit.tohex(startOffset, 8),
            bit.tohex(endOffset, 8),
            bit.tohex((endOffset - startOffset) - len, 4)
        ))
    end

    return result
end

function base:checkClass(class, name)
    if type(self.parsers[class]) ~= 'table' then
        print(("!!! Unimplemented, %s%s at %s"):format(
            (class or "unknown class"),
            (name and (" with name '"..name.."'") or ""),
            bit.tohex(self.buf.pos - 8)
        ))
        class = 'raw'
    end
    return class
end

function base:resolveIndex(index)
    index = tonumber(index)
    if index == 0 then
        return "None", ""
    elseif index > 0 then
        local idx = index - 1
        return "Export", self.exports[idx]
    else
        local idx = -index - 1
        return "Import", self.imports[idx]
    end
end


function base.newOrderedTable(typ, ...)
    if type(typ) == 'string' then
        local out = base.newOrderedTable()
        out.__type = typ
        for i, v in ipairs {...} do
            out[i] = v
        end
        return out
    end

    local meta = {}
    meta.__newindex = function(t, k ,v)
        if not rawget(t._values, k) then -- new key 
            t._keys[#t._keys + 1] = k
        end
        if v == nil then -- delete key too.
            if t._values[k] ~= nil then
                for i, v2 in ipairs(t._keys) do
                    if v2 == k then
                        table.remove(t._keys, i)
                        break
                    end
                end
                t._values[k] = nil
            end
        else -- update/store value
            t._values[k] = v
        end
    end
    meta.__len = function(t) return #t._keys end
    meta.__index = function(t, k)
        return rawget(t._values, k)
    end
    meta.__pairs = function(t)
        local i = 0
        return function()
            i = i + 1
            local key = t._keys[i]
            if key ~= nil then
                return key, t._values[key]
            end
        end
    end
    return setmetatable({_keys = {}, _values = {}}, meta)
end


return base
