

---@type table<string, Parser>
local parsers = {}


-- FNiagaraTypeDefinition

parsers.ClassStructOrEnum = {}
parsers.ClassStructOrEnum.readProperty = function(buf, base, len)
    -- weird case: length comes after an option
    buf:advance(-8)

    local subclass = base.names[tonumber(buf:read_u64())]
    subclass = base:checkClass(subclass)

    len = buf:read_u32(); buf:read_u32()
    assert(buf:read_u8() == 0)

    return base:ensureLength(len, function()
        base.hasStructExtraFrom = 'ClassStructOrEnum'
        local out = base.newOrderedTable('ClassStructOrEnum', base.parsers[subclass].readValue(buf, base))
        out._subtype = subclass

        return out
    end)
end
parsers.ClassStructOrEnum.readValue = function(buf, base)
    error(("ClassStructOrEnum.readValue unimplemented! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end


return parsers
