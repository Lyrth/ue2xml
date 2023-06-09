--- use-luvit

local ffi = require 'ffi'
local bit = require 'bit'

local band, bxor, bnot, brsh = bit.band, bit.bxor, bit.bnot, bit.rshift


--- uint32_t is slow, luajit recommends int32_t
local CRCTable_IStr = ffi.new('const int32_t[256]', {
    0x00000000LL, 0x04C11DB7LL, 0x09823B6ELL, 0x0D4326D9LL, 0x130476DCLL, 0x17C56B6BLL, 0x1A864DB2LL, 0x1E475005LL, 0x2608EDB8LL, 0x22C9F00FLL, 0x2F8AD6D6LL, 0x2B4BCB61LL, 0x350C9B64LL, 0x31CD86D3LL, 0x3C8EA00ALL, 0x384FBDBDLL,
    0x4C11DB70LL, 0x48D0C6C7LL, 0x4593E01ELL, 0x4152FDA9LL, 0x5F15ADACLL, 0x5BD4B01BLL, 0x569796C2LL, 0x52568B75LL, 0x6A1936C8LL, 0x6ED82B7FLL, 0x639B0DA6LL, 0x675A1011LL, 0x791D4014LL, 0x7DDC5DA3LL, 0x709F7B7ALL, 0x745E66CDLL,
    0x9823B6E0LL, 0x9CE2AB57LL, 0x91A18D8ELL, 0x95609039LL, 0x8B27C03CLL, 0x8FE6DD8BLL, 0x82A5FB52LL, 0x8664E6E5LL, 0xBE2B5B58LL, 0xBAEA46EFLL, 0xB7A96036LL, 0xB3687D81LL, 0xAD2F2D84LL, 0xA9EE3033LL, 0xA4AD16EALL, 0xA06C0B5DLL,
    0xD4326D90LL, 0xD0F37027LL, 0xDDB056FELL, 0xD9714B49LL, 0xC7361B4CLL, 0xC3F706FBLL, 0xCEB42022LL, 0xCA753D95LL, 0xF23A8028LL, 0xF6FB9D9FLL, 0xFBB8BB46LL, 0xFF79A6F1LL, 0xE13EF6F4LL, 0xE5FFEB43LL, 0xE8BCCD9ALL, 0xEC7DD02DLL,
    0x34867077LL, 0x30476DC0LL, 0x3D044B19LL, 0x39C556AELL, 0x278206ABLL, 0x23431B1CLL, 0x2E003DC5LL, 0x2AC12072LL, 0x128E9DCFLL, 0x164F8078LL, 0x1B0CA6A1LL, 0x1FCDBB16LL, 0x018AEB13LL, 0x054BF6A4LL, 0x0808D07DLL, 0x0CC9CDCALL,
    0x7897AB07LL, 0x7C56B6B0LL, 0x71159069LL, 0x75D48DDELL, 0x6B93DDDBLL, 0x6F52C06CLL, 0x6211E6B5LL, 0x66D0FB02LL, 0x5E9F46BFLL, 0x5A5E5B08LL, 0x571D7DD1LL, 0x53DC6066LL, 0x4D9B3063LL, 0x495A2DD4LL, 0x44190B0DLL, 0x40D816BALL,
    0xACA5C697LL, 0xA864DB20LL, 0xA527FDF9LL, 0xA1E6E04ELL, 0xBFA1B04BLL, 0xBB60ADFCLL, 0xB6238B25LL, 0xB2E29692LL, 0x8AAD2B2FLL, 0x8E6C3698LL, 0x832F1041LL, 0x87EE0DF6LL, 0x99A95DF3LL, 0x9D684044LL, 0x902B669DLL, 0x94EA7B2ALL,
    0xE0B41DE7LL, 0xE4750050LL, 0xE9362689LL, 0xEDF73B3ELL, 0xF3B06B3BLL, 0xF771768CLL, 0xFA325055LL, 0xFEF34DE2LL, 0xC6BCF05FLL, 0xC27DEDE8LL, 0xCF3ECB31LL, 0xCBFFD686LL, 0xD5B88683LL, 0xD1799B34LL, 0xDC3ABDEDLL, 0xD8FBA05ALL,
    0x690CE0EELL, 0x6DCDFD59LL, 0x608EDB80LL, 0x644FC637LL, 0x7A089632LL, 0x7EC98B85LL, 0x738AAD5CLL, 0x774BB0EBLL, 0x4F040D56LL, 0x4BC510E1LL, 0x46863638LL, 0x42472B8FLL, 0x5C007B8ALL, 0x58C1663DLL, 0x558240E4LL, 0x51435D53LL,
    0x251D3B9ELL, 0x21DC2629LL, 0x2C9F00F0LL, 0x285E1D47LL, 0x36194D42LL, 0x32D850F5LL, 0x3F9B762CLL, 0x3B5A6B9BLL, 0x0315D626LL, 0x07D4CB91LL, 0x0A97ED48LL, 0x0E56F0FFLL, 0x1011A0FALL, 0x14D0BD4DLL, 0x19939B94LL, 0x1D528623LL,
    0xF12F560ELL, 0xF5EE4BB9LL, 0xF8AD6D60LL, 0xFC6C70D7LL, 0xE22B20D2LL, 0xE6EA3D65LL, 0xEBA91BBCLL, 0xEF68060BLL, 0xD727BBB6LL, 0xD3E6A601LL, 0xDEA580D8LL, 0xDA649D6FLL, 0xC423CD6ALL, 0xC0E2D0DDLL, 0xCDA1F604LL, 0xC960EBB3LL,
    0xBD3E8D7ELL, 0xB9FF90C9LL, 0xB4BCB610LL, 0xB07DABA7LL, 0xAE3AFBA2LL, 0xAAFBE615LL, 0xA7B8C0CCLL, 0xA379DD7BLL, 0x9B3660C6LL, 0x9FF77D71LL, 0x92B45BA8LL, 0x9675461FLL, 0x8832161ALL, 0x8CF30BADLL, 0x81B02D74LL, 0x857130C3LL,
    0x5D8A9099LL, 0x594B8D2ELL, 0x5408ABF7LL, 0x50C9B640LL, 0x4E8EE645LL, 0x4A4FFBF2LL, 0x470CDD2BLL, 0x43CDC09CLL, 0x7B827D21LL, 0x7F436096LL, 0x7200464FLL, 0x76C15BF8LL, 0x68860BFDLL, 0x6C47164ALL, 0x61043093LL, 0x65C52D24LL,
    0x119B4BE9LL, 0x155A565ELL, 0x18197087LL, 0x1CD86D30LL, 0x029F3D35LL, 0x065E2082LL, 0x0B1D065BLL, 0x0FDC1BECLL, 0x3793A651LL, 0x3352BBE6LL, 0x3E119D3FLL, 0x3AD08088LL, 0x2497D08DLL, 0x2056CD3ALL, 0x2D15EBE3LL, 0x29D4F654LL,
    0xC5A92679LL, 0xC1683BCELL, 0xCC2B1D17LL, 0xC8EA00A0LL, 0xD6AD50A5LL, 0xD26C4D12LL, 0xDF2F6BCBLL, 0xDBEE767CLL, 0xE3A1CBC1LL, 0xE760D676LL, 0xEA23F0AFLL, 0xEEE2ED18LL, 0xF0A5BD1DLL, 0xF464A0AALL, 0xF9278673LL, 0xFDE69BC4LL,
    0x89B8FD09LL, 0x8D79E0BELL, 0x803AC667LL, 0x84FBDBD0LL, 0x9ABC8BD5LL, 0x9E7D9662LL, 0x933EB0BBLL, 0x97FFAD0CLL, 0xAFB010B1LL, 0xAB710D06LL, 0xA6322BDFLL, 0xA2F33668LL, 0xBCB4666DLL, 0xB8757BDALL, 0xB5365D03LL, 0xB1F740B4LL,
})

