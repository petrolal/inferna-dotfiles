-- App-specific tweaks.
local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

require_all.files((paths.inferna_path or paths.inferna_path) .. "/default/hypr/apps", "default.hypr.apps")
