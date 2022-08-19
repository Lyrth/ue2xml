
---use-luvit

local FILE = 'analyze/BP_Default_AbilitiesDatabase.uasset'


local fs = require 'fs'
local bit = require 'bit'
local strcrc = require './strcrc'

local ByteBuffer = require './bytebuffer'


---@type ByteBuffer
local buf = ByteBuffer.from(assert(fs.readFileSync(FILE)))


---@param buf ByteBuffer
local function readString(buf)
    local len = buf:read_i32()
    -- TODO: utf16 support
    return buf:read_bytes(len):gsub('%z$','')
end


---@param buf ByteBuffer
local function readGuid(buf)
    local guid = {}
    for i = 1,16 do
        guid[i] = bit.tohex(buf:read_u8(), 2)
    end

    return table.concat(guid)
end


---@param buf ByteBuffer
local function readCustomVersion(buf)
    local t = {}
    t.key       = readGuid(buf)
    t.version   = buf:read_i32()

    return t
end


---@param buf ByteBuffer
local function readHeader(buf)
    local t = {}
    t.tag                   = buf:read_u32()
    t.legacyVersion         = buf:read_i32()
    t.legacyUe3Version      = buf:read_i32()
    t.versionUe4            = buf:read_i32()
    t.versionLicenseeUe4    = buf:read_i32()
    t.customVersions        = {}
    do
        local arrLen = buf:read_u32()
        for i = 1, arrLen do
            p('a')
            t.customVersions[i] = readCustomVersion(buf)
        end
    end
    t.totalHeaderSize   = buf:read_u32()
    t.folderName        = readString(buf)
    t.packageFlags      = buf:read_u32()
    t.nameCount         = buf:read_u32()
    t.nameOffset        = buf:read_u32()
    t.gatherableTextDataCount   = buf:read_u32()
    t.gatherableTextDataOffset  = buf:read_u32()
    t.exportCount       = buf:read_u32()
    t.exportOffset      = buf:read_u32()
    t.importCount       = buf:read_u32()
    t.importOffset      = buf:read_u32()
    t.dependsOffset     = buf:read_u32()
    t.stringAssetReferencesCount    = buf:read_u32()
    t.stringAssetReferencesOffset   = buf:read_u32()
    t.searchableNamesOffset     = buf:read_u32()
    t.thumbnailTableOffset      = buf:read_u32()
    t.guid              = readGuid(buf)
    t.generations       = {}
    do
        local arrLen = buf:read_u32()
        for i = 1, arrLen do
            t.generations[i] = {
                exportCount = buf:read_u32(),
                nameCount = buf:read_u32(),
            }
        end
    end
    t.bulkDataStartOffset = buf:read_u32()

    buf:seek(0xBD)
    t.dataOffset = buf:read_u32()

    return t
end


---@param buf ByteBuffer
local function readName(buf)
    local name = readString(buf)
    local iHash = buf:read_u16()
    local sHash = buf:read_u16()
    if iHash ~= strcrc.RawNonCasePreservingHash(name) then
        print('String '..name..' not have matching ihash')
    end
    if sHash ~= strcrc.RawCasePreservingHash(name) then
        print('String '..name..' not have matching shash')
    end

    return name
end

local names = {}

local function resolveIndex(index)
    index = tonumber(index)
    if index == 0 then
        return "<Root>"
    elseif index > 0 then
        local idx = index - 1
        return ("<Export %03d (%s)>"):format(idx, bit.tohex(idx, 4))
    else
        local idx = -index - 1
        return ("<Import %03d (%s)>"):format(idx, bit.tohex(idx, 4))
    end
end

local function resolveName(low, high)
    if low >= 0 then
        return names[tonumber(low)]
    else
        error(("What high: %s, low: %s"):format(bit.tohex(high, 8), bit.tohex(low, 8)))
    end
end



---@param buf ByteBuffer
local function readImport(buf)
    local t = {}
    t.classPackage = resolveName(buf:read_i32(), buf:read_i32())
    t.className = resolveName(buf:read_i32(), buf:read_i32())
    t.outer = resolveIndex(buf:read_i32())
    t.objectName = resolveName(buf:read_i32(), buf:read_i32())

    return t
end