local CRCTable_Str = ffi.new('const int32_t[256]', {
    0x00000000LL, 0x77073096LL, 0xee0e612cLL, 0x990951baLL, 0x076dc419LL, 0x706af48fLL, 0xe963a535LL, 0x9e6495a3LL, 0x0edb8832LL, 0x79dcb8a4LL, 0xe0d5e91eLL, 0x97d2d988LL, 0x09b64c2bLL, 0x7eb17cbdLL, 0xe7b82d07LL, 0x90bf1d91LL,
    0x1db71064LL, 0x6ab020f2LL, 0xf3b97148LL, 0x84be41deLL, 0x1adad47dLL, 0x6ddde4ebLL, 0xf4d4b551LL, 0x83d385c7LL, 0x136c9856LL, 0x646ba8c0LL, 0xfd62f97aLL, 0x8a65c9ecLL, 0x14015c4fLL, 0x63066cd9LL, 0xfa0f3d63LL, 0x8d080df5LL,
    0x3b6e20c8LL, 0x4c69105eLL, 0xd56041e4LL, 0xa2677172LL, 0x3c03e4d1LL, 0x4b04d447LL, 0xd20d85fdLL, 0xa50ab56bLL, 0x35b5a8faLL, 0x42b2986cLL, 0xdbbbc9d6LL, 0xacbcf940LL, 0x32d86ce3LL, 0x45df5c75LL, 0xdcd60dcfLL, 0xabd13d59LL,
    0x26d930acLL, 0x51de003aLL, 0xc8d75180LL, 0xbfd06116LL, 0x21b4f4b5LL, 0x56b3c423LL, 0xcfba9599LL, 0xb8bda50fLL, 0x2802b89eLL, 0x5f058808LL, 0xc60cd9b2LL, 0xb10be924LL, 0x2f6f7c87LL, 0x58684c11LL, 0xc1611dabLL, 0xb6662d3dLL,
    0x76dc4190LL, 0x01db7106LL, 0x98d220bcLL, 0xefd5102aLL, 0x71b18589LL, 0x06b6b51fLL, 0x9fbfe4a5LL, 0xe8b8d433LL, 0x7807c9a2LL, 0x0f00f934LL, 0x9609a88eLL, 0xe10e9818LL, 0x7f6a0dbbLL, 0x086d3d2dLL, 0x91646c97LL, 0xe6635c01LL,
    0x6b6b51f4LL, 0x1c6c6162LL, 0x856530d8LL, 0xf262004eLL, 0x6c0695edLL, 0x1b01a57bLL, 0x8208f4c1LL, 0xf50fc457LL, 0x65b0d9c6LL, 0x12b7e950LL, 0x8bbeb8eaLL, 0xfcb9887cLL, 0x62dd1ddfLL, 0x15da2d49LL, 0x8cd37cf3LL, 0xfbd44c65LL,
    0x4db26158LL, 0x3ab551ceLL, 0xa3bc0074LL, 0xd4bb30e2LL, 0x4adfa541LL, 0x3dd895d7LL, 0xa4d1c46dLL, 0xd3d6f4fbLL, 0x4369e96aLL, 0x346ed9fcLL, 0xad678846LL, 0xda60b8d0LL, 0x44042d73LL, 0x33031de5LL, 0xaa0a4c5fLL, 0xdd0d7cc9LL,
    0x5005713cLL, 0x270241aaLL, 0xbe0b1010LL, 0xc90c2086LL, 0x5768b525LL, 0x206f85b3LL, 0xb966d409LL, 0xce61e49fLL, 0x5edef90eLL, 0x29d9c998LL, 0xb0d09822LL, 0xc7d7a8b4LL, 0x59b33d17LL, 0x2eb40d81LL, 0xb7bd5c3bLL, 0xc0ba6cadLL,
    0xedb88320LL, 0x9abfb3b6LL, 0x03b6e20cLL, 0x74b1d29aLL, 0xead54739LL, 0x9dd277afLL, 0x04db2615LL, 0x73dc1683LL, 0xe3630b12LL, 0x94643b84LL, 0x0d6d6a3eLL, 0x7a6a5aa8LL, 0xe40ecf0bLL, 0x9309ff9dLL, 0x0a00ae27LL, 0x7d079eb1LL,
    0xf00f9344LL, 0x8708a3d2LL, 0x1e01f268LL, 0x6906c2feLL, 0xf762575dLL, 0x806567cbLL, 0x196c3671LL, 0x6e6b06e7LL, 0xfed41b76LL, 0x89d32be0LL, 0x10da7a5aLL, 0x67dd4accLL, 0xf9b9df6fLL, 0x8ebeeff9LL, 0x17b7be43LL, 0x60b08ed5LL,
    0xd6d6a3e8LL, 0xa1d1937eLL, 0x38d8c2c4LL, 0x4fdff252LL, 0xd1bb67f1LL, 0xa6bc5767LL, 0x3fb506ddLL, 0x48b2364bLL, 0xd80d2bdaLL, 0xaf0a1b4cLL, 0x36034af6LL, 0x41047a60LL, 0xdf60efc3LL, 0xa867df55LL, 0x316e8eefLL, 0x4669be79LL,
    0xcb61b38cLL, 0xbc66831aLL, 0x256fd2a0LL, 0x5268e236LL, 0xcc0c7795LL, 0xbb0b4703LL, 0x220216b9LL, 0x5505262fLL, 0xc5ba3bbeLL, 0xb2bd0b28LL, 0x2bb45a92LL, 0x5cb36a04LL, 0xc2d7ffa7LL, 0xb5d0cf31LL, 0x2cd99e8bLL, 0x5bdeae1dLL,
    0x9b64c2b0LL, 0xec63f226LL, 0x756aa39cLL, 0x026d930aLL, 0x9c0906a9LL, 0xeb0e363fLL, 0x72076785LL, 0x05005713LL, 0x95bf4a82LL, 0xe2b87a14LL, 0x7bb12baeLL, 0x0cb61b38LL, 0x92d28e9bLL, 0xe5d5be0dLL, 0x7cdcefb7LL, 0x0bdbdf21LL,
    0x86d3d2d4LL, 0xf1d4e242LL, 0x68ddb3f8LL, 0x1fda836eLL, 0x81be16cdLL, 0xf6b9265bLL, 0x6fb077e1LL, 0x18b74777LL, 0x88085ae6LL, 0xff0f6a70LL, 0x66063bcaLL, 0x11010b5cLL, 0x8f659effLL, 0xf862ae69LL, 0x616bffd3LL, 0x166ccf45LL,
    0xa00ae278LL, 0xd70dd2eeLL, 0x4e048354LL, 0x3903b3c2LL, 0xa7672661LL, 0xd06016f7LL, 0x4969474dLL, 0x3e6e77dbLL, 0xaed16a4aLL, 0xd9d65adcLL, 0x40df0b66LL, 0x37d83bf0LL, 0xa9bcae53LL, 0xdebb9ec5LL, 0x47b2cf7fLL, 0x30b5ffe9LL,
    0xbdbdf21cLL, 0xcabac28aLL, 0x53b39330LL, 0x24b4a3a6LL, 0xbad03605LL, 0xcdd70693LL, 0x54de5729LL, 0x23d967bfLL, 0xb3667a2eLL, 0xc4614ab8LL, 0x5d681b02LL, 0x2a6f2b94LL, 0xb40bbe37LL, 0xc30c8ea1LL, 0x5a05df1bLL, 0x2d02ef8dLL,
})



