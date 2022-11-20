
local FILE = 'analyze/CreditsDataTable.uasset'


local fs = require 'fs'
local bit = require 'bit'

local ByteBuffer = require './bytebuffer'
local readUasset = require './uassetreader'
local baseread = require './baseread'
local objectutil = require './objectutil'


---@type ByteBuffer
local uasset = ByteBuffer.from(assert(fs.readFileSync(FILE)))
local uexp = ByteBuffer.from(assert(fs.readFileSync(FILE:gsub("%.uasset", "%.uexp"))))

local head = readUasset(uasset)

do
    local fd = assert(fs.openSync(FILE:gsub("%.uasset", "%.summary%.txt"), 'w'))
    local function out(t)
        fs.writeSync(fd, nil, (t or '')..'\n')
    end

    local function getObj(t)
        if t.type == 'Export' then
            return head.exports[t.index]
        elseif t.type == 'Import' then
            return head.imports[t.index]
        else -- root
            return {
                objectName = "",
                className = "Root"
            }
        end
    end

    out()
    out("===== NAMES =====")
    for i = 0, #head.names do
        out(("% 4d %s\t%s"):format(i, bit.tohex(i, 4), head.names[i]))
    end

    out()
    out("===== EXPORTS =====")
    for i = 0, #head.exports do
        local class = getObj(head.exports[i].class)
        local outer = getObj(head.exports[i].outer)
        out(("% 4d %s\t[%s] %s @ %s #%s \t: [%s] %s"):format(i, bit.tohex(i, 4), class.objectName, head.exports[i].objectName, bit.tohex(head.exports[i].serialOffset - head.summary.totalHeaderSize, 8), bit.tohex(head.exports[i].serialSize, 8), outer.className or '', outer.objectName))
    end

    out()
    out("===== IMPORTS =====")
    for i = 0, #head.imports do
        local outer = getObj(head.imports[i].outer)
        out(("% 4d %s\t[%s] %s\t: [%s] %s"):format(i, bit.tohex(i, 4), head.imports[i].className, head.imports[i].objectName, outer.className, outer.objectName))
    end

    fs.closeSync(fd)
end

local exportData = baseread.parseExports(uexp, head.names, head.importNames, head.exportNames, head.exports, head.summary.totalHeaderSize)

fs.writeFileSync(FILE:gsub("%.uasset", "%.uexp")..".xml", objectutil.convertToXml(exportData))

