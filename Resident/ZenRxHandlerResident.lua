--
-- Zen Control Rx Requester Resident (Default Poll Interval 1 sec)
--

state, retval = storage.get('pollwait')

if (state) then
    storage.set('pollwait', false)
else
    ZenDataGramHandler.zen_rx()
end
