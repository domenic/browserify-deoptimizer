"use strict";

var path = require("path");
var _ = require("underscore");

exports.urlize = function (path) {
    return "/" + path.replace(/\\/g, "/");
};

exports.isCoreBuiltin = function (filePath) {
    // The "core" built-in modules must be bundled into the prelude file, since the definitions of Browserify's
    // `require` depend on them: they cannot be split out into separate files.
    var pieces = filePath.split(path.sep).slice(-3);

    return _.isEqual(pieces, ["browserify", "builtins", "path.js"]) ||
           _.isEqual(pieces, ["browserify", "builtins", "__browserify_process.js"]);
};
