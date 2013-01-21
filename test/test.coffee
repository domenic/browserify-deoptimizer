"use strict"

expect = require("chai").expect
fs = require("fs")
path = require("path")
browserify = require("browserify")
_ = require("underscore")
BrowserifyWrap = require("browserify/lib/wrap")
{ isCoreBuiltin } = require("../lib/utils")

deoptimize = require("..")

fixtureDir = path.resolve(__dirname, "fixtures")
fixtureId = (fileName) => "/test/fixtures/" + fileName
keyFromId = (id) => if id[0] is "/" then id.substring(1) else id
fixtureKey = (fileName) => keyFromId(fixtureId(fileName))
fixturePath = (fileName) => path.resolve(fixtureDir, fileName)
fixtureText = (fileName) => fs.readFileSync(fixturePath(fileName))
wrapped = (moduleId, body) => new BrowserifyWrap({}).wrap(moduleId, body)
wrappedFixture = (fileName) => wrapped(fixtureId(fileName), fixtureText(fileName))
wrappedOther = (moduleId) => wrapped(moduleId, fs.readFileSync(moduleId.substring(1)))
wrappedWithSpecificId = (moduleId, fileName) => wrapped(moduleId, fs.readFileSync(fileName))

describe "With a simple entry file that `require`s another file", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.addEntry(fixturePath("requires1.js"))

        deoptimized = deoptimize(bundle)

    it "should include the prelude file as browserify-prelude.js", =>
        bundle = browserify(exports: true)
        for fileName of bundle.files
            if not isCoreBuiltin(fileName)
                delete bundle.files[fileName]
        preludeContents = bundle.bundle()

        expect(deoptimized).to.have.property("browserify-prelude.js").that.equals(preludeContents)

    it "should include the entry file and its required file separately", =>
        expect(deoptimized).to.have.property(fixtureKey("requires1.js")).that.equals(wrappedFixture("requires1.js"))
        expect(deoptimized).to.have.property(fixtureKey("1.js")).that.equals(wrappedFixture("1.js"))

    it "should include a browserify-entry.js file as the last one", =>
        lastKey = _.last(Object.keys(deoptimized))
        expect(lastKey).to.equal("browserify-entry.js")

    it "should include a browserify-entry.js file that simply requires the entry file", =>
        entryFileContents = "require(\"#{fixtureId('requires1.js')}\");\n"
        expect(deoptimized).to.have.property("browserify-entry.js").that.equals(entryFileContents)

    it "should not contain a browserify-aliases.js file", =>
        expect(deoptimized).not.to.have.property("browserify-aliases.js")

describe "With an entry file that `require`s the assert module", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.addEntry(fixturePath("requiresAssert.js"))

        deoptimized = deoptimize(bundle)

    it "should include the assert module", =>
        expect(deoptimized).to.have.property("assert")

describe "With multiple entry files", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.addEntry(fixturePath("requires1.js"))
        bundle.addEntry(fixturePath("requiresAssert.js"))

        deoptimized = deoptimize(bundle)

    it "should include both entry files", =>
        expect(deoptimized).to.have.property(fixtureKey("requires1.js"))
            .that.equals(wrappedFixture("requires1.js"))
        expect(deoptimized).to.have.property(fixtureKey("requiresAssert.js"))
            .that.equals(wrappedFixture("requiresAssert.js"))

    it "should include files required by both entry files", =>
        expect(deoptimized).to.have.property(fixtureKey("1.js")).that.equals(wrappedFixture("1.js"))
        expect(deoptimized).to.have.property("assert")

    it "should include a browserify-entry.js file that requires both entry files, in order", =>
        entryFileContents = """
                            require("#{fixtureId('requires1.js')}");
                            require("#{fixtureId('requiresAssert.js')}");

                            """
        expect(deoptimized).to.have.property("browserify-entry.js").that.equals(entryFileContents)

describe "With no entry files", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.require(fixturePath("requires1.js"))

        deoptimized = deoptimize(bundle)

    it "should include all recursively-required files", =>
        expect(deoptimized).to.have.property(fixtureKey("requires1.js")).that.equals(wrappedFixture("requires1.js"))
        expect(deoptimized).to.have.property(fixtureKey("1.js")).that.equals(wrappedFixture("1.js"))

    it "should not include a browserify-entry.js file", =>
        expect(deoptimized).not.to.have.property("browserify-entry.js")

describe "With aliases", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.alias("underscore2", "underscore")
        bundle.addEntry(fixturePath("requiresAliased.js"))

        deoptimized = deoptimize(bundle)

    it "should remove the `require.alias` calls from the prelude", =>
        preludeContents = deoptimized["browserify-prelude.js"]

        expect(preludeContents).to.not.contain("require.alias(")

    it "should include the `require.alias` calls in browserify-aliases.js", =>
        aliasesFileContents = 'require.alias("underscore", "/node_modules/underscore2");\n'
        expect(deoptimized).to.have.property("browserify-aliases.js").that.equals(aliasesFileContents)

    it "should include the un-aliased package", =>
        expect(deoptimized).to.have.property("node_modules/underscore/package.json")
        expect(deoptimized).to.have.property("node_modules/underscore/index.js")

describe "With registered extensions", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.register(".jade", (body, fileName) => "module.exports = 'blah';")
        bundle.addEntry(fixturePath("requiresJade.js"))

        deoptimized = deoptimize(bundle)

    it "should add that extension to `require.extensions` in the prelude", =>
        preludeContents = deoptimized["browserify-prelude.js"]

        expect(preludeContents).to.contain('require.extensions = [".js",".coffee",".json",".jade"]')

    it "should bundle any files with that extension that are required", =>
        wrappedJadeBody = wrapped(fixtureId("stuff.jade"), "module.exports = 'blah';")
        expect(deoptimized).to.have.property(fixtureKey("stuff.jade")).that.equals(wrappedJadeBody)

describe "With prepends", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.prepend("var x = 5;")

        deoptimized = deoptimize(bundle)

    it "should add the prepend code to the prelude", =>
        preludeContents = deoptimized["browserify-prelude.js"]

        expect(preludeContents).to.match(/^var x = 5;/)

describe "With a specific baseDir", =>
    deoptimized = null

    beforeEach =>
        bundle = browserify()
        bundle.addEntry(fixturePath("requires1.js"))

        deoptimized = deoptimize(bundle, __dirname)

    it "should include the entry file and its dependent with a key relative to the baseDir", =>
        requires1Contents = wrappedWithSpecificId("/fixtures/requires1.js", fixturePath("requires1.js"))
        expect(deoptimized).to.have.property("fixtures/requires1.js").that.equals(requires1Contents)

        oneContents = wrappedWithSpecificId("/fixtures/1.js", fixturePath("1.js"))
        expect(deoptimized).to.have.property("fixtures/1.js").that.equals(oneContents)
