--
-- Zen UDP DataGram Handler
--

ZenDataGramHandler = {}

function ZenDataGramHandler.send_datagram(obj_addr, obj_level)
    socket = require("socket")
    udp = socket.udp()
    cbus_data = ZenDataGramHandler.string_split(obj_addr, "/")
    cbus_data[4] = obj_level
    datagram_payload = ZenDataGramHandler.transform_cbus_data(cbus_data)
    objinfo, retval = storage.get(obj_addr)
    udp:setpeername(objinfo[1],5108)
    udp:send(datagram_payload)
    ZenDataGramHandler.rx_from_zencontroller(udp)
    udp:close()
end

function ZenDataGramHandler.transform_cbus_data(cbus_data)
    local cbus_datagram = {}
    local input_chksum = {}
    -- control byte
    cbus_datagram[1] = string.char(0)
    input_chksum[1] = 0
    -- unused byte 1
    cbus_datagram[2] = string.char(0)
    input_chksum[2] = 0
    -- unused byte 2
    cbus_datagram[3] = string.char(0)
    input_chksum[3] = 0
    -- unused byte 3
    cbus_datagram[4] = string.char(0)
    input_chksum[4] = 0
    -- address byte
    addr = tonumber(cbus_data[3])
    dali_address_byte = ZenDataGramHandler.get_dali_address_byte(addr)
    cbus_datagram[5] = string.char(dali_address_byte)
    input_chksum[5] = dali_address_byte
    -- arc level
    level = cbus_data[4]
    if level == 255 then
        level = 254
    end
    cbus_datagram[6] = string.char(level)
    input_chksum[6] = level
    -- xor checksum of address byte and arc level
    cbus_datagram[7] = string.char(ZenDataGramHandler.get_xor_checksum(input_chksum))
    return table.concat(cbus_datagram,"")
end

function ZenDataGramHandler.get_dali_address_byte(addr)
    -- cmd_flag -> 0x0 (Direct Mode) and 0x1 (InDirect Mode)
    local cmd_flag = 0
    if (addr < 176) then
        addr = addr % 16
        dali_address_byte = bit.bor(bit.bor(bit.lshift(addr, 1), 128), cmd_flag)
    elseif (addr > 175) then
        if (addr > 239) then
            addr = 127
        else
            addr = addr % 176
        end
        dali_address_byte = bit.bor(bit.lshift(addr, 1), cmd_flag)
    end
    return dali_address_byte
end

function ZenDataGramHandler.get_xor_checksum(data_array)
    local xor_data = 0
    for ckey, cval in pairs(data_array) do
        xor_data = bit.bxor(xor_data, cval)
    end
    return xor_data
end

function ZenDataGramHandler.rx_from_zencontroller(udp)
    udp:settimeout(0.2)
    local data = udp:receive()
    if (data ~= nil) then
        a = 1
        if (string.match(data,'R')) then
            log('UDP Message: Received successfully by the controller')
    	elseif (string.match(data,'S R')) then
            log('UDP Message: Invalid Command')
            -- TBD
    	elseif (string.match(data,'Reply Error – Short Circuit')) then
            log('UDP Message: Physical DALI Bus error')
        elseif (data) then
            log(data)
        end
    end
end

function ZenDataGramHandler.build_quick_query(address)
    local query_payload = {}
    local input_chksum = {}
    -- Quick Query Control Byte Mode 3
    query_payload[1] =  string.char(3)
    input_chksum[1] = 3
    -- unused byte 1
    query_payload[2] = string.char(0)
    input_chksum[2] = 0
    -- unused byte 2
    query_payload[3] = string.char(0)
    input_chksum[3] = 0
    -- unused byte 3
    query_payload[4] = string.char(0)
    input_chksum[4] = 0
    -- address byte for quick query
    q_addr = ZenDataGramHandler.get_dali_address_byte(address)
    query_payload[5] = string.char(q_addr)
    input_chksum[5] = q_addr
    -- query value 0xA0
    query_payload[6] = string.char(160)
    input_chksum[6] = 160
    -- XOR Data
    query_payload[7] = string.char(ZenDataGramHandler.get_xor_checksum(input_chksum))
    return table.concat(query_payload,"")
