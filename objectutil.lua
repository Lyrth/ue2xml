
local xml = require './slaxdom'

local rawget, ipairs, tremove = rawget, ipairs, table.remove

local orderedTableMeta = {
    __newindex = function(t, k ,v)
        if not rawget(t._values, k) then -- new key 
            t._keys[#t._keys + 1] = k
        end
        if v == nil then -- delete key too.
            if t._values[k] ~= nil then
                for i, v2 in ipairs(t._keys) do
                    if v2 == k then
                        tremove(t._keys, i)
                        break
                    end
                end
                t._values[k] = nil
            end
        else -- update/store value
            t._values[k] = v
        end
    end,
    __len = function(t) return #t._keys end,
    __index = function(t, k)
        return rawget(t._values, k)
    end,
    __pairs = function(t)
        local i = 0
        return function()
            i = i + 1
            local key = t._keys[i]
            if key ~= nil then
                return key, t._values[key]
            end
        end
    end
}

local function newOrderedTable()
    return setmetatable({_keys = {}, _values = {}}, orderedTableMeta)
end


local type, tinsert, tostring, tonumber, pairs = type, table.insert, tostring, tonumber, pairs
local HUGE = math.huge

local function convertToDom(tb)
    if type(tb) == 'table' then
        local name = tb.__type or "UNKNOWN"
        local flat = tb.__flatten

        local attr = {}
        local kids = {}

        --name first
        if tb._name then
            tinsert(attr, {
                type = 'attribute',
                name = 'name',
                value = tostring(tb._name)
            })
            tb._name = nil
        end

        for k, v in pairs(tb) do
            if type(k) == 'string' and k:sub(1,1) == '_' and k:sub(2,2) ~= '_' then
                tinsert(attr, {
                    type = 'attribute',
                    name = k:sub(2),
                    value = tostring(v)
                })
            end
        end

        -- sequential ordering important
        for i = 1, HUGE do
            local v = tb[i]
            if v == nil then break end
            local d = convertToDom(v)
            if d.type == 'element' and d.__flatten then
                for _, child in ipairs(d.kids) do
                    tinsert(kids, child)
                end
            else
                tinsert(kids, d)
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

local function convertToXml(t)
    return xml:xml({
        type = 'document',
        name = '#doc',
        kids = { convertToDom(t) }
    }, { indent = 4 })
end


return {
    newOrderedTable = newOrderedTable,
    convertToDom = convertToDom,
    convertToXml = convertToXml,
}
