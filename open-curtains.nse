description = [[Take snapshots from VNC servers not requiring authentication]]
author = "David Ramsden (adapted)"
license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = {"default", "safe"}

portrule = function(host, port)
    return port.protocol == "tcp" and port.state == "open"
end

action = function(host, port)
    local pl = os.getenv("OPEN_CURTAINS_PL") or "./open-curtains.pl"
    local cmd = pl .. " " .. host.ip .. " " .. port.number .. " 2>&1"
    local handle = io.popen(cmd)
    if not handle then return "ERR:exec" end
    local output = handle:read("*a") or ""
    handle:close()
    return output
end
