# Split Browserify Bundles into Individual Files

Sometimes you work in browsers without `//@ sourceURL` or source maps. But you like using [Browserify][], since it's
truly amazing. How will you ever debug things? With all your modules squished into one file, it's a disaster.

Enter the **Browserify Deoptimizer**, which will handily “de-optimize” your Browserify bundles by turning them into
individual files, including files for each module you author.

[browserify]: https://github.com/substack/node-browserify

## Usage

You use the Browserify Deoptimizer by first creating a Browserify bundle, programmatically. Then, instead of creating a
big string with `bundle.bundle()`, you just deoptimize it!

```js
var browserify = require("browserify");
var deoptimize = require("browserify-deoptimizer");

var bundle = browserify();
bundle.alias("jquery", "jquery-browserify");
bundle.addEntry("start.js");

var baseDirectory = process.cwd(); // module IDs will be determined relative to this
var deoptimized = deoptimize(bundle, baseDirectory);
```

Your `deoptimized` variable will then look something like this:

```js
{
  "browserify-prelude.js": 'var require = function (file, …',
  "node_modules/jquery-browserify/package.json": 'require.define("/node_modules/…',
  "node_modules/jquery-browserify/index.js": 'require.define("/node_modules/…',
  "browserify-aliases.js": 'require.alias("jquery-browseri…',
  "start.js": 'require.define("/start.js",fun…',
  "browserify-entry.js": 'require("/start.js");'
}
```

You can then use these module IDs to write out the wrapped files to the filesystem, and the appropriate `<script>` tags
to your `index.html`.

## Special Files

Since Browserify does some magic, we can't just create a single file for each of your modules. We need some magic files
too. These are:

- `browserify-prelude.js`: contains the definition of `require` and `process`, as well as any prepends with
  `bundle.prepend`. This will be the first file in the map.
- `browserify-aliases.js`: Contains any calls to Browserify's `require.alias` to set up module aliases. This is inserted
  into the map after the entries for the aliased files themselves (e.g. after jquery-browserify's files). If there are
  no aliases, this file will not exist.
- `browserify-entry.js`: Contains calls to `require` for all entry files in the bundle. If there are no entry files,
  this file will not exist.

## Name

This package owes its name to [r.js][], the RequireJS optimizer, which turns multiple AMD modules into a single bundled
file. Since this package does the opposite, I thought it'd be clever to name it a deoptimizer.

[r.js]: http://requirejs.org/docs/optimization.html
