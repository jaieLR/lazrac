--
-- Zen Control Triiger Handler (All events from objects with keyword: zencontrol)
--

addrinfo = event.dst
oinfo, retval = storage.get(addrinfo)

if (oinfo[2]) then
    oinfo[2] = false
    oinfo[3] = true
    storage.set(event.dst, oinfo)
else
    storage.set('pollwait', true)
    ZenDataGramHandler.send_datagram(addrinfo, event.getvalue())
end