end

function ZenDataGramHandler.zen_rx()
    integration_kw = "zencontrol"
    socket_rx = require("socket")
    udp_rx = socket_rx.udp()
    local zobjects = GetCBusByKW(integration_kw)

    local zc_array = {}
    for okey, oval in pairs(zobjects) do
        if (oval['is_user_parameter']) then
            nettag, apptag, grouptag = CBusLookupAddresses(oval['address'][1], oval['address'][2], oval['address'][3])
            zc_array[grouptag] = oval['units']
        end
    end

    for obj, vals in pairs(zc_array) do
        local zc_objects = GetCBusByKW(obj)
        for zobj, zvals in pairs(zc_objects) do
            state, retval = storage.get('pollwait')
            if (not state) then
                local net_id = zvals['address'][1]
                local app_id = zvals['address'][2]
                local obj = zvals['address'][3]
                local obj_addr = tostring(zvals['address'][1]) .. '/' .. tostring(zvals['address'][2]) .. '/' .. tostring(zvals['address'][3])
                local obj_level = GetCBusLevel(net_id, app_id, obj)

                if (obj < 240) then
                    local query = ZenDataGramHandler.build_quick_query(obj)
                    local rxval_array, retval = storage.get(obj_addr)
                    udp_rx:setpeername(rxval_array[1],5108)
                    udp_rx:settimeout(0.2)
                    if (rxval_array[3]) then
                        rxval_array[3] = false
                        storage.set(obj_addr, rxval_array)
                    else
                        udp_rx:send(query)
                        local data = udp_rx:receive()
                        if (data ~= nil) then
                            local input_chksum = {}
                            local response = string.byte(data,1)
                            local level = string.byte(data,2)
                            input_chksum[1] = response
                            input_chksum[2] = level
                            local rx_checksum = string.byte(data,3)
                            local checksum = ZenDataGramHandler.get_xor_checksum(input_chksum)
                            if (level == 254) then
                                level = 255
                            end
                            if (response == 81 and checksum == rx_checksum and obj_level ~= level) then
                                log ("Updating Level Info for object: " .. obj_addr)
                                rxval_array[2] = true
                                storage.set(obj_addr, rxval_array)
                                SetCBusLevel(net_id, app_id, obj, level, 0)
                            elseif (response == 255) then
                                log ("Warning :: Rxed Mixed as response. DALI gear has different actual levels: " .. obj_addr)
                            end
                        end
                    end
                end
            end
        end
    end
    udp_rx:close()
end

function ZenDataGramHandler.initialize_objects()
    integration_kw = "zencontrol"
    storage.set('pollwait', false)
    local zobjects = GetCBusByKW(integration_kw)
    local zc_array = {}
    for okey, oval in pairs(zobjects) do
    	if (oval['is_user_parameter']) then
            nettag, apptag, grouptag = CBusLookupAddresses(oval['address'][1], oval['address'][2], oval['address'][3])
            log ('Found Controller ' .. oval['units'] .. ' with keyword : ' .. grouptag)
            zc_array[grouptag] = oval['units']
        end
    end
    -- Each controlled object will have a table value
    -- Value[1]: IP Address of ZC
    -- Value[2]: If level is set from Rx loop. False otherwise
    -- Value[3]: Level setby Event Handler
    for obj, vals in pairs(zc_array) do
        local zc_objects = GetCBusByKW(obj)
        for zobj, zvals in pairs(zc_objects) do
            local val_array = {}
            local obj_addr = tostring(zvals['address'][1]) .. '/' .. tostring(zvals['address'][2]) .. '/' .. tostring(zvals['address'][3])
            val_array[1] = vals
            val_array[2] = false
            val_array[3] = false
            storage.set(obj_addr, val_array)
        end 
    end
end

function ZenDataGramHandler.string_split(inputstring, separator)
    if separator == nil then
        separator = "%s"
    end
    local t={} ; i=1
    for str in string.gmatch(inputstring, "([^"..separator.."]+)") do
        t[i] = str
        i = i + 1
    end
    return t
end

function ZenDataGramHandler.get_version()
    version_info = "version 1.0.2, 2020-08-12"
    return version_info
end
