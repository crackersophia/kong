local helpers = require "spec-old-api.helpers"


local TEST_PREFIX = "servroot_prepared_test"


describe("kong prepare", function()
  setup(function()
    pcall(helpers.dir.rmtree, TEST_PREFIX)
  end)

  after_each(function()
    pcall(helpers.dir.rmtree, TEST_PREFIX)
  end)

  it("prepares a prefix", function()
    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
      prefix = TEST_PREFIX
    }))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
    local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

    assert.truthy(helpers.path.exists(admin_access_log_path))
    assert.truthy(helpers.path.exists(admin_error_log_path))
  end)

  it("prepares a prefix from CLI arg option", function()
    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path ..
                             " -p " .. TEST_PREFIX))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
    local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

    assert.truthy(helpers.path.exists(admin_access_log_path))
    assert.truthy(helpers.path.exists(admin_error_log_path))
  end)

  describe("errors", function()
    it("on inexistent Kong conf file", function()
      local ok, stderr = helpers.kong_exec "prepare --conf foobar.conf"
      assert.False(ok)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)
  end)
end)
