
local bit = require 'bit'
local utf = require 'utf'


---@type table<string, Parser>
local parsers = {}


local function FName(buf)
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


parsers.EnumProperty = {}
parsers.EnumProperty.readProperty = function(buf, base, len)
    local enum = base.names[tonumber(buf:read_u64())]
    assert(buf:read_u8() == 0)
    local out = base:ensureLength(len, function()
        if enum == 'None' then
            -- bitfield??
            local out = base.newOrderedTable('Enum', bit.tohex(buf:read_u8(), 2))
            out._type = 'bitfield'
            return out
        end
        local val = base.names[tonumber(buf:read_u64())]
        return base.newOrderedTable('Enum', val)
    end)
    out._enum = enum

    return out
end
parsers.EnumProperty.readValue = function(buf, base)
    return base.names[tonumber(buf:read_u64())]
end

parsers.ByteProperty = {}
parsers.ByteProperty.readProperty = function(buf, base, len)
    local out = parsers.EnumProperty.readProperty(buf, base, len)
    out.__type = 'Byte'
    return out
end
parsers.ByteProperty.readValue = function(buf, base)
    -- return parsers.EnumProperty.readValue(buf, base)
    -- weird asf
    return tonumber(buf:read_u8())
end

parsers.ObjectProperty = {}
parsers.ObjectProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        local objType, object = base:resolveIndex(buf:read_i32())

        local out = base.newOrderedTable('Object', object)
        out._type = objType
        return out
    end)
end
parsers.ObjectProperty.readValue = function(buf, base)
    local _, object = base:resolveIndex(buf:read_i32())
    return object
end

parsers.SoftObjectProperty = {}
parsers.SoftObjectProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        local object = base.names[tonumber(buf:read_u64())]
        local subpath = FName(buf)

        local out = base.newOrderedTable('SoftObject', object)
        if #subpath > 0 then
            out._subpath = subpath
        end
        return out
    end)
end
parsers.SoftObjectProperty.readValue = function(buf, base)
    error(("SoftObjectProperty.readValue unimplemented! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end

parsers.NameProperty = {}
parsers.NameProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        local name = base.names[tonumber(buf:read_u64())]
        return base.newOrderedTable('Name', name)
    end)
end
parsers.NameProperty.readValue = function(buf, base)
    return base.names[tonumber(buf:read_u64())]
end

parsers.StrProperty = {}
parsers.StrProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        return base.newOrderedTable('Str', FName(buf))
    end)
end
parsers.StrProperty.readValue = function(buf, base)
    return FName(buf)
end

parsers.TextProperty = {}
parsers.TextProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        assert(buf:read_u32() == 0)
        local empty = buf:read_i8() == -1
        local namespace = FName(buf)

        local key, str = '', ''
        if not empty then
            key = FName(buf)
            str = FName(buf)
        end

        local out = base.newOrderedTable('Text', str)
        out._namespace = namespace
        out._key = key
        return out
    end)
end
parsers.TextProperty.readValue = function(buf, base)
    error(("TextProperty.readValue unimplemented! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end

parsers.DelegateProperty = {}
parsers.DelegateProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        local out = parsers.DelegateProperty.readValue(buf, base)
        out.__type = 'Delegate'
        return out
    end)
end
parsers.DelegateProperty.readValue = function(buf, base)
    local object = tonumber(buf:read_i32())
    local out = base.newOrderedTable('DelegateValue', base.names[tonumber(buf:read_u64())])
    out._object = object
    return out
end

parsers.MulticastDelegateProperty = {}
parsers.MulticastDelegateProperty.readProperty = function(buf, base, len)
    assert(buf:read_u8() == 0)
    return base:ensureLength(len, function()
        local out = parsers.MulticastDelegateProperty.readValue(buf, base)
        out.__type = 'MulticastDelegate'
        return out
    end)
end
parsers.MulticastDelegateProperty.readValue = function(buf, base)
    local num = tonumber(buf:read_u32())
    local out = base.newOrderedTable('MulticastDelegateValue')

    for i = 1, num do
        out[i] = parsers.DelegateProperty.readValue(buf, base)
    end

    return out
end

parsers.MulticastInlineDelegateProperty = {}
parsers.MulticastInlineDelegateProperty.readProperty = function(buf, base, len)
    local out = parsers.MulticastDelegateProperty.readProperty(buf, base, len)
    out.__type = 'MulticastInlineDelegate'
    return out
end
parsers.MulticastInlineDelegateProperty.readValue = function(buf, base)
    local out = parsers.MulticastDelegateProperty.readValue(buf, base)
    out.__type = 'MulticastInlineDelegateValue'
    return out
end

parsers.MulticastSparseDelegateProperty = {}
parsers.MulticastSparseDelegateProperty.readProperty = function(buf, base, len)
    local out = parsers.MulticastDelegateProperty.readProperty(buf, base, len)
    out.__type = 'MulticastSparseDelegate'
    return out
end
parsers.MulticastSparseDelegateProperty.readValue = function(buf, base)
    local out = parsers.MulticastDelegateProperty.readValue(buf, base)
    out.__type = 'MulticastSparseDelegateValue'
    return out
end


return parsers
