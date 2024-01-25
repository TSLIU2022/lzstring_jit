-- LZString for Lua
--
local _M = { _VERSION = "0.1" }
-- local mt = { __index = _M }

local bit = require("bit")
local utf8 = require("utf8")

local keyStrBase64  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
local keyStrUriSafe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"

-- 返回参数字符集中特定字符的索引值
local function createBaseReverseDic(keyStr)
    local baseReverseDic = {}
    -- baseReverseDic[ keyStr:sub(i, i)] = i 表达更简单，但在大规模调用下可能性能会差些
    for i = 0, string.len(keyStr) - 1, 1 do
        baseReverseDic[ string.char(string.byte(keyStr, i+1)) ] = i
    end

    return baseReverseDic
end

-- 获取 Base64 字符集中特定字符的索引值
local baseReverseDic_keyStrBase64  = createBaseReverseDic(keyStrBase64)

-- 获取 URL 安全字符集中特定字符的索引值
local baseReverseDic_keyStrUriSafe = createBaseReverseDic(keyStrUriSafe)

-- 根据 bitsPerChar 的值计算 context 的长度
local function get_uncompressed_length(context, bitsPerChar)
    local length
    -- bitsPerChar 等于 6：这意味着每个字符使用 6 位二进制数进行编码。这种编码方式通常用于传统的 ASCII 字符集，其中每个字符使用 7 位二进制数（即 1 个字节）进行编码。在这种情况下，我们可以使用 Lua 字符串操作函数（如 string.len）来计算字符串的长度。
    if bitsPerChar == 6 then
        length = string.len(context)
    end
    -- bitsPerChar 等于 15 或 16：这意味着每个字符使用 15 或 16 位二进制数进行编码。这种编码方式通常用于 UTF-16 编码的 Unicode 字符集，其中每个字符使用 2 个字节或 4 个字节进行编码。在这种情况下，我们需要使用 utf8.len 函数来计算字符串中 UTF-8 编码字符的数量。
    if bitsPerChar == 15 or bitsPerChar == 16 then
        length =utf8.len(context)
    end

    return length
end

local function get_char_from_uncompressed(context, bitsPerChar, i)
    local context_c
    if bitsPerChar == 15 or bitsPerChar == 16 then
        context_c =  utf8.sub(context, i+1, i+1)
    else
        context_c = string.char(string.byte(context, i+1))
    end
    return context_c
end

-- 根据给定的 bitsPerChar 参数，从输入的字符串 context 中获取字符的值。bitsPerChar 参数表示每个字符所使用的位数，可以是 6、15 或 16
local function get_char_value(context, bitsPerChar)
    if bitsPerChar == 6 then
        -- return string.byte(context)
        return string.byte(context,1)
    end

    if bitsPerChar == 15 or bitsPerChar == 16 then
        return utf8.byte(context, 0, 1)
    end
end

local function table_remove(table, key)
    local ret_table={}
    for k,v in pairs(table) do
        if k ~= key then
            ret_table[k]=v
        end
    end
    return ret_table
end

