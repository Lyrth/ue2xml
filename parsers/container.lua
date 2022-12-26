

---@type table<string, Parser>
local parsers = {}


local knownStructs = { Box = true, Box2D = true, Color = true, ColorMaterialInput = true, DateTime = true, ExpressionInput = true, FrameNumber = true, Guid = true, NavAgentSelector = true, SmartName = true, RichCurveKey = true, SimpleCurveKey = true, ScalarMaterialInput = true, ShadingModelMaterialInput = true, VectorMaterialInput = true, Vector2MaterialInput = true, MaterialAttributesInput = true, SkeletalMeshSamplingLODBuiltData = true, SkeletalMeshSamplingRegionBuiltData = true, PerPlatformBool = true, PerPlatformFloat = true, PerPlatformInt = true, PerQualityLevelInt = true, GameplayTagContainer = true, IntPoint = true, IntVector = true, LevelSequenceObjectReferenceMap = true, LinearColor = true, NiagaraVariable = true, NiagaraVariableBase = true, NiagaraVariableWithOffset = true, NiagaraDataInterfaceGPUParamInfo = true, MovieSceneEvalTemplatePtr = true, MovieSceneEvaluationFieldEntityTree = true, MovieSceneEvaluationKey = true, MovieSceneFloatChannel = true, MovieSceneFloatValue = true, MovieSceneFrameRange = true, MovieSceneSegment = true, MovieSceneSegmentIdentifier = true, MovieSceneSequenceID = true, MovieSceneTrackIdentifier = true, MovieSceneTrackImplementationPtr = true, FontData = true, FontCharacter = true, Plane = true, Quat = true, Rotator = true, SectionEvaluationDataTree = true, StringClassReference = true, SoftClassPath = true, StringAssetReference = true, SoftObjectPath = true, Timespan = true, UniqueNetIdRepl = true, Vector = true, Vector2D = true, Vector4 = true, Vector_NetQuantize = true, Vector_NetQuantize10 = true, Vector_NetQuantize100 = true, Vector_NetQuantizeNormal = true }


local function ResolveAsItem(base, buf, subclass, totalLen)
    if subclass == 'StructProperty' then
        local name = base.names[tonumber(buf:read_u64())]
        local class = base.names[tonumber(buf:read_u64())]
        assert(class == subclass)
        local thisLen = buf:read_u32(); buf:read_u32()  -- 0x35
        assert(thisLen == totalLen - 0x35)              -- 4b num, 8b name, 8b class, 8b thislen, 8b structclass, 1b 0, 16b 0
        local structType = base.names[tonumber(buf:read_u64())]
        assert(buf:read_u8() == 0)
        assert(buf:read_u64() == 0)
        assert(buf:read_u64() == 0)

        return 'StructProperty', 'Struct:'..structType, knownStructs[structType] and thisLen
    end
    return subclass, subclass
end

parsers.StructPropertyKnown = {}
-- TODO: for all of those structs
---@diagnostic disable-next-line: redundant-parameter
parsers.StructPropertyKnown.readValue = function(buf, base, len) return base:readRaw(len) end


parsers.StructProperty = {}
parsers.StructProperty.readProperty = function(buf, base, len)
    local structType = base.names[tonumber(buf:read_u64())]
    assert(buf:read_u64() == 0) -- flags 1?
    assert(buf:read_u64() == 0) -- flags 2?
    assert(buf:read_u8() == 0)

    return base:ensureLength(len, function()
        local out = base.newOrderedTable('Struct')
        out._subtype = structType
        if knownStructs[structType] then
            ---@diagnostic disable-next-line: redundant-parameter
            out[1] = parsers.StructPropertyKnown.readValue(buf, base, len)
        else
            out[1] = parsers.StructProperty.readValue(buf, base)
        end

        return out
    end)
end
parsers.StructProperty.readValue = function(buf, base)
    local out = base.newOrderedTable('StructValue')
    out.__flatten = true

    local i = 1
    for prop in base:readFields() do
        out[i] = prop
        i = i + 1
    end

    -- special case for niagara: extra zeroes
    if base.hasStructExtraFrom then
        out[i] = base.newOrderedTable('__StructExtra', tonumber(buf:read_u32()))
        out[i]._from = base.hasStructExtraFrom
        base.hasStructExtraFrom = nil
    end

    return out
end

