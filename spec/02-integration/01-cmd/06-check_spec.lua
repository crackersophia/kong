local helpers = require "spec.helpers"

local INVALID_CONF_PATH = "spec/fixtures/invalid.conf"

describe("kong check", function()
  it("validates a conf", function()
    local _, stderr, stdout = helpers.kong_exec("check "..helpers.test_conf_path)
    assert.equal("", stderr)
    assert.matches("configuration at .- is valid", stdout)
  end)
  it("reports invalid conf", function()
    local _, stderr, stdout = helpers.kong_exec("check "..INVALID_CONF_PATH)
    assert.is_nil(stdout)
    assert.matches("[error] cassandra_repl_strategy has", stderr, nil, true)
    assert.matches("[error] when specifying a custom DNS resolver you must turn off dnsmasq", stderr, nil, true)
  end)
  it("doesn't like invalid files", function()
    local _, stderr, stdout = helpers.kong_exec("check inexistent.conf")
    assert.is_nil(stdout)
    assert.matches("[error] no file at: inexistent.conf", stderr, nil, true)
  end)
end)
