local cjson = require "cjson"


local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at


local function get_body_data()
  local req = ngx.req

  req.read_body()
  local data = req.get_body_data()
  if data then
    return data
  end

  local file_path = req.get_body_file()
  if file_path then
    local file = io.open(file_path, "r")
    data = file:read("*all")
    file:close()
    return data
  end

  return ""
end


local function log(premature, conf, message)
  if premature then
    return
  end

  local host = conf.host
  local port = conf.port
  local timeout = conf.timeout
  local keepalive = conf.keepalive

  local sock = ngx.socket.tcp()
  sock:settimeout(timeout)

  local ok, err = sock:connect(host, port)
  if not ok then
    kong.log.err("failed to connect to ", host, ":", tostring(port), ": ", err)
    return
  end

  if conf.tls then
    ok, err = sock:sslhandshake(true, conf.tls_sni, false)
    if not ok then
      kong.log.err("failed to perform TLS handshake to ", host, ":", port, ": ", err)
      return
    end
  end

  ok, err = sock:send(cjson.encode(message) .. "\n")
  if not ok then
    kong.log.err("failed to send data to ", host, ":", tostring(port), ": ", err)
  end

  ok, err = sock:setkeepalive(keepalive)
  if not ok then
    kong.log.err("failed to keepalive to ", host, ":", tostring(port), ": ", err)
    return
  end
end


local TcpLogHandler = {
  PRIORITY = 7,
  VERSION = "2.0.1",
}


function TcpLogHandler:access(conf)
  if conf.log_body then
    kong.ctx.plugin.request_body = get_body_data()
    kong.ctx.plugin.response_body = ""
  end
end


function TcpLogHandler:body_filter(conf)
  if conf.log_body then
    local chunk = ngx.arg[1]
    kong.ctx.plugin.response_body = kong.ctx.plugin.response_body .. (chunk or "")
  end
end


function TcpLogHandler:log(conf)
  local message = kong.log.serialize({kong = kong, })
  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return TcpLogHandler
