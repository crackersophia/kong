local cjson    = require "cjson"
local helpers  = require "spec.helpers"


local TCP_PORT = 35001


for _, strategy in helpers.each_strategy() do
  describe("Plugin: tcp-log (log) [#" .. strategy .. "]", function()
    local proxy_client, proxy_ssl_client
    local proxy_client_grpc, proxy_client_grpcs

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert {
        hosts = { "tcp_logging.com" },
      }

      bp.plugins:insert {
        route = { id = route.id },
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT,
        },
      }

      bp.plugins:insert {
        name    = "post-function",
        route   = { id = route.id },
        config  = { access = { [[
          local header = kong.request.get_header("x-ssl-client-verify")
          if header then
            kong.client.tls.set_client_verify("SUCCESS")
          end
        ]]
        }, },
      }


      local route2 = bp.routes:insert {
        hosts = { "tcp_logging.com" },
        paths = { "/log_body" },
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name = "tcp-log",
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          log_body = true,
        },
      }

      local route3 = bp.routes:insert {
        hosts = { "tcp_logging_tls.com" },
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT,
          tls    = true,
        },
      }

      local route4 = bp.routes:insert {
        hosts = { "tcp_logging_tls.com" },
        paths = { "/log_body" },
      }

      bp.plugins:insert {
        route = { id = route4.id },
        name = "tcp-log",
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          tls = true,
          log_body = true,
        },
      }

      local grpc_service = assert(bp.services:insert {
        name = "grpc-service",
        url = "grpc://localhost:15002",
      })

      local route5 = assert(bp.routes:insert {
        service = grpc_service,
        protocols = { "grpc" },
        hosts = { "tcp_logging_grpc.test" },
      })

      bp.plugins:insert {
        route = { id = route5.id },
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT,
        },
      }

      local route6 = assert(bp.routes:insert {
        service = grpc_service,
        protocols = { "grpc" },
        hosts = { "tcp_logging_grpc_with_body.test" },
      })

      bp.plugins:insert {
        route = { id = route6.id },
        name = "tcp-log",
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          log_body = true,
        },
      }

      local grpcs_service = assert(bp.services:insert {
        name = "grpcs-service",
        url = "grpcs://localhost:15003",
      })

      local route7 = assert(bp.routes:insert {
        service = grpcs_service,
        protocols = { "grpcs" },
        hosts = { "tcp_logging_grpcs.test" },
      })

      bp.plugins:insert {
        route = { id = route7.id },
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT,
        },
      }

      local route8 = assert(bp.routes:insert {
        service = grpcs_service,
        protocols = { "grpcs" },
        hosts = { "tcp_logging_grpcs_with_body.test" },
      })

      bp.plugins:insert {
        route = { id = route8.id },
        name = "tcp-log",
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          log_body = true,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
      proxy_client_grpc = helpers.proxy_client_grpc()
      proxy_client_grpcs = helpers.proxy_client_grpcs()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("logs to TCP", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host  = "tcp_logging.com",
        },
      })
      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)

      -- Since it's over HTTP, let's make sure there are no TLS information
      assert.is_nil(log_message.request.tls)

      -- Since log_body is false, let's make sure there are no bodies information
      assert.is_nil(log_message.request.body)
      assert.is_nil(log_message.response.body)
    end)

    it("logs(with body) to TCP", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_client:send {
        method = "POST",
        path = "/log_body/request",
        headers = {
          host = "tcp_logging.com",
        },
        body = "request body",
      })
      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)

      -- Since it's over HTTP, let's make sure there are no TLS information
      assert.is_nil(log_message.request.tls)

      -- Since log_body is true, let's make sure there are right bodies information
      assert.equal("request body", log_message.request.body);
      assert.is_string(log_message.response.body)
    end)

    it("logs to TCP (#grpc)", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "tcp_logging_grpc.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal("grpc-service", log_message.service.name)

      -- Since it's over HTTP, let's make sure there are no TLS information
      assert.is_nil(log_message.request.tls)

      -- Since log_body is false, let's make sure there are no bodies information
      assert.is_nil(log_message.request.body)
      assert.is_nil(log_message.response.body)
    end)

    it("logs(with body) to TCP (#grpc)", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "tcp_logging_grpc_with_body.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal("grpc-service", log_message.service.name)

      -- Since it's over HTTP, let's make sure there are no TLS information
      assert.is_nil(log_message.request.tls)

      -- Since log_body is true, let's make sure there are right bodies information
      -- request/response body consists of grpc part and pb part
      -- grpc part format: <compressed flag(1 bytes)> <msg len(4 bytes)>
      -- pb part format: <tag> <type> [<length>] <data>

      -- [request body] grpc part: (0, 0, 0, 0, 8), pb part: (10, 6, 119, 111, 114, 108, 100, 33), the last 6 bytes correspond to "world!"
      local expect_request_body = string.char(0, 0, 0, 0, 8, 10, 6, 119, 111, 114, 108, 100, 33)
      assert.equal(expect_request_body, log_message.request.body)

      -- [response body] grpc part: (0, 0, 0, 0, 14), pb part: (10, 12, 104, ... , 108, 100, 33), the last 12 bytes correspond to "hello world!"
      local expect_response_body = string.char(0, 0, 0, 0, 14, 10, 12, 104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 33)
      assert.equal(expect_response_body, log_message.response.body)
    end)

    it("logs proper latencies", function()
      local tcp_thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/delay/1",
        headers = {
          host  = "tcp_logging.com",
        },
      })

      assert.response(r).has.status(200)
      -- Getting back the TCP server input
      local ok, res = tcp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.True(log_message.latencies.proxy < 3000)

      -- Sometimes there's a split milisecond that makes numbers not
      -- add up by 1. Adding an artificial 1 to make the test
      -- resilient to those.
      local is_latencies_sum_adding_up =
        1+log_message.latencies.request >= log_message.latencies.kong +
        log_message.latencies.proxy

      assert.True(is_latencies_sum_adding_up)
    end)

    it("logs proper latencies (#grpc)", function()
      local tcp_thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "tcp_logging_grpc.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = tcp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.equal("grpc", log_message.service.protocol)
      assert.True(log_message.latencies.proxy < 3000)

      -- Sometimes there's a split milisecond that makes numbers not
      -- add up by 1. Adding an artificial 1 to make the test
      -- resilient to those.
      local is_latencies_sum_adding_up =
        1 + log_message.latencies.request >= log_message.latencies.kong +
        log_message.latencies.proxy

      assert.True(is_latencies_sum_adding_up)
    end)

    it("logs proper latencies (#grpcs) #flaky", function()
      local tcp_thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "tcp_logging_grpcs.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = tcp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.equal("grpcs", log_message.service.protocol)
      assert.True(log_message.latencies.proxy < 3000)

      -- Sometimes there's a split milisecond that makes numbers not
      -- add up by 1. Adding an artificial 1 to make the test
      -- resilient to those.
      local is_latencies_sum_adding_up =
        1 + log_message.latencies.request >= log_message.latencies.kong +
        log_message.latencies.proxy

      assert.True(is_latencies_sum_adding_up)
    end)

    it("performs a TLS handshake on the remote TCP server", function()
      local thread = helpers.tcp_server(TCP_PORT, { tls = true })

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host = "tcp_logging_tls.com",
        },
      })
      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)

      -- Since log_body is false, let's make sure there are no bodies information
      assert.is_nil(log_message.request.body)
      assert.is_nil(log_message.response.body)
    end)

    it("performs a TLS handshake(with body) on the remote TCP server", function()
      local thread = helpers.tcp_server(TCP_PORT, { tls = true })

      -- Making the request
      local r = assert(proxy_client:send {
        method = "POST",
        path = "/log_body/request",
        headers = {
          host = "tcp_logging_tls.com",
        },
        body = "request body",
      })
      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)

      -- Since log_body is true, let's make sure there are right bodies information
      assert.equal("request body", log_message.request.body);
      assert.is_string(log_message.response.body)
    end)

    it("logs TLS info", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_ssl_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host  = "tcp_logging.com",
        },
      })

      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("TLSv1.2", log_message.request.tls.version)
      assert.is_string(log_message.request.tls.cipher)
      assert.equal("NONE", log_message.request.tls.client_verify)
    end)

    it("TLS client_verify can be overwritten", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_ssl_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host  = "tcp_logging.com",
          ["x-ssl-client-verify"] = "SUCCESS",
        },
      })

      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("TLSv1.2", log_message.request.tls.version)
      assert.is_string(log_message.request.tls.cipher)
      assert.equal("SUCCESS", log_message.request.tls.client_verify)
    end)

    it("logs(with body) TLS info", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/log_body/request",
        headers = {
          host = "tcp_logging.com",
        },
        body = "request body",
      })

      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("TLSv1.2", log_message.request.tls.version)
      assert.is_string(log_message.request.tls.cipher)
      assert.equal("NONE", log_message.request.tls.client_verify)

      -- Since log_body is true, let's make sure there are right bodies information
      assert.equal("request body", log_message.request.body);
      assert.is_string(log_message.response.body)
    end)

    it("logs TLS info (#grpcs)", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "tcp_logging_grpcs.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.equal("grpcs", log_message.service.protocol)
      assert.equal("TLSv1.2", log_message.request.tls.version)
      assert.is_string(log_message.request.tls.cipher)
      assert.equal("NONE", log_message.request.tls.client_verify)

      -- Since log_body is false, let's make sure there are no bodies information
      assert.is_nil(log_message.request.body);
      assert.is_nil(log_message.response.body)
    end)

    it("logs(with body) TLS info (#grpcs)", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "tcp_logging_grpcs_with_body.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.equal("grpcs", log_message.service.protocol)
      assert.equal("TLSv1.2", log_message.request.tls.version)
      assert.is_string(log_message.request.tls.cipher)
      assert.equal("NONE", log_message.request.tls.client_verify)

      -- Since log_body is true, let's make sure there are right bodies information
      local expect_request_body = string.char(0, 0, 0, 0, 8, 10, 6, 119, 111, 114, 108, 100, 33)
      assert.equal(expect_request_body, log_message.request.body)
      local expect_response_body = string.char(0, 0, 0, 0, 14, 10, 12, 104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 33)
      assert.equal(expect_response_body, log_message.response.body)
    end)

  end)

end
