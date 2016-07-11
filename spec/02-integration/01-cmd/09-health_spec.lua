local helpers = require "spec.helpers"

describe("kong restart", function()
  before_each(function()
    helpers.kill_all()
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.kill_all()
    helpers.clean_prefix()
  end)

  it("health help", function()
    local _, stderr = helpers.kong_exec "health --help"
    assert.not_equal("", stderr)
  end)
  it("succeeds when Kong is running with custom --prefix", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))

    local _, _, stdout = assert(helpers.kong_exec("health --prefix "..helpers.test_conf.prefix))
    assert.matches("serf%.-running", stdout)
    assert.matches("nginx%.-running", stdout)
    assert.not_matches("dnsmasq.*running", stdout)
    assert.matches("Kong is healthy at "..helpers.test_conf.prefix, stdout, nil, true)
  end)
  it("fails when Kong is not running", function()
    local ok, stderr = helpers.kong_exec("health --prefix "..helpers.test_conf.prefix)
    assert.False(ok)
    assert.matches("Kong is not running at "..helpers.test_conf.prefix, stderr, nil, true)
  end)
  it("fails when a service is not running", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    helpers.execute("pkill serf")

    local ok, stderr = helpers.kong_exec("health --prefix "..helpers.test_conf.prefix)
    assert.False(ok)
    assert.matches("Some services are not running", stderr, nil, true)
  end)
  it("checks dnsmasq if enabled", function()
    assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))

    local ok, stderr = helpers.kong_exec("health --prefix "..helpers.test_conf.prefix, {
      dnsmasq = true,
      dns_resolver = ""
    })
    assert.False(ok)
    assert.matches("Some services are not running", stderr, nil, true)
  end)

  describe("errors", function()
    it("errors on inexisting prefix", function()
      local ok, stderr = helpers.kong_exec("health --prefix inexistant")
      assert.False(ok)
      assert.matches("no such prefix: ", stderr, nil, true)
    end)
  end)
end)
