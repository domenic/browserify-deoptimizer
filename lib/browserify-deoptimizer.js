"use strict";

var browserify = require("browserify");
var _ = require("underscore");
var path = require("path");

var urlize = require("./utils").urlize;
var isCoreBuiltin = require("./utils").isCoreBuiltin;

function getModuleId(file, filePath, baseDir) {
    return file.target || urlize(path.relative(baseDir, filePath));
}

function keyFromModuleId(moduleId) {
    // Keys in the result map should be a bit more friendly than the raw Browserify module IDs, which often begin with
    // `/`. This makes them hard to deal with as paths, since they act as absolute paths. Just remove the leading `/`.
    return moduleId[0] === "/" ? moduleId.substring(1) : moduleId;
}

function addFilesAndEntries(bundle, result, baseDir) {
    // The `bundle.files` and `bundle.entries` properties map absolute file paths to unwrapped module bodies. Use them
    // to create a map of module IDs to wrapped module bodies.
    var allFiles = _.extend({}, bundle.files, bundle.entries);

    Object.keys(allFiles).forEach(function (filePath) {
        if (!isCoreBuiltin(filePath)) {
            var file = allFiles[filePath];
            var moduleId = getModuleId(file, filePath, baseDir);
            result[keyFromModuleId(moduleId)] = bundle.wrap(moduleId, file.body);
        }
    });
}

function removeNonPreludeStuff(bundle) {
    // Temporarily move non-core builtins out of `bundle.files` and `bundle.entries`. They will go in individual files.
    // Also move `bundle.aliases`, since we take care of those in a separate browserify-aliases.js file.
    var files = Object.create(null);
    var entries = bundle.entries;
    var aliases = bundle.aliases;

    for (var fileName in bundle.files) {
        if (!isCoreBuiltin(fileName)) {
            files[fileName] = bundle.files[fileName];
            delete bundle.files[fileName];
        }
    }
    bundle.entries = {};
    bundle.aliases = {};

    return { files: files, entries: entries, aliases: aliases };
}

function addBackNonPreludeStuff(bundle, nonPreludeStuff) {
    for (var movedFileName in nonPreludeStuff.files) {
        bundle.files[movedFileName] = nonPreludeStuff.files[movedFileName];
    }
    bundle.entries = nonPreludeStuff.entries;
    bundle.aliases = nonPreludeStuff.aliases;
}

function addPrelude(bundle, result) {
    var nonPreludeStuff = removeNonPreludeStuff(bundle);

    result["browserify-prelude.js"] = bundle.bundle();

    addBackNonPreludeStuff(bundle, nonPreludeStuff);

    // Since we called `bundle.bundle`, we need to reload the bundle.
    bundle.reload();
}

function addAliases(bundle, result, baseDir) {
    if (Object.keys(bundle.aliases).length === 0) {
        return;
    }

    // Create a bundle with the aliases. It currently contains the prelude, the aliases, and the core built-ins.
    var tempBundle = browserify({ require: bundle.aliases, cache: true });

    // Add files and entries for this temp bundle: this gets the un-aliased files to be included. I.e. if we alias
    // jquery-browserify to jquery, this puts jquery-browserify in the result.
    addFilesAndEntries(tempBundle, result, baseDir);

    // Now we're going to generate the browserify-aliases.js file. To do this, remove all actual files and the prelude:
    // we just want the `require.alias` calls.
    tempBundle.files = {};
    tempBundle.prepends = [];

    // This will give a string containing the the `require.alias` calls only.
    result["browserify-aliases.js"] = tempBundle.bundle();
}

function addEntryRequirer(bundle, result, baseDir) {
    if (Object.keys(bundle.entries).length === 0) {
        return;
    }

    var entryRequires = Object.keys(bundle.entries).reduce(function (soFar, filePath) {
        var file = bundle.entries[filePath];
        var moduleId = getModuleId(file, filePath, baseDir);
        return soFar + 'require("' + moduleId + '");\n';
    }, "");
    result["browserify-entry.js"] = entryRequires;
}

module.exports = function (bundle, baseDir) {
    if (baseDir === undefined) {
        baseDir = process.cwd();
    }

    var result = Object.create(null);

    // The multi-file nature necessitates forcing all exports, otherwise subsequent files don't know what `require` is.
    bundle.exports = true;

    addPrelude(bundle, result);
    addAliases(bundle, result, baseDir);
    addFilesAndEntries(bundle, result, baseDir);
    addEntryRequirer(bundle, result, baseDir);

    return result;
};
