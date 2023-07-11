local data, running
function dbg()
    if running then
        debug.sethook()
        running = false
        io.save("mlog.txt", table.concat(data, "\r\n"))
        return
    end
    running = true
    data = {}
    local func
    debug.sethook(function(event, line)
        local info = debug.getinfo(2, "nSf")
        if event == "line" then
            if not func or func ~= info.func then
                table.insert(data, string.format(
                    "%s:%d: function %s (what: %s), func type: %s", info.short_src, line, info.name or "", info.namewhat or "", info.what or ""
                ))
                func = info.func
            else
                table.insert(data, string.format(
                    "%s:%d", info.short_src, line
                ))
            end
        elseif event == "return" then
            table.insert(data, string.format(
                "%s: RETURN FROM function %s (what: %s), func type: %s", info.short_src, info.name or "", info.namewhat or "", info.what or ""
            ))
        elseif event == "call" then
            table.insert(data, string.format(
                "%s: CALL function %s (what: %s), func type: %s", info.short_src, info.name or "", info.namewhat or "", info.what or ""
            ))
        end
    end, "crl")
end