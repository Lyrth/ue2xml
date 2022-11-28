
local bit = require 'bit'
local fs = require 'fs'

local objectutil = require './objectutil'


---@class ParserBase
---@field buf ByteBuffer
---@field names string[]
---@field imports table
---@field exports table
---@field expOffset integer
local base = {}


---@class Parser
---@field readProperty fun(buf: ByteBuffer, base: ParserBase, expectedLength: integer): table
---@field readValue fun(buf: ByteBuffer, base: ParserBase): any

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
---@param importNames string[]
---@param exportNames string[]
---@param exports table
---@param expOffset integer
function base.parseExports(buf, names, importNames, exportNames, exports, expOffset)
    local self = setmetatable({}, {__index = base})
    self.buf = buf
    self.names = names
    self.imports = importNames
    self.exports = exportNames
    self.expOffset = expOffset  -- uasset size

    local exportObjects = base.newOrderedTable('uexp')
    for i = 0, #exports do
        exportObjects[i+1] = self:parseExport(exports[i])
    end

    return exportObjects
end


local debugTagsFormat = [[
<?xml version="1.0" encoding="UTF-8"?>
<wxHexEditor_XML_TAG>
  <filename path="%s">
%s
  </filename>
</wxHexEditor_XML_TAG>
]]

local debugEntryFormat = [[
    <TAG id="%d">
      <start_offset>%d</start_offset>
      <end_offset>%d</end_offset>
      <tag_text>%s</tag_text>
      <font_colour>#%s</font_colour>
      <note_colour>#%s</note_colour>
    </TAG>
]]

---@param buf ByteBuffer
---@param names string[]
---@param importNames string[]
---@param exportNames string[]
---@param exports table
---@param expOffset integer
function base.parseExportsDebug(buf, names, importNames, exportNames, exports, expOffset, debugUexpPath)
    assert(type(debugUexpPath) == 'string', "Please specify debugUexpPath for the debug variant")
    local self = setmetatable({}, {__index = base})
    self.buf = buf
    self.names = names
    self.imports = importNames
    self.exports = exportNames
    self.expOffset = expOffset  -- uasset size

    local tags = {}
    self.readField = function(self)
        local start = tonumber(self.buf.pos)
        local success, prop = pcall(base.readField, self)
        if success and prop == nil then
            -- none
            tags[#tags+1] = {s = start, e = start - 1 + 8, c = 0x604080, t = "None"}
        elseif not success and type(prop) == 'string' then
            print(prop)
            if prop:find("!!! Invalid name") then
                tags[#tags+1] = {s = start, e = start - 1 + 8, c = 0xFF0000, t = "[Invalid: Name]"}
                goto fail
            else
                tags[#tags+1] = {s = start, e = start - 1 + 8, c = 0x804040, t = "[Name]"}
            end

            if prop:find("!!! Unimplemented class") then
                tags[#tags+1] = {s = start + 8, e = start - 1 + 16, c = 0xFF0000, t = "[Invalid: Class]"}
                goto fail
            else
                tags[#tags+1] = {s = start + 8, e = start - 1 + 16, c = 0x804040, t = "[Class]"}
            end

            tags[#tags+1] = {s = start + 16, e = start - 1 + 24, c = 0x804040, t = "[Length]"}
            tags[#tags+1] = {s = start + 24, e = start + 24, c = 0xFF0000, t = "[Error: '" .. prop .. "']"}

            ::fail::
        elseif success and type(prop) == 'table' then
            -- parse success
            tags[#tags+1] = {s = start, e = start - 1 + 8, c = 0x404040, t = "Name: "..prop._name}
            tags[#tags+1] = {s = start + 8, e = start - 1 + 16, c = 0x404040, t = "Class: "..prop.__type}
            tags[#tags+1] = {s = start + 16, e = start - 1 + 24, c = 0x404040, t = "[Length]"}
            -- t[#t+1] = {s = start + 24, e = self.buf.pos - 1, c = 0x404040, t = "[Data]"}
        end

        if not success then error(prop) end
        return prop
    end

    local exportObjects = base.newOrderedTable('uexp')
    for i = 0, #exports do
        local success, parsed = pcall(self.parseExport, self, exports[i])
        if success then
            exportObjects[i+1] = parsed
        else
            exportObjects[i+1] = self.newOrderedTable('DEBUG', {"!!! Errored part here !!!"})
        end
    end

    local tagsStr = {}
    for i = 1, #tags do
        local tag = tags[i]
        tagsStr[i] = debugEntryFormat:format(i-1, tag.s, tag.e, tag.t, '000000', bit.tohex(tag.c, 6))
    end

    local xml = debugTagsFormat:format(debugUexpPath, table.concat(tagsStr))
    fs.writeFileSync(debugUexpPath..'.tags', xml)

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
        local class = self:getFromIndex(exportInfo.class.type, exportInfo.class.index)
        if class == 'DataTable' then
            -- process datatable
            -- TODO
            local object = self.newOrderedTable('Data')
            object._type = 'DataTable'

            assert(self.buf:read_u32() == 0)
            local count = self.buf:read_u32()

            for j = 1, count do
                local name = self.names[tonumber(self.buf:read_u32())]; self.buf:read_u32()
                local item = self.parsers.StructProperty.readValue(self.buf, self)
                item.__flatten = false
                item.__type = 'TableItem'
                item._name = name

                object[j] = item
            end

            out[i] = object
        else
            print(("Extra data found for class '%s' of length %s at %s"):format(
                class,
                bit.tohex(remaining, 8),
                bit.tohex(self.buf.pos, 8)
            ))
            -- process raw
            out[i] = self:readRaw(remaining)
            out[i]._class = class
        end
    end

    return out
end

function base:readField()
    local name = self.names[tonumber(self.buf:read_u32())]; self.buf:read_u32()
    if name == nil then error("!!! Invalid name at "..bit.tohex(self.buf.pos - 8)) end
    if name == 'None' then return nil end

    local class = self.names[tonumber(self.buf:read_u32())]; self.buf:read_u32()
    class = self:checkClass(class, name)

    local len = self.buf:read_u32(); self.buf:read_u32()
    local prop = self.parsers[class].readProperty(self.buf, self, len)
    prop._name = name

    return prop
end

function base:readFields() return self.readField, self end

function base:readRaw(len)
    local raw = self.buf:read_bytes(len)
    local bytes = {}
    for i = 1, #raw do
        bytes[i] = bit.tohex(raw:sub(i,i):byte(), 2)
    end

    local extra = self.newOrderedTable('Data', table.concat(bytes, ' '))
    extra._type = 'Raw'
    return extra
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
        print(("!!! Unimplemented class, %s%s at %s"):format(
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
        return 'None', ""
    elseif index > 0 then
        local idx = index - 1
        return 'Export', self.exports[idx]
    else
        local idx = -index - 1
        return 'Import', self.imports[idx]
    end
end

function base:getFromIndex(typ, idx)
    if typ == 'None' then
        return ""
    elseif typ == 'Export' then
        return self.exports[idx]
    else
        return self.imports[idx]
    end
end


function base.newOrderedTable(typ, ...)
    local out = objectutil.newOrderedTable()
    if type(typ) == 'string' then
        out.__type = typ
        for i, v in ipairs {...} do
            out[i] = v
        end
    end
    return out
end


return base
