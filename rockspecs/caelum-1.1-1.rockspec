-- Caelum-1.1-1.rockspec

package = "Caelum"
version = "1.1-1"
source = {
  url = "https://github.com/zLouis043/Caelum-lua/archive/refs/tags/v1.0.tar.gz",
  -- sha256 = "<hash>"
}
description = {
  summary = "Lua Library that adds Classes, Structs, Enums, validators, type-checking system, and a easy reflection system",
  homepage = "https://github.com/zLouis043/Caelum-lua",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  -- eventuali altre dipendenze
}
build = {
  type = "builtin",
  modules = {
    ["Caelum"] = "./src/Caelum.lua"
  }
}