--- return FCrc::Strihash_DEPRECATED(Source) & 0xFFFF;
--- Don't include the null terminator btw.
---@param str string
---@return number
local function RawNonCasePreservingHash(str)
    str = str:upper()
    local lim = #str - 1
    local buf = ffi.cast('const uint8_t*', str)
    local crc = 0LL
    for i = 0, lim do
        crc = bxor(band(brsh(crc, 8), 0x00FFFFFF), CRCTable_IStr[band(bxor(crc, buf[i]), 0xFF)])
    end
    return tonumber(band(crc, 0xFFFF))
end


--- FCrc::StrCrc32(Source) & 0xFFFF
--- Don't include the null terminator btw.
--- Surely we won't encounter UTF16 names in the names table.....right?
---@param str string
---@return number
local function RawCasePreservingHash(str)
    local lim = #str - 1
    local buf = ffi.cast('const uint8_t*', str)
    local crc = bnot(0LL)
    for i = 0, lim do
        crc = bxor(band(brsh(crc, 8), 0x00FFFFFF), CRCTable_Str[band(bxor(crc, buf[i]), 0xFF)])
        crc = bxor(band(brsh(crc, 8), 0x00FFFFFF), CRCTable_Str[band(     crc         , 0xFF)])
        crc = bxor(band(brsh(crc, 8), 0x00FFFFFF), CRCTable_Str[band(     crc         , 0xFF)])
        crc = bxor(band(brsh(crc, 8), 0x00FFFFFF), CRCTable_Str[band(     crc         , 0xFF)])
    end
    return tonumber(band(bnot(crc), 0xFFFF))
end


return {
    RawNonCasePreservingHash = RawNonCasePreservingHash,
    RawCasePreservingHash = RawCasePreservingHash
}