parsers.ArrayProperty = {}
parsers.ArrayProperty.readProperty = function(buf, base, len)
    local subclass = base.names[tonumber(buf:read_u64())]
    subclass = base:checkClass(subclass)
    assert(buf:read_u8() == 0)

    return base:ensureLength(len, function()
        local num = buf:read_u32()

        local subtype, knownLen
        subclass, subtype, knownLen = ResolveAsItem(base, buf, subclass, len)

        local out = base.newOrderedTable('Array')
        out._subtype = subtype
        if knownLen then
            out._count = num
            out[1] = parsers.StructPropertyKnown.readValue(buf, base, knownLen)
        else
            for i = 1, num do
                out[i] = base.newOrderedTable('ArrayItem', base.parsers[subclass].readValue(buf, base))
            end
        end

        return out
    end)
end
parsers.ArrayProperty.readValue = function(buf, base)
    error(("ArrayProperty.readValue unimplemented! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end

parsers.SetProperty = {}
parsers.SetProperty.readProperty = function(buf, base, len)
    local subclass = base.names[tonumber(buf:read_u64())]
    subclass = base:checkClass(subclass)
    assert(buf:read_u8() == 0)

    return base:ensureLength(len, function()
        assert(buf:read_u32() == 0)
        local num = buf:read_u32()

        local subtype, knownLen
        subclass, subtype, knownLen = ResolveAsItem(base, buf, subclass, len)

        local out = base.newOrderedTable('Set')
        out._subtype = subtype
        if knownLen then
            out._count = num
            out[1] = parsers.StructPropertyKnown.readValue(buf, base, knownLen)
        else
            for i = 1, num do
                out[i] = base.newOrderedTable('SetItem', base.parsers[subclass].readValue(buf, base))
            end
        end

        return out
    end)
end
parsers.SetProperty.readValue = function(buf, base)
    error(("SetProperty.readValue unimplemented! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end

-- parsers.MapProperty = {}
-- parsers.MapProperty.readProperty = function(buf, base, len)
--     local keyClass = base.names[tonumber(buf:read_u64())]
--     local valClass = base.names[tonumber(buf:read_u64())]
--     keyClass = base:checkClass(keyClass)
--     valClass = base:checkClass(valClass)
--     assert(buf:read_u8() == 0)

--     return base:ensureLength(len, function()
--         assert(buf:read_u32() == 0)
--         local num = buf:read_u32()

--         local keySubtype, valSubtype = nil, nil
--         keyClass, keySubtype = ResolveAsItem(base, buf, keyClass, len)
--         valClass, valSubtype = ResolveAsItem(base, buf, valClass, len)

--         local out = base.newOrderedTable('Map')
--         out._keyClass = keySubtype
--         out._valClass = valSubtype

--         for i = 1, num do
--             out[i] = base.newOrderedTable('MapItem',
--                 base.newOrderedTable('Key', base.parsers[keyClass].readValue(buf, base)),
--                 base.newOrderedTable('Value', base.parsers[valClass].readValue(buf, base))
--             )
--         end

--         return out
--     end)
-- end
-- parsers.MapProperty.readValue = function(buf, base)
--     error(("SetProperty.readValue unimplemented! at: %s"):format(
--         bit.tohex(buf.pos, 8)
--     ))
-- end

parsers.MapProperty = {}
parsers.MapProperty.readProperty = function(buf, base, len)
    local keyClass = base.names[tonumber(buf:read_u64())]
    local valClass = base.names[tonumber(buf:read_u64())]
    keyClass = base:checkClass(keyClass)
    valClass = base:checkClass(valClass)
    assert(buf:read_u8() == 0)

    return base:ensureLength(len, function()
        assert(buf:read_u32() == 0)
        local num = buf:read_u32()

        local out = base.newOrderedTable('Map')
        out._keyClass = keyClass
        out._valClass = valClass

        -- TODO: if not valid field then do plain data
        for i = 1, num do
            out[i] = base.newOrderedTable('MapItem',
                base.newOrderedTable('Key', base.parsers[keyClass].readValue(buf, base)),
                base.newOrderedTable('Value', base.parsers[valClass].readValue(buf, base))
            )
        end

        return out
    end)
end
parsers.MapProperty.readValue = function(buf, base)
    error(("SetProperty.readValue unimplemented! at: %s"):format(
        bit.tohex(buf.pos, 8)
    ))
end


return parsers
