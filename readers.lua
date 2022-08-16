
local bit = require 'bit'
local ffi = require 'ffi'

local fromLE32, fromLE64
if ffi.abi('le') then
    fromLE32 = function(n) return n end
    fromLE64 = function(n) return n end
else
    if ffi.abi('win') then
        ffi.cdef [[
            uint16_t bswap16(uint16_t x) __asm__("_byteswap_ushort");
            uint32_t bswap32(uint32_t x) __asm__("_byteswap_ulong");
            uint64_t bswap64(uint64_t x) __asm__("_byteswap_uint64");
        ]]
    else
        ffi.cdef [[
            uint16_t bswap16(uint16_t x) __asm__("__builtin_bswap16");
            uint32_t bswap32(uint32_t x) __asm__("__builtin_bswap32");
            uint64_t bswap64(uint64_t x) __asm__("__builtin_bswap64");
        ]]
    end

    local U = (ffi.os == 'Windows') and ffi.load('ucrtbase') or ffi.C

    fromLE32 = U.bswap32
    fromLE64 = U.bswap64
end

local u32s, u64s = ffi.typeof 'uint32_t[1]', ffi.typeof 'uint64_t[1]'
local fptr, dptr = ffi.typeof 'float*', ffi.typeof 'double*'
local function toFloat(u32)
    return tonumber(("%.4f"):format(ffi.cast(fptr, u32s(fromLE32(u32)))[0]))
end

local function toDouble(u64)
    return tonumber(("%.8f"):format(ffi.cast(dptr, u64s(fromLE64(u64)))[0]))
end


--- order-preserving table
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


local knownStructs = { Box = true, Box2D = true, Color = true, ColorMaterialInput = true, DateTime = true, ExpressionInput = true, FrameNumber = true, Guid = true, NavAgentSelector = true, SmartName = true, RichCurveKey = true, SimpleCurveKey = true, ScalarMaterialInput = true, ShadingModelMaterialInput = true, VectorMaterialInput = true, Vector2MaterialInput = true, MaterialAttributesInput = true, SkeletalMeshSamplingLODBuiltData = true, SkeletalMeshSamplingRegionBuiltData = true, PerPlatformBool = true, PerPlatformFloat = true, PerPlatformInt = true, PerQualityLevelInt = true, GameplayTagContainer = true, IntPoint = true, IntVector = true, LevelSequenceObjectReferenceMap = true, LinearColor = true, NiagaraVariable = true, NiagaraVariableBase = true, NiagaraVariableWithOffset = true, NiagaraDataInterfaceGPUParamInfo = true, MovieSceneEvalTemplatePtr = true, MovieSceneEvaluationFieldEntityTree = true, MovieSceneEvaluationKey = true, MovieSceneFloatChannel = true, MovieSceneFloatValue = true, MovieSceneFrameRange = true, MovieSceneSegment = true, MovieSceneSegmentIdentifier = true, MovieSceneSequenceID = true, MovieSceneTrackIdentifier = true, MovieSceneTrackImplementationPtr = true, FontData = true, FontCharacter = true, Plane = true, Quat = true, Rotator = true, SectionEvaluationDataTree = true, StringClassReference = true, SoftClassPath = true, StringAssetReference = true, SoftObjectPath = true, Timespan = true, UniqueNetIdRepl = true, Vector = true, Vector2D = true, Vector4 = true, Vector_NetQuantize = true, Vector_NetQuantize10 = true, Vector_NetQuantize100 = true, Vector_NetQuantizeNormal = true }


local r = {
    ---@type table<integer, string>
    names = {},
    ---@type table<integer, string>
    imports = {},
    ---@type table<integer, string>
    exports = {}
}

function r.new(names, imports, exports)
    return setmetatable({
        names = names,
        imports = imports,
        exports = exports
    }, {__index = r})
end

function r:resolveIndex(index)
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

function r:checkClass(pos, class, name)
    if type(self[class]) ~= 'function' then
        print(("!!! Unimplemented, %s%s at %s"):format(
            (class or "unknown class"),
            (name and (" with name '"..name.."'") or ""),
            bit.tohex(pos)
        ))
        class = 'raw'
    end
    return class
end


-- TODO return remaining bytes instead if unreadable
---@param buf ByteBuffer
function r:beginRead(buf, rootName)
    local name = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    if name == nil then error("Invalid name at "..bit.tohex(buf.pos - 8)) end
    if name == 'None' then return self:_None(buf) end

    local class = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    class = self:checkClass(buf.pos - 8, class, name)

    local obj = self[class](self, buf)
    obj._name = name

    local out = OPT()
    out.__type = 'Root'
    out._name = rootName
    out[1] = obj
    return out
end

function r:bytesRaw(buf, len)
    local raw = buf:read_bytes(len)
    local bytes = {}
    for i = 1, #raw do
        bytes[i] = bit.tohex(raw:sub(i,i):byte(), 2)
    end

    local out = OPT()
    out.__type = '_Raw'
    out[1] = table.concat(bytes, ' ')
    return out
