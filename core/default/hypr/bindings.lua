local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

require_all.files((paths.inferna_path or paths.omarchy_path) .. "/default/hypr/bindings", "default.hypr.bindings")
