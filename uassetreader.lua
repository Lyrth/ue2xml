
local bit = require 'bit'
local utf = require 'utf'
local strcrc = require './strcrc'

local tohex, band = bit.tohex, bit.band
local concat = table.concat


---- Basic ----

---@param buf ByteBuffer
local function readString(buf)
    local strlen = buf:read_i32()
    local str
    if strlen >= 0 then
        str = buf:read_bytes(strlen)
    else
        str = utf.utf16ToUtf8(buf:read_bytes(-strlen * 2))
    end

    if str:byte(-1) == 0 then str = str:sub(1, -2) end
    return str
end

---@param buf ByteBuffer
local function readGuid(buf)
    local guid = {}
    for i = 1,16 do
        guid[i] = tohex(buf:read_u8(), 2)
    end

    return concat(guid)
end

---@param buf ByteBuffer
---@param num integer
---@param fn fun(buf:ByteBuffer):any
local function readArray(buf, num, fn, ...)
    local t = {}
    for i = 0, num-1 do
        t[i] = fn(buf, ...)
    end
    return t
end


---- Summary-specific ----

---@param buf ByteBuffer
local function readCustomVersion(buf)
    return {
        key       = readGuid(buf),
        version   = buf:read_i32(),
    }
end

---@param buf ByteBuffer
local function readGeneration(buf)
    return {
        exportCount = buf:read_u32(),
        nameCount = buf:read_u32(),
    }
end

---@param buf ByteBuffer
local function readEngineVersion(buf)
    return {
        major   = buf:read_u16(),
        minor   = buf:read_u16(),
        patch   = buf:read_u16(),
        changelist  = buf:read_u32(),
        name    = readString(buf),
    }
end

---@param buf ByteBuffer
local function readCompressedChunk(buf)
    return {
        uncompressedOffset  = buf:read_u32(),
        uncompressedSize    = buf:read_u32(),
        compressedOffset    = buf:read_u32(),
        compressedSize      = buf:read_u32(),
    }
end


---- Resolvers ----

local resolvable = {__tostring = function(t)
    return ("<%s %04d (%sh)>"):format(t.type, t.index, tohex(t.index, 4))
end}
local function resolveIndex(index)
    index = tonumber(index)
    if index == 0 then
        return setmetatable({type = 'None', index = 0}, resolvable)
    elseif index > 0 then
        index = index - 1
        return setmetatable({type = 'Export', index = index}, resolvable)
    else
        index = -index - 1
        return setmetatable({type = 'Import', index = index}, resolvable)
    end
end

local function resolveName(names, low, high)
    if low >= 0 then
        return names[tonumber(low)]
    else
        error(("Unknown name high: %s, low: %s"):format(tohex(high, 8), tohex(low, 8)))
    end
end


---- Actual sections ----