end

function r:raw(buf)
    -- guesswork TODO read until last 0: extra props, read until non zero: raw data
    -- 07000000 03000000 04000000 00000000 00000000 00 21000000
    -- 09000000 02000000 00000000 01 00 - bool
    local len = buf:read_u32(); buf:read_u32()
    while buf:read_u8() ~= 0 do
        buf:advance(7)
    end

    return self:bytesRaw(buf, len)
end

-- TODO OOOOOOOOOOOOO ensure length for all types

-- TODO OOOOOOO PRPERTY VARIANTS

-- Basic types --

function r:FloatProperty(buf)   assert(buf:read_u64() == 4) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'Float' out[1] = toFloat(buf:read_u32()) return out end
function r:DoubleProperty(buf)  assert(buf:read_u64() == 8) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'Double' out[1] = toDouble(buf:read_u64()) return out end
function r:Int64Property(buf)   assert(buf:read_u64() == 8) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'Int64' out[1] = buf:read_i64() return out end
function r:Int32Property(buf)   assert(buf:read_u64() == 4) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'Int32' out[1] = buf:read_i32() return out end
function r:Int16Property(buf)   assert(buf:read_u64() == 2) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'Int16' out[1] = buf:read_i16() return out end
function r:Int8Property(buf)    assert(buf:read_u64() == 1) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'Int8' out[1] = buf:read_i8() return out end
function r:UInt64Property(buf)  assert(buf:read_u64() == 8) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'UInt64' out[1] = buf:read_u64() return out end
function r:UInt32Property(buf)  assert(buf:read_u64() == 4) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'UInt32' out[1] = buf:read_u32() return out end
function r:UInt16Property(buf)  assert(buf:read_u64() == 2) assert(buf:read_u8() == 0) local out = OPT() out.__type = 'UInt16' out[1] = buf:read_u16() return out end

-- proooobably a signed int??
function r:IntProperty(buf)
    local out = self:Int32Property(buf)
    out.__type = 'Int'
    return out
end

function r:BoolProperty(buf)
    assert(buf:read_u64() == 0)
    local value = buf:read_u8() ~= 0
    assert(buf:read_u8() == 0)

    local out = OPT()
    out.__type = 'Bool'
    out[1] = value
    return out
end

-- lies
function r:ByteProperty(buf)
    local out = self:EnumProperty(buf)
    out.__type = 'Byte'
    return out
end


-- Other types --

function r:ObjectProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)
    local objType, object = self:resolveIndex(buf:read_i32())

    local out = OPT()
    out.__type = 'Object'
    out._type = objType
    out[1] = object
    return out
end

function r:SoftObjectProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)
    local objType, object = self:resolveIndex(buf:read_i32()); buf:read_i32()
    local subpath = self:_FName(buf)

    local out = OPT()
    out.__type = 'SoftObject'
    out._type = objType
    out._subpath = #subpath > 0 and subpath or nil
    out[1] = object
    return out
end

function r:NameProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)
    local name = self.names[tonumber(buf:read_u32())]; buf:read_u32()

    local out = OPT()
    out.__type = 'Name'
    out[1] = name
    return out
end


function r:_FName(buf)
    local strlen = buf:read_i32()
    if strlen < 0 then error('TODO UTF16') end
    local str = buf:read_bytes(strlen)
    if str:match('%z$') then
        str = str:sub(1, -2)
    end
    return str
end

function r:StrProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)

    local out = OPT()
    out.__type = 'Str'
    out[1] = self:_FName(buf)
    return out
end

function r:TextProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)
    assert(buf:read_u32() == 0)

    local empty = buf:read_i8() == -1

    local namespace = self:_FName(buf)

    local key, str = '', ''
    if not empty then
        key = self:_FName(buf)
        str = self:_FName(buf)
    end

    local out = OPT()
    out.__type = 'Text'
    out._namespace = namespace
    out._key = key
    out[1] = str
    return out
end

function r:_DelegateValue(buf)
    local out = OPT()
    out.__type = '_DelegateValue'
    out._object = tonumber(buf:read_i32())
    out[1] = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    return out

end

function r:DelegateProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)

    local out = self:_DelegateValue(buf)
    out.__type = 'Delegate'
    return out
end

function r:MulticastDelegateProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)
    local num = buf:read_u32();

    local out = OPT()
    out.__type = 'MulticastDelegate'

    for i = 1, num do
        out[i] = self:_DelegateValue(buf)
    end

    return out
end

function r:MulticastInlineDelegateProperty(buf)
    local out = self:MulticastDelegateProperty(buf)
    out.__type = 'MulticastInlineDelegate'
    return out
end

function r:MulticastSparseDelegateProperty(buf)
    local out = self:MulticastDelegateProperty(buf)
    out.__type = 'MulticastSparseDelegate'
    return out
end


-- Container types --

