
# hslinks

Resolves links to Haskell functions in Markdown-style text.

Invoke with a list of Cabal files as follows

    hslinks foo/Foo.cabal bar/Bar.cabal ... <input-file >output-file

The program acts as a text transformer that replaces

* `@[foo]` with `[foo][foo]`
* `@@@hslinks@@@` with *module index* consisting of URLs to Haddock files

For an example, see `Test.md`.

`hslinks` uses the modules currently installed on the system.


## Requirements

* [Haskell Platform](http://www.haskell.org/platform)

## Installation

    cabal configure
    cabal install
