--[[

Some small UTF-8 <-> UTF-16 converter utility. Only tested/works on Windows tho.

Author: Lyrthras <https://github.com/Lyrth, me[at]lyr.pw>

--]]


local ffi = require 'ffi'

if not ffi.abi 'le' then error("This script wasn't coded for big-endian machines.") end

if ffi.abi '64bit' then
    ffi.cdef 'typedef int64_t ssize_t'
else
    ffi.cdef 'typedef int32t ssize_t'
end

if ffi.abi 'win' then
    ffi.cdef [[
        typedef struct _Mbstatet {
            unsigned long _Wchar;
            unsigned short _Byte, _State;
        } _Mbstatet;
        typedef _Mbstatet mbstate_t;
    ]]
else
    ffi.cdef [[
        typedef struct {
            int __count;
            union {
                int32_t __wch;
                char __wchb[4];
            } __value;          /* Value so far.  */
        } __mbstate_t;
        typedef __mbstate_t mbstate_t;
    ]]
end

ffi.cdef [[
    typedef uint16_t char16_t;

    size_t c16rtomb(char *mbchar, char16_t wchar, mbstate_t *state);
    size_t mbrtoc16(char16_t* destination, const char* source, size_t max_bytes, mbstate_t* state);
]]
local C = ffi.abi 'win' and ffi.load 'ucrtbase' or ffi.C

local function utf8ToUtf16(str)
    local n = #str

    local state = ffi.new('mbstate_t')
    local sptr = ffi.cast('const char*', str)
    local out = ffi.new('char16_t[?]', n + 1) -- TODO malloc
    local soff = 0
    local outlen = n

    for i = 0, n-1 do
        local ret = C.mbrtoc16(out + i, sptr + soff, n - soff, state)
        ret = ffi.cast('ssize_t', ret)

        if ret > 0 then
            soff = soff + ret
        elseif ret == 0 then
            -- skip single null; TODO non-conformant C0 80 null?
            soff = soff + 1
        elseif ret == -3 then
            -- continue
        else
            outlen = i
            break
        end
        if soff >= n then
            outlen = i + 1
            break
        end
    end

    return ffi.string(ffi.cast('unsigned char*', out), outlen * 2)
end

local function utf16ToUtf8(str)
    local n = #str
    assert(n % 2 == 0, "bad UTF-16 string length")
    local nh = n / 2

    local state = ffi.new('mbstate_t')
    local sptr = ffi.cast('const char16_t*', str)
    local out = ffi.new('char[?]', n*2 + 1)
    local outoff = 0

    for i = 0, nh-1 do
        local ret = C.c16rtomb(out + outoff, sptr[i], state)
        ret = ffi.cast('ssize_t', ret)

        if ret >= 0 then
            outoff = outoff + ret
        else
            break
        end
    end

    return ffi.string(out, outoff)
end


return {
    utf8ToUtf16 = utf8ToUtf16,
    utf16ToUtf8 = utf16ToUtf8,
}