function r:_EnumValue(buf)
    local value = self.names[tonumber(buf:read_u32())]; buf:read_u32()

    local out = OPT()
    out.__type = '_EnumValue'
    out.__flatten = true
    out[1] = value
    return out
end

function r:EnumProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    local enum = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    assert(buf:read_u8() == 0)
    local val = self:_EnumValue(buf)
    if len > 8 then
        buf:read_bytes(len - 8)
    end

    local out = OPT()
    out.__type = 'Enum'
    out._enum = enum
    out[1] = val
    return out
end


function r:_ResolveAsItem(buf, subclass, totalLen)
    if subclass == 'StructProperty' then
        local name = self.names[tonumber(buf:read_u32())]; buf:read_u32()
        local class = self.names[tonumber(buf:read_u32())]; buf:read_u32()
        assert(class == subclass)
        local thislen = buf:read_u32(); buf:read_u32()  -- 0x35
        assert(thislen == totalLen - 0x35)              -- 4b num, 8b name, 8b class, 8b thislen, 8b structclass, 1b 0, 16b 0
        local structType = self.names[tonumber(buf:read_u32())]; buf:read_u32()
        assert(buf:read_u8() == 0)
        assert(buf:read_u64() == 0)
        assert(buf:read_u64() == 0)
        return '_StructBody', 'Struct:'..structType
    end
    if subclass == 'EnumProperty' then
        return '_EnumValue', 'EnumValue'
    end
    return subclass
end

-- after the zeroes
function r:_StructMember(buf)
    local name = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    if name == nil then error("Invalid name at "..bit.tohex(buf.pos - 8)) end
    if name == 'None' then return nil end

    local class = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    class = self:checkClass(buf.pos - 8, class, name)

    return {
        key = name,
        value = self[class](self, buf)
    }
end

-- all fields until None
function r:_StructBody(buf)
    local out = OPT()
    out.__type = '_StructBody'
    out.__flatten = true
    local i = 1
    while true do
        local member = self:_StructMember(buf)
        if member == nil then break end
        member.value._name = member.key
        out[i] = member.value
        i = i + 1
    end
    return out
end

function r:StructProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    local structType = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    assert(buf:read_u64() == 0) -- flags 1?
    assert(buf:read_u64() == 0) -- flags 2?
    assert(buf:read_u8() == 0)

    local out = OPT()
    out.__type = 'Struct'
    out._subtype = structType

    if knownStructs[structType] then
        -- TODO: for all of those structs
        out[1] = self:bytesRaw(buf, len)
    else
        out[1] = self:_StructBody(buf)
    end

    return out
end

function r:ArrayProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    local subclass = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    subclass = self:checkClass(buf.pos - 8, subclass)
    assert(buf:read_u8() == 0)
    local num = buf:read_u32()

    local subtype = nil
    subclass, subtype = self:_ResolveAsItem(buf, subclass, len)

    local out = OPT()
    out.__type = 'Array'
    out._subtype = subtype

    for i = 1, num do
        local item = OPT()
        item.__type = 'ArrayItem'
        item[1] = self[subclass](self, buf)
        out[i] = item
    end

    return out
end

function r:SetProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    local subclass = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    subclass = self:checkClass(buf.pos - 8, subclass)
    assert(buf:read_u8() == 0)
    assert(buf:read_u32() == 0)
    local num = buf:read_u32()

    local subtype = nil
    subclass, subtype = self:_ResolveAsItem(buf, subclass, len)

    local out = OPT()
    out.__type = 'Set'
    out._subtype = subtype

    for i = 1, num do
        local item = OPT()
        item.__type = 'SetItem'
        item[1] = self[subclass](self, buf)
        out[i] = item
    end

    return out
end



function r:MapProperty(buf)
    local len = buf:read_u32(); buf:read_u32()
    local keyClass = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    keyClass = self:checkClass(buf.pos - 8, keyClass)
    local valClass = self.names[tonumber(buf:read_u32())]; buf:read_u32()
    valClass = self:checkClass(buf.pos - 8, valClass)
    assert(buf:read_u8() == 0)
    assert(buf:read_u32() == 0)
    local num = buf:read_u32()

    local keySubtype, valSubtype = nil, nil
    keyClass, keySubtype = self:_ResolveAsItem(buf, keyClass, len)
    valClass, valSubtype = self:_ResolveAsItem(buf, valClass, len)


    local out = OPT()
    out.__type = 'Map'
    out._keyClass = keySubtype
    out._valClass = valSubtype

    for i = 1, num do
        local item = OPT()
        item.__type = 'MapItem'
        item[1] = {
            __type = 'Key',
            self[keyClass](self, buf)
        }
        item[2] = {
            __type = 'Value',
            self[valClass](self, buf)
        }
        out[i] = item
    end

    return out
end


function r:_None(buf)
    if buf:read_u32() ~= 0 then
        -- was a closing None
        buf:advance(-4)
        return nil
    end
    -- todo
    if buf:read_u16() == 1 then
        -- image
    else
        return nil
    end
end


return r