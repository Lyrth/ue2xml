--->use-luvit<---

--- Buffer v2

local ffi = require 'ffi'

local cast, typeof = ffi.cast, ffi.typeof
local assert, type, tbins, tbrem = assert, type, table.insert, table.remove

ffi.cdef [[
    void* malloc(size_t size);
    void free(void* mem);
    void* memset(void* ptr, int val, size_t n);
]]

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

local C = (ffi.os == 'Windows') and ffi.load('msvcrt') or ffi.C
local U = (ffi.os == 'Windows') and ffi.load('ucrtbase') or ffi.C

local i8, i16, i32, i64 = typeof 'int8_t', typeof 'int16_t', typeof 'int32_t', typeof 'int64_t'

local conv = {}

do
    local u16ptr, u32ptr, u64ptr = typeof 'uint16_t*', typeof 'uint32_t*', typeof 'uint64_t*'

    if ffi.abi('le') then
        conv.asLE16 = function(ptr) return cast(u16ptr, ptr)[0] end
        conv.asLE32 = function(ptr) return cast(u32ptr, ptr)[0] end
        conv.asLE64 = function(ptr) return cast(u64ptr, ptr)[0] end
        conv.fromLE16 = function(ptr, n) cast(u16ptr, ptr)[0] = n end
        conv.fromLE32 = function(ptr, n) cast(u32ptr, ptr)[0] = n end
        conv.fromLE64 = function(ptr, n) cast(u64ptr, ptr)[0] = n end
        conv.asBE16 = function(ptr) return U.bswap16(cast(u16ptr, ptr)[0]) end
        conv.asBE32 = function(ptr) return U.bswap32(cast(u32ptr, ptr)[0]) end
        conv.asBE64 = function(ptr) return U.bswap64(cast(u64ptr, ptr)[0]) end
        conv.fromBE16 = function(ptr, n) cast(u16ptr, ptr)[0] = U.bswap16(n) end
        conv.fromBE32 = function(ptr, n) cast(u32ptr, ptr)[0] = U.bswap32(n) end
        conv.fromBE64 = function(ptr, n) cast(u64ptr, ptr)[0] = U.bswap64(n) end
    else
        conv.asLE16 = function(ptr) return U.bswap16(cast(u16ptr, ptr)[0]) end
        conv.asLE32 = function(ptr) return U.bswap32(cast(u32ptr, ptr)[0]) end
        conv.asLE64 = function(ptr) return U.bswap64(cast(u64ptr, ptr)[0]) end
        conv.fromLE16 = function(ptr, n) cast(u16ptr, ptr)[0] = U.bswap16(n) end
        conv.fromLE32 = function(ptr, n) cast(u32ptr, ptr)[0] = U.bswap32(n) end
        conv.fromLE64 = function(ptr, n) cast(u64ptr, ptr)[0] = U.bswap64(n) end
        conv.asBE16 = function(ptr) return cast(u16ptr, ptr)[0] end
        conv.asBE32 = function(ptr) return cast(u32ptr, ptr)[0] end
        conv.asBE64 = function(ptr) return cast(u64ptr, ptr)[0] end
        conv.fromBE16 = function(ptr, n) cast(u16ptr, ptr)[0] = n end
        conv.fromBE32 = function(ptr, n) cast(u32ptr, ptr)[0] = n end
        conv.fromBE64 = function(ptr, n) cast(u64ptr, ptr)[0] = n end
    end
end

-- TODO make all cdecls into typeof return calls


---@alias endianness
---|>'"le"' # Little-endian
---| '"be"' # Big-endian

--- Byte buffer for sequential and 0-indexed reading/writing.
---@class ByteBuffer
---@field length integer  # Buffer length
---@field pos integer     # Position to read next
---@field mode endianness # Endianness of buffer reads/writes
---@field rw boolean    # Is the buffer also writable
---@field pos_stack integer[] # Position stack for push and pop operations
---@field ct ffi.cdata* # Cdata pointer to buffer memory
---@field _ct ffi.cdata* private
---@field _funcs table private
local ByteBuffer = {}

---@class ByteBuffer
local LEfn = {}

---@class ByteBuffer
local BEfn = {}


---@param self ByteBuffer
local function ByteBuffer__index(self, key)
    if type(key) == 'number' then
        assert(key >= 0 and key < self.length, "Index out of bounds")
        return self.ct[key]
    end
    return self._funcs[key] or ByteBuffer[key]
end


--- Create a new, empty buffer with size `length`.
---@return ByteBuffer
function ByteBuffer.new(length, options)
    assert(type(length) == 'number' and length >= 0, "length must be a positive integer.")
    options = options or {}

    ---@type ByteBuffer
    local self = setmetatable({}, {__index = ByteBuffer__index})
    self.mode = options.mode == 'be' and 'be' or 'le'
    self.rw = options.rw and true or false
    self.length = length
    self.pos = 0
    self.pos_stack = {}
    self._funcs = (self.mode == 'be') and BEfn or LEfn

    -- Keepalive field with type cdata<void *>, since ffi.cast
    -- doesn't keep source cdata (and gets garbage collected).
    -- Used for later realloc too, to detach the finalizer.
    -- TODO check if you could just cdef an alias with a different
    -- return type `uint8_t *`, to eliminate redundant cdata storage.
    self._ct = ffi.gc(C.malloc(self.length), C.free)

    -- the cdata of type cdata<uint8_t *> that gets actually used.
    self.ct = cast('uint8_t *', self._ct)

    if options.zerofill then
        ffi.fill(self.ct, self.length)
    end

    return self