local function _compress(uncompressedStr, bitsPerChar, getCharFromInt)
    if not uncompressedStr or uncompressedStr == '' then
        return ""
    end

    local length
    local value
    local context_dictionary = {}   -- 用于存储上下文字典的表
    local context_dictionaryToCreate = {}  -- 用于存储需要创建的上下文字典的表
    local context_c
    local context_wc  -- 上下文字符串
    local context_w=''  -- 当前处理的字符
    local context_enlargeIn = 2  -- 用于控制字典扩展的变量
    local context_dictSize = 3  -- 字典的大小
    local context_numBits = 2   -- 当前使用的位数
    local context_data = {}     -- 用于存储压缩后的数据的字符串
    local context_data_val = 0  -- 用于存储压缩后的数据的变量
    local context_data_position = 0  -- 用于表示 context_data_val 中的位置

    length = get_uncompressed_length(uncompressedStr, bitsPerChar)

    for  i = 0, length-1, 1  do
        -- 构建压缩字典，如果 context_dictionary 不存在该字符则进行创建
        context_c = get_char_from_uncompressed(uncompressedStr, bitsPerChar, i)

        if not context_dictionary[ context_c ] then
            context_dictionary[ context_c ] = context_dictSize
            context_dictSize = context_dictSize + 1
            context_dictionaryToCreate[ context_c ] = 1
        end

        context_wc = context_w..context_c

        if context_dictionary[ context_wc ] then
            context_w = context_wc
        else
            if context_dictionaryToCreate[ context_w ] then
                if  get_char_value(context_w, bitsPerChar) < 256 then
                    for j = 0, context_numBits-1, 1 do
                        context_data_val = bit.lshift(context_data_val, 1)
                        if context_data_position == bitsPerChar - 1 then
                            context_data_position = 0
                            -- context_data = context_data..getCharFromInt(context_data_val)
                            table.insert(context_data, getCharFromInt(context_data_val))
                            context_data_val = 0
                        else
                            context_data_position = context_data_position + 1
                        end
                    end

                    value = get_char_value(context_w, bitsPerChar)

                    for j = 0, 8-1, 1 do
                        context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
                        if context_data_position == bitsPerChar -1 then
                            context_data_position = 0
                            -- context_data = context_data..getCharFromInt(context_data_val)
                            table.insert(context_data, getCharFromInt(context_data_val))
                            context_data_val = 0
                        else
                            context_data_position = context_data_position + 1
                        end
                        value = bit.arshift(value, 1)
                    end
                else
                    value = 1
                    for j = 0, context_numBits-1, 1 do
                        context_data_val = bit.bor(bit.lshift(context_data_val, 1), value)
                        if context_data_position == bitsPerChar - 1 then
                            context_data_position = 0
                            -- context_data = context_data..getCharFromInt(context_data_val)
                            table.insert(context_data, getCharFromInt(context_data_val))
                            context_data_val = 0
                        else
                            context_data_position = context_data_position + 1
                        end
                        value = 0
                    end

                    value = get_char_value(context_w, bitsPerChar)

                    for j = 0, 16-1, 1 do
                        context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
                        if context_data_position == bitsPerChar -1 then
                            context_data_position = 0
                            -- context_data = context_data..getCharFromInt(context_data_val)
                            table.insert(context_data, getCharFromInt(context_data_val))
                            context_data_val = 0
                        else
                            context_data_position = context_data_position + 1
                        end
                        value = bit.arshift(value, 1)
                    end
                end

                context_enlargeIn=context_enlargeIn - 1
                if context_enlargeIn == 0 then
                    context_enlargeIn = 2^context_numBits
                    context_numBits = context_numBits + 1
                end
                context_dictionaryToCreate = table_remove(context_dictionaryToCreate, context_w)
                -- context_dictionaryToCreate[context_w] = nil
            else
                value = context_dictionary[context_w]
                for j = 0, context_numBits-1, 1 do
                    context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
                    if context_data_position == bitsPerChar -1 then
                        context_data_position = 0
                        -- context_data = context_data..getCharFromInt(context_data_val)
                        table.insert(context_data, getCharFromInt(context_data_val))
                        context_data_val = 0
                    else
                        context_data_position = context_data_position + 1
                    end
                    value = bit.arshift(value, 1)
                end
            end
            context_enlargeIn = context_enlargeIn - 1
            if context_enlargeIn == 0 then
                context_enlargeIn = 2 ^ context_numBits
                context_numBits = context_numBits + 1
            end
            -- Add wc to the dictionary
            context_dictionary[context_wc] = context_dictSize
            context_dictSize = context_dictSize + 1
            context_w = context_c
        end

    end

     -- Output the code for w.
    -- if context_w and context_wc ~= '' then
    if string.len(context_w) ~= 0 then
        if context_dictionaryToCreate[context_w] then
            if get_char_value(context_w, bitsPerChar) < 256 then
                for i = 0, context_numBits-1 ,1 do
                    context_data_val = bit.lshift(context_data_val, 1)
                    if context_data_position == bitsPerChar - 1 then
                        context_data_position = 0
                        -- context_data = context_data..getCharFromInt(context_data_val)
                        table.insert(context_data, getCharFromInt(context_data_val))
                        context_data_val = 0
                    else
                        context_data_position = context_data_position + 1
                    end
                end

                value = get_char_value(context_w , bitsPerChar)

                for i = 0, 8-1, 1 do
                    context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
                    if context_data_position == bitsPerChar -1 then
                        context_data_position = 0
                        -- context_data = context_data..getCharFromInt(context_data_val)
                        table.insert(context_data, getCharFromInt(context_data_val))
                        context_data_val = 0
                    else
                        context_data_position = context_data_position + 1
                    end
                    value = bit.arshift(value, 1)
                end
            else
                value = 1
                for i = 0, context_numBits-1, 1 do
                    context_data_val = bit.bor(bit.lshift(context_data_val, 1), value)
                    if context_data_position == bitsPerChar - 1 then
                        context_data_position = 0
                        -- context_data = context_data..getCharFromInt(context_data_val)
                        table.insert(context_data, getCharFromInt(context_data_val))
                        context_data_val = 0
                    else
                        context_data_position = context_data_position + 1
                    end
                    value = 0
                end

                value = get_char_value(context_w , bitsPerChar)
                for i = 0, 16-1, 1 do
                    context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
                    if context_data_position == bitsPerChar -1 then
                        context_data_position = 0
                        -- context_data = context_data..getCharFromInt(context_data_val)
                        table.insert(context_data, getCharFromInt(context_data_val))
                        context_data_val = 0
                    else
                        context_data_position = context_data_position + 1
                    end
                    value = bit.arshift(value, 1)
                end
            end

            context_enlargeIn=context_enlargeIn - 1

            if context_enlargeIn == 0 then
                context_enlargeIn = 2^context_numBits
                context_numBits = context_numBits + 1
            end
            context_dictionaryToCreate = table_remove(context_dictionaryToCreate, context_w)
            -- context_dictionaryToCreate[context_w] = nil
        else
            value = context_dictionary[context_w]
            for i = 0, context_numBits-1, 1 do
                context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
                if context_data_position == bitsPerChar -1 then
                    context_data_position = 0
                    -- context_data = context_data..getCharFromInt(context_data_val)
                    table.insert(context_data, getCharFromInt(context_data_val))
                    context_data_val = 0
                else
                    context_data_position = context_data_position + 1
                end
                value = bit.arshift(value, 1)
            end
        end
        context_enlargeIn = context_enlargeIn - 1

        if context_enlargeIn == 0 then
            context_enlargeIn = 2 ^ context_numBits
            context_numBits = context_numBits + 1
        end
    end

    -- Mark the end of the stream
    value = 2
    for i = 0, context_numBits-1, 1 do
        context_data_val = bit.bor(bit.lshift(context_data_val, 1), bit.band(value, 1))
        if context_data_position == bitsPerChar -1 then
            context_data_position = 0
            -- context_data = context_data..getCharFromInt(context_data_val)
            table.insert(context_data, getCharFromInt(context_data_val))
            context_data_val = 0
        else
            context_data_position = context_data_position + 1
        end
        value = bit.arshift(value, 1)
    end

    --Flush the last char
    while 1 == 1
    do
        context_data_val = bit.lshift(context_data_val, 1)
        if context_data_position == bitsPerChar - 1 then
            -- context_data = context_data..getCharFromInt(context_data_val)
            table.insert(context_data, getCharFromInt(context_data_val))
            break
        else
            context_data_position = context_data_position + 1
        end
    end

    -- return table.concat(context_data，“”)
    -- return context_data
    return table.concat(context_data,"")

