local version = setmetatable({
  major = 0,
  minor = 9,
  patch = 0,
  pre_release = "rc2"
}, {
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
                         t.pre_release and t.pre_release or "")
  end
})

return {
  _NAME = "kong",
  _VERSION = tostring(version),
  _VERSION_TABLE = version,

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()`.
  _DEPENDENCIES = {
    nginx = "1.9.15.1",
    --resty = "", -- not version dependent for now
    serf  = "0.7.0",
    --dnsmasq = "" -- not version dependent for now
  }
}
