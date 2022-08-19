
local bit = require 'bit'
local ffi = require 'ffi'

local toFloat, toDouble
do  -- converters
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
    toFloat = function(u32)
        return tonumber(("%.4f"):format(ffi.cast(fptr, u32s(fromLE32(u32)))[0]))
    end

    toDouble = function(u64)
        return tonumber(("%.8f"):format(ffi.cast(dptr, u64s(fromLE64(u64)))[0]))
    end
end -- converters


---@type table<string, Parser>
local parsers = {}


-- generate readProperty and readValue for simple types
local function primitiveParser(typ, fun)
    local parser = {}
    parser.readProperty = function(buf, base, len)
        assert(buf:read_u8() == 0)
        return base.newOrderedTable(typ,
            base:ensureLength(len, parser.readValue, buf, base))
    end
    parser.readValue = fun
    return parser
end


parsers.FloatProperty   = primitiveParser('Float',  function(buf) return toFloat(buf:read_u32())  end)
parsers.DoubleProperty  = primitiveParser('Double', function(buf) return toDouble(buf:read_u64()) end)
parsers.Int64Property   = primitiveParser('Int64',  function(buf) return buf:read_i64() end)
parsers.Int32Property   = primitiveParser('Int32',  function(buf) return buf:read_i32() end)
parsers.Int16Property   = primitiveParser('Int16',  function(buf) return buf:read_i16() end)
parsers.Int8Property    = primitiveParser('Int8',   function(buf) return buf:read_i8()  end)
parsers.UInt64Property  = primitiveParser('UInt64', function(buf) return buf:read_u64() end)
parsers.UInt32Property  = primitiveParser('UInt32', function(buf) return buf:read_u32() end)
parsers.UInt16Property  = primitiveParser('UInt16', function(buf) return buf:read_u16() end)

parsers.IntProperty     = primitiveParser('Int',    function(buf) return buf:read_i32() end)

parsers.BoolProperty = {}
parsers.BoolProperty.readProperty = function(buf, base, len)
    local value = buf:read_u8() ~= 0    -- 1-byte flag: bool value
    assert(buf:read_u8() == 0)          -- normal data divider

    return base:ensureLength(len, function()
        return base.newOrderedTable('Bool', value)
    end)
end
parsers.BoolProperty.readValue = function(buf)
    error(("BoolProperty.readValue should never be called! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end

-- ByteProperty: literally just an EnumProperty(?) OR-able EnumProperty i guess


return parsers