end

function ByteBuffer.from(s, options)
    assert(type(s) == 'string', "s must be a string source.")
    local self = ByteBuffer.new(#s, options)

    ffi.copy(self.ct, s, self.length)

    return self
end


--- Other ---

function ByteBuffer:checkWrite()
    assert(self.rw, "Buffer is read-only, write operaions not supported.")
end


--- Position functions ---

--- Advance pos by `n`, returning current position before advance
function ByteBuffer:advance(n)
    local current = self.pos
    assert(current + n <= self.length, "Reached end of buffer.")
    self.pos = current + n
    return current
end

function ByteBuffer:push()
    tbins(self.pos_stack, self.pos)
    return self
end

function ByteBuffer:pop()
    ---@type integer
    self.pos = assert(tbrem(self.pos_stack), "Nothing to pop from position stack.")
    return self
end

---@param pos integer
function ByteBuffer:seek(pos)
    assert(type(pos) == 'number' or type(pos) == 'cdata', "pos must be an integer.")
    if pos < 0 then
        pos = self.length + pos
    end
    self.pos = pos
    return self
end


--- Read functions ---

local function complement8(n)
    return cast(i8, n)
end

local function complement16(n)
    return cast(i16, n)
end

local function complement32(n)
    -- weird things happen with casting directly to an int32_t
    return cast(i32, cast(i64, n))
end

local function complement64(n)
    return cast(i64, n)
end

--

function ByteBuffer:iter()
    return function()
        if self.pos < self.length then
            local pos = self:advance(1)
            return pos, self.ct[pos]
        end
    end
end

--

function LEfn:read_u8()
    return self.ct[self:advance(1)]
end
BEfn.read_u8 = LEfn.read_u8

function LEfn:read_i8()
    return complement8(self:read_u8())
end
BEfn.read_i8 = LEfn.read_i8

--

function LEfn:read_u16()
    return conv.asLE16(self.ct + self:advance(2))
end
function BEfn:read_u16()
    return conv.asBE16(self.ct + self:advance(2))
end

function LEfn:read_i16()
    return complement16(self:read_u16())
end
BEfn.read_i16 = LEfn.read_i16

--

function LEfn:read_u32()
    return conv.asLE32(self.ct + self:advance(4))
end
function BEfn:read_u32()
    return conv.asBE32(self.ct + self:advance(4))
end

function LEfn:read_i32()
    return complement32(self:read_u32())
end
BEfn.read_i32 = LEfn.read_i32

--

function LEfn:read_u64()
    return conv.asLE64(self.ct + self:advance(8))
end
function BEfn:read_u64()
    return conv.asBE64(self.ct + self:advance(8))
end

function LEfn:read_i64()
    return complement64(self:read_u64())
end
BEfn.read_i64 = LEfn.read_i64

--

local ffistr = ffi.string
function ByteBuffer:read_bytes(len)
    assert(type(len) == 'number' and len >= 0, "len must be a positive integer.")

    return ffistr(self.ct + self:advance(len), len)
end


--- Write functions ---

function LEfn:write_u8(val)
    self:checkWrite()
    self.ct[self:advance(1)] = val
    return self
end
BEfn.write_u8 = LEfn.write_u8

function LEfn:write_i8(val)
    self:checkWrite()
    self.ct[self:advance(1)] = val
    return self
end
BEfn.write_i8 = LEfn.write_u8

--

function LEfn:write_u16(val)
    self:checkWrite()
    conv.fromLE16(self.ct + self:advance(2), val)
    return self
end
function LEfn:write_i16(val)
    self:checkWrite()
    conv.fromLE16(self.ct + self:advance(2), val)
    return self
end

function BEfn:write_u16(val)
    self:checkWrite()
    conv.fromBE16(self.ct + self:advance(2), val)
    return self
end
BEfn.write_i16 = BEfn.write_u16

--

function LEfn:write_u32(val)
    self:checkWrite()
    conv.fromLE32(self.ct + self:advance(4), val)
    return self
end
function LEfn:write_i32(val)
    self:checkWrite()
    conv.fromLE32(self.ct + self:advance(4), val)
    return self
end

function BEfn:write_u32(val)
    self:checkWrite()
    conv.fromBE32(self.ct + self:advance(4), val)
    return self
end
BEfn.write_i32 = BEfn.write_u32

--

function LEfn:write_u64(val)
    self:checkWrite()
    conv.fromLE64(self.ct + self:advance(8), val)
    return self
end
function LEfn:write_i64(val)
    self:checkWrite()
    conv.fromLE64(self.ct + self:advance(8), val)
    return self
end

function BEfn:write_u64(val)
    self:checkWrite()
    conv.fromBE64(self.ct + self:advance(8), val)
    return self
end
BEfn.write_i64 = BEfn.write_u64

--

local fficopy = ffi.copy
function ByteBuffer:write_bytes(val)
    self:checkWrite()
    fficopy(self.ct + self:advance(#val), val)
    return self
end


return ByteBuffer
