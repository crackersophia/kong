local ssl_fixtures = require "spec.03-plugins.16-ssl.fixtures"
local helpers = require "spec.helpers"


local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                  helpers.test_conf.proxy_ssl_port, server_name)
  ))

  return stdout
end


describe("SSL", function()
  local admin_client

  setup(function()
    helpers.dao:truncate_tables()

    assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "example.com", "ssl1.com" },
      upstream_url = "http://httpbin.org",
    })

    assert(helpers.start_kong())

    admin_client = helpers.admin_client()

    assert(admin_client:send {
      method = "POST",
      path = "/certificates",
      body = {
        cert = ssl_fixtures.cert,
        key  = ssl_fixtures.key,
        snis = "example.com,ssl1.com",
      },
      headers = { ["Content-Type"] = "application/json" },
    })
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  describe("handshake", function()
    it("sets the default fallback SSL certificate if no SNI match", function()
      local cert = get_cert("test.com")
      assert.matches("CN=localhost", cert, nil, true)
    end)

    it("sets the configured SSL certificate if SNI match", function()
      local cert = get_cert("ssl1.com")
      assert.matches("CN=ssl1.com", cert, nil, true)

      cert = get_cert("example.com")
      assert.matches("CN=ssl1.com", cert, nil, true)
    end)
  end)

  describe("https_only", function()

  end)

end)

describe("#o SSL certificates and SNIs invalidations", function()
  local admin_client
  local CACHE_KEY = "certificate.ssl1.com"

  before_each(function()
    helpers.dao:truncate_tables()

    assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "ssl1.com" },
      upstream_url = "http://httpbin.org",
    })

    local certificate = assert(helpers.dao.ssl_certificates:insert {
      cert = ssl_fixtures.cert,
      key  = ssl_fixtures.key,
    })

    assert(helpers.dao.ssl_servers_names:insert {
      ssl_certificate_id = certificate.id,
      name = "ssl1.com",
    })

    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    helpers.stop_kong(nil, true)
  end)

  it("DELETE", function()
    local cert = get_cert("ssl1.com")
    assert.matches("CN=ssl1.com", cert, nil, true)

    -- check cache is populated

    local res = assert(admin_client:send {
      method = "GET",
      path   = "/cache/" .. CACHE_KEY,
    })

    assert.res_status(200, res)

    -- delete the SSL certificate

    res = assert(admin_client:send {
      method = "DELETE",
      path   = "/certificates/ssl1.com",
    })

    assert.res_status(204, res)

    -- ensure cache is invalidated

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. CACHE_KEY,
      })
      res:read_body()
      return res.status == 404
    end, 5)
  end)

  it("UPDATE", function()
    local cert = get_cert("ssl1.com")
    assert.matches("CN=ssl1.com", cert, nil, true)

    -- check cache is populated

    local res = assert(admin_client:send {
      method = "GET",
      path   = "/cache/" .. CACHE_KEY,
    })

    assert.res_status(200, res)

    -- update the SSL certificate

    res = assert(admin_client:send {
      method = "PATCH",
      path   = "/certificates/ssl1.com",
      body   = {
        cert = helpers.file.read(helpers.test_conf.ssl_cert),
        key  = helpers.file.read(helpers.test_conf.ssl_cert_key),
      },
      headers = { ["Content-Type"] = "application/json" },
    })

    assert.res_status(200, res)

    -- ensure cache is invalidated

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. CACHE_KEY,
      })
      res:read_body()
      return res.status == 404
    end, 5)

    cert = get_cert("ssl1.com")
    assert.not_matches("CN=ssl1.com", cert, nil, true)
  end)
end)