end

-- 将一个整数转换为一个字符
local function fc(i)
    print("被调用: ",i .." char: "..utf8.char(i))
    return utf8.char(i)
end

local function defunc(inputStr, index)
    return utf8.byte(inputStr, index+1, index +1)
end

local function get_compressed_length(context, resetValue)
    local length
    if resetValue == 16384 or resetValue == 32768 then
        length = utf8.len(context)
    else
        length = string.len(context)
    end
    return length
end

local DecData = {}

function DecData:new(val, position, index)
    local o = {
        val = val or '',
        position = position or 0,
        index = index or 0
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function DecData:set_val(val)
    self.val = val
end

function DecData:set_position(position)
    self.position = position
end

function DecData:get_val()
    return self.val
end

function DecData:get_index()
    return self.index
end

function DecData:get_position()
    return self.position
end

function DecData:set_index(index)
    self.index = index
end

local function f(i, resetValue)
    if resetValue == 16384 or resetValue == 32768 then
        return utf8.char(i)
    else
        if i >= 256 then
            local high = bit.rshift(i, 8)
            local low = bit.band(i, 0xff)
            return  string.char(high)..string.char(low)
        else
            return string.char(i)
        end
    end
end

local function def_get_char_value(context, resetValue)
    local value
    if resetValue == 16384 or resetValue == 32768 then
        value = utf8.char(utf8.byte(context, 0,  1 ))
    else
        value = string.char(string.byte(context,1))
    end
    return value
end

local function table_length(table)
    local length = 0
    local key, value = next(table)

    while key ~= nil do
        length = length + 1
        key, value = next(table, key)
    end

    return length
end

-- 创建一个函数，将 uint8Array转换为字符串
local function uint8ArrayToString(uint8Array)
    local str = ""
    for i = 1, #uint8Array do
        str = str .. string.char(uint8Array[i])
    end
    return str
end

-- 创建一个函数，将字符串转换为 uint8Array
local function string_to_uint8Array(s)
    local array = {}
    for i = 1, #s do
        table.insert(array, string.byte(s, i))
    end
    return array
end

local function _decompress(inputStr, resetValue, getNextValue)
    if not inputStr or inputStr == '' then
        return ""
    end

    local length = get_compressed_length(inputStr, resetValue)
    local dictionary = {}
    local next=0
    local enlargeIn = 4
    local dictSize = 4
    local numBits = 3
    local entry = ''
    local result_index = 0
    local result = {}
    local w
    local resb
    local c
    local data = DecData:new(getNextValue(inputStr, 0), resetValue , 1)
    local bits = 0
    local maxpower = 2^2
    local power = 1

    for i = 0, 3-1, 1 do
        dictionary[i] = f(i, resetValue)
    end

    while power ~= maxpower do
        resb = bit.band(data:get_val(), data:get_position())
        data:set_position(bit.rshift(data:get_position(), 1))
        if data:get_position() == 0 then
            data:set_position(resetValue)
            if resetValue ~= 16384 then
                data:set_val(getNextValue(inputStr, data:get_index()))
                data:set_index(data:get_index()+1)
            else
                data:set_val(getNextValue(inputStr, data:get_index()))
                data:set_index(data:get_index()+1)
            end
        end

        if resb > 0 then
            bits = bit.bor(bits, 1*power)
        else
            bits = bit.bor(bits, 0)
        end

        power = bit.lshift(power, 1)
    end

    next = bits
    if next == 0 then
        bits = 0
        -- why not use 256 ??
        maxpower = 2^8
        power = 1
        while power ~= maxpower do
            resb = bit.band(data:get_val(), data:get_position())
            data:set_position(bit.rshift(data:get_position(), 1))
            if data:get_position() == 0 then
                data:set_position(resetValue)
                data:set_val(getNextValue(inputStr, data:get_index()))
                data:set_index(data:get_index()+1)
            end

            if resb > 0 then
                bits = bit.bor(bits, 1*power)
            else
                bits = bit.bor(bits, 0)
            end

            power = bit.lshift(power, 1)
        end
        c = f(bits, resetValue)
    elseif next == 1 then
        bits = 0
        maxpower = 2^16
        power = 1
        while power ~= maxpower do
            resb = bit.band(data:get_val(), data:get_position())
            data:set_position(bit.rshift(data:get_position(), 1))
            if data:get_position() == 0 then
                data:set_position(resetValue)
                data:set_val(getNextValue(inputStr, data:get_index()))
                data:set_index(data:get_index()+1)
            end

            if resb > 0 then
                bits = bit.bor(bits, 1*power)
            else
                bits = bit.bor(bits, 0)
            end
            power = bit.lshift(power, 1)
        end
        c = f(bits,resetValue)
    elseif next == 2 then
        return ""
    end

    dictionary[3] = c
    w = c
    -- mock set??
    result[result_index]=w
    result_index=result_index+1


    while 1 == 1 do
        if data:get_index() > length then
            return ""
        end

        bits = 0
        maxpower = 2^numBits
        power=1

        while power ~= maxpower do
            resb = bit.band(data:get_val(), data:get_position())
            data:set_position(bit.rshift(data:get_position(), 1))
            if data:get_position() == 0 then
                data:set_position(resetValue)
                data:set_val(getNextValue(inputStr, data:get_index()))
                data:set_index(data:get_index()+1)
            end
            if resb > 0 then
                bits = bit.bor(bits, 1*power)
            else
                bits = bit.bor(bits, 0)
            end

            power = bit.lshift(power, 1)
        end
        -- TODO: very strange here, c above is as char/string, here further is a int, rename "c" in the switch as "cc"
        local cc = bits
        if cc == 0 then
            bits = 0
            maxpower = 2^8
            power = 1
            while power ~= maxpower do
                resb = bit.band(data:get_val(), data:get_position())
                data:set_position(bit.rshift(data:get_position(), 1))
                if data:get_position() == 0 then
                    data:set_position(resetValue)
                    data:set_val(getNextValue(inputStr, data:get_index()))
                    data:set_index(data:get_index()+1)
                end
                if resb > 0 then
                    bits = bit.bor(bits, 1*power)
                else
                    bits = bit.bor(bits, 0)
                end
                power = bit.lshift(power, 1)
            end

            dictionary[dictSize] = f(bits, resetValue)
            dictSize = dictSize + 1
            cc = dictSize - 1
            enlargeIn = enlargeIn -1

        elseif cc == 1 then
            bits = 0
            maxpower = 2^16
            power = 1
            while power ~= maxpower do
                resb = bit.band(data:get_val(), data:get_position())
                data:set_position(bit.rshift(data:get_position(), 1))
                if data:get_position() == 0 then
                    data:set_position(resetValue)
                    data:set_val(getNextValue(inputStr, data:get_index()))
                    data:set_index(data:get_index()+1)
                end
                if resb > 0 then
                    bits = bit.bor(bits, 1*power)
                else
                    bits = bit.bor(bits, 0)
                end
                power = bit.lshift(power, 1)
            end

            dictionary[dictSize] = f(bits, resetValue)
            dictSize = dictSize + 1
            cc = dictSize - 1
            enlargeIn = enlargeIn -1

        elseif cc == 2 then
            local decomString=''
            for key,value in pairs(result) do
                --print("key is",key, "value=",value)
                decomString=decomString..value
            end
            return decomString
        end

        if enlargeIn == 0 then
            enlargeIn = 2 ^ numBits
            numBits = numBits + 1
        end

        if cc < table_length(dictionary) and dictionary[cc] ~= nil then
        -- if cc < #dictionary and dictionary[cc] ~= nil then
            entry = dictionary[cc]
        else
            if cc == dictSize then
                entry = w..def_get_char_value(w, resetValue)
            else
                return nil
            end
        end

        result[result_index]=entry
        result_index=result_index+1
        --Add w+entry[0] to the dictionary
        dictionary[dictSize]=w..def_get_char_value(entry, resetValue)
        dictSize = dictSize + 1
        enlargeIn = enlargeIn - 1

        w = entry

        if enlargeIn == 0 then
            enlargeIn = 2^numBits
            numBits = numBits + 1
        end
    end
end

function _M.compress(input)
    return _compress(input, 16, fc)
end

function _M.compressToUint8Array(uncompressed)
    local compressed = _M.compress(uncompressed)
    -- print("_M.compressToUint8Array",compressed)
    local buf = {}
    local totalLen = #compressed
    -- print("totalLen",totalLen)
    for i = 1, totalLen do
        local current_value = string.byte(compressed, i)
        buf[i * 2 - 1] = math.floor(current_value / 256)
        buf[i * 2] = current_value % 256
    end
    return buf
end

function _M.compressToUint8ArrayString(uncompressed)
    local uint8Array_buf = _M.compressToUint8Array(uncompressed)
    return uint8ArrayToString( uint8Array_buf )
end

function _M.decompress(inputStr)
    if not inputStr then
        return ''
    end

    if inputStr == '' then
        return nil
    end

    return _decompress(inputStr, 32768, defunc)
end

local function df(i)
    if i >= 256 then
        local high = bit.rshift(i, 8)
        local low = bit.band(i, 0xff)
        return  string.char(high)..string.char(low)
    else
        return string.char(i)
    end
end

function _M.decompressFromUint8Array(compressed)
    if compressed == nil or compressed == '' then
        return _M.decompress(compressed)
    else
        local buf = {}
        local totalLen = #compressed / 2
        print("totalLen: ",totalLen)
        for i = 0, totalLen - 1 do
            buf[i + 1] = compressed[i * 2 + 1] * 256 + compressed[i * 2 + 2]
        end
        print("buf:\n",table.concat(buf, ""))
        local result = {}
        for _, c in ipairs(buf) do
            table.insert(result, df(c))
        end
        print("result:\n",table.concat(result, ""))
        return _M.decompress(table.concat(result, ""))
    end
end

function _M.decompressFromUint8ArrayString(input)
    local  compressed = string_to_uint8Array(input)
    return _M.decompressFromUint8Array(compressed)
end

return _M