---@param buf ByteBuffer
local function readExport(buf)
    local t = {}
    t.class = resolveIndex(buf:read_i32())
    t.super = resolveIndex(buf:read_i32())
    t.template = resolveIndex(buf:read_i32())
    t.outer = resolveIndex(buf:read_i32())
    t.objectName = resolveName(buf:read_i32(), buf:read_i32())
    t.save = buf:read_u32()
    t.serialSize = buf:read_u32(); buf:read_u32()
    t.serialOffset = buf:read_u32(); buf:read_u32()
    t.forcedExport = buf:read_u32() ~= 0
    t.notForClient = buf:read_u32() ~= 0
    t.notForServer = buf:read_u32() ~= 0
    t.packageGuid = readGuid(buf)
    t.packageFlags = buf:read_u32()
    t.notAlwaysLoadedForEditorGame = buf:read_u32() ~= 0
    t.isAsset = buf:read_u32() ~= 0
    t.firstExportDependency = buf:read_i32()
    t.serializeBeforeSerializationDependencies = buf:read_u32() ~= 0
    t.createBeforeSerializationDependencies = buf:read_u32() ~= 0
    t.serializeBeforeCreateDependencies = buf:read_u32() ~= 0
    t.createBeforeCreateDependencies = buf:read_u32() ~= 0

    return t
end




-----



local head = readHeader(buf)
p(head)


print()
print("----- NAMES -----")
buf:seek(head.nameOffset)
for i = 0, head.nameCount-1 do
    local n = readName(buf)
    names[i] = n
    print(("%03d\t%s\t%s"):format(i, bit.tohex(i, 4), n))
end

local imports = {}

print()
print("----- IMPORTS -----")
buf:seek(head.importOffset)
for i = 0, head.importCount-1 do
    local import = readImport(buf)
    local n = ("%s/%s:%s outer:%s"):format(
        import.classPackage,
        import.className,
        import.objectName,
        import.outer
    )

    imports[i] = import.objectName
    print(("%03d\t%s\t%s"):format(i, bit.tohex(i, 4), n))
end

local exports = {}
local exportHeaders = {}

print()
print("----- EXPORTS -----")
buf:seek(head.exportOffset)
for i = 0, head.exportCount-1 do
    local export = readExport(buf)
    local n = ("%s : %s outer:%s"):format(
        export.objectName,
        export.class,
        export.outer
    )

    exportHeaders[i] = export
    exports[i] = export.objectName
    print(("%03d\t%s\t%s - @%s #%s"):format(
        i,
        bit.tohex(i, 4),
        n,
        bit.tohex(export.serialOffset - buf.length, 4),
        bit.tohex(export.serialSize, 4))
    )
end

print()
print("----- EXTRA -----")
buf:seek(head.dataOffset)
while buf.pos < buf.length do
    local index = buf:read_i32()
    if index == 0 then
        print("<Root>")
    elseif index > 0 then
        local idx = index - 1
        print(exports[tonumber(idx)])
    else
        local idx = -index - 1
        print(imports[tonumber(idx)])
    end
end

local function OPT()
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

-- __type
-- __flatten
-- _attrname
-- [1] content
local function convertToDom(tb)
    if type(tb) == 'table' then
        local name = tb.__type or "UNKNOWN"
        local flat = tb.__flatten

        local attr = {}
        local kids = {}

        --name first
        if tb._name then
            table.insert(attr, {
                type = 'attribute',
                name = 'name',
                value = tostring(tb._name)
            })
            tb._name = nil
        end

        for k, v in pairs(tb) do
            if type(k) == 'string' and k:sub(1,1) == '_' and k:sub(2,2) ~= '_' then
                table.insert(attr, {
                    type = 'attribute',
                    name = k:sub(2),
                    value = tostring(v)
                })
            end
        end

        -- sequential ordering important
        for i = 1, math.huge do
            local v = tb[i]
            if v == nil then break end
            local d = convertToDom(v)
            if d.type == 'element' and d.__flatten then
                for _, child in ipairs(d.kids) do
                    table.insert(kids, child)
                end
            else
                table.insert(kids, d)
            end
        end

        return {
            name = name,
            type = 'element',
            attr = attr,
            kids = kids,
            __flatten = flat
        }
    else
        if type(tb) == 'cdata' then tb = tonumber(tb) end
        return {
            type = 'text',
            name = '#text',
            value = tostring(tb)
        }
    end
end

--do return end


---@type ByteBuffer
local uexp = ByteBuffer.from(assert(fs.readFileSync(FILE:gsub("%.uasset", "%.uexp"))))

--local Readers = require 'readers'
--local t = Readers.new(names, imports, exports):beginRead(uexp, "Default__?")

local baseread = require 'baseread'

local t = baseread.parseExports(uexp, names, imports, exports, exportHeaders, buf.length)


local dom = {
    type = 'document',
    name = '#doc',
    kids = {
        convertToDom(t)
    }
}


local xml = require'slaxdom'
fs.writeFileSync(FILE:gsub("%.uasset", "%.uexp")..".xml", xml:xml(dom, {indent = 4}))


p("Aa")