---@param buf ByteBuffer
local function readSummary(buf)
    local t = {}
    t.tag                   = buf:read_u32()
    assert(t.tag == 0x9E2A83C1ULL, "Invalid uasset file")

    t.legacyFileVersion     = buf:read_i32()    -- -7 4.27, -8 is ue5
    t.legacyUe3Version      = buf:read_i32()
    t.fileVersionUe4        = buf:read_i32()
    t.fileVersionLicenseeUe4= buf:read_i32()
    t.customVersions        = readArray(buf, buf:read_u32(), readCustomVersion)
    t.totalHeaderSize       = buf:read_u32()
    t.folderName            = readString(buf)
    t.packageFlags          = buf:read_u32()
    t.isFilterEditorOnly    = band(t.packageFlags, 0x80000000ULL) > 0
    t.isMapPackage          = band(t.packageFlags, 0x00020000ULL) > 0

    t.nameCount             = buf:read_u32()
    t.nameOffset            = buf:read_u32()
    t.localizationId        = not t.isFilterEditorOnly and readString(buf) or nil
    t.gatherableTextDataCount   = buf:read_u32()
    t.gatherableTextDataOffset  = buf:read_u32()
    t.exportCount           = buf:read_u32()
    t.exportOffset          = buf:read_u32()
    t.importCount           = buf:read_u32()
    t.importOffset          = buf:read_u32()
    t.dependsOffset         = buf:read_u32()
    t.softPackageReferencesCount    = buf:read_u32()
    t.softPackageReferencesOffset   = buf:read_u32()
    t.searchableNamesOffset = buf:read_u32()
    t.thumbnailTableOffset  = buf:read_u32()
    t.guid                  = readGuid(buf)
    t.persistentGuid        = not t.isFilterEditorOnly and readGuid(buf) or nil
    t.generations           = readArray(buf, buf:read_u32(), readGeneration)

    t.savedByEngineVersion          = readEngineVersion(buf)
    t.compatibleWithEngineVersion   = readEngineVersion(buf)
    t.compressionFlags      = buf:read_u32()
    t.compressedChunks      = readArray(buf, buf:read_u32(), readCompressedChunk)
    assert(t.compressionFlags < 256, "Invalid compression flags")
    assert(#t.compressedChunks == 0, "Cannot read uasset with compressed chunks")

    t.packageSource             = buf:read_u32()
    t.additionalPackagesToCook  = readArray(buf, buf:read_u32(), readString)
    t.assetRegistryDataOffset   = buf:read_u32()
    t.bulkDataStartOffset       = buf:read_u64()      -- uasset + uexp - 4
    t.worldTileInfoDataOffset   = buf:read_u32()
    t.chunkIds                  = readArray(buf, buf:read_u32(), buf.read_u32)
    t.preloadDependencyCount    = buf:read_u32()
    t.preloadDependencyOffset   = buf:read_u32()

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

---@param buf ByteBuffer
local function readImport(buf, names)
    local t = {}
    t.classPackage = resolveName(names, buf:read_i32(), buf:read_i32())
    t.className = resolveName(names, buf:read_i32(), buf:read_i32())
    t.outer = resolveIndex(buf:read_i32())
    t.objectName = resolveName(names, buf:read_i32(), buf:read_i32())

    return t
end

---@param buf ByteBuffer
local function readExport(buf, names)
    local t = {}
    t.class = resolveIndex(buf:read_i32())
    t.super = resolveIndex(buf:read_i32())
    t.template = resolveIndex(buf:read_i32())
    t.outer = resolveIndex(buf:read_i32())
    t.objectName = resolveName(names, buf:read_i32(), buf:read_i32())
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

---@param buf ByteBuffer
local function readDepends(buf)
    return readArray(buf, buf:read_u32(), function(buf2) return resolveIndex(buf2:read_i32()) end)
end

---@param buf ByteBuffer
local function readAssetRegistry(buf, summary)
    if not summary.isFilterEditorOnly then
        local _ = buf:read_u64()    -- outDependencyDataOffset
    end

    return readArray(buf, buf:read_u32(), function(buf2)
        return {
            objectPath = readString(buf2),
            objectClassName = readString(buf2),
            tags = readArray(buf2, buf2:read_u32(), function(buf3)
                return {
                    key = readString(buf3),
                    value = readString(buf3),
                }
            end)
        }
    end)
end



---@param buf ByteBuffer
local function readUasset(buf)
    local t = {}
    t.summary = readSummary(buf)

    buf:seek(t.summary.nameOffset)
    t.names = readArray(buf, t.summary.nameCount, readName)

    buf:seek(t.summary.importOffset)
    t.imports = readArray(buf, t.summary.importCount, readImport, t.names)

    buf:seek(t.summary.exportOffset)
    t.exports = readArray(buf, t.summary.exportCount, readExport, t.names)

    buf:seek(t.summary.dependsOffset)
    t.depends = readArray(buf, t.summary.exportCount, readDepends)

    buf:seek(t.summary.assetRegistryDataOffset)
    t.assets = readAssetRegistry(buf, t.summary)

    buf:seek(t.summary.preloadDependencyOffset)
    t.preloadDependencies = readArray(buf, t.summary.preloadDependencyCount, function(buf2) return resolveIndex(buf2:read_i32()) end)

    t.importNames = {}
    for i = 0, #t.imports do
        t.importNames[i] = t.imports[i].objectName
    end

    t.exportNames = {}
    for i = 0, #t.exports do
        t.exportNames[i] = t.exports[i].objectName
    end

    if t.summary.totalHeaderSize ~= buf.pos then
        print("WARN: totalHeaderSize does not match actual uasset (header) size")
    end

    return t
end


return readUasset
