# Jai GON Parser

## Dependencies

This module depends on my Utils module (sorry): https://github.com/Stuart-Mouse/jai-utils
I use this Utils module for many functions which are common across my other modules.


## About

GON is a JSON-like data file format, originally create by Tyler Glaiel: https://github.com/TylerGlaiel/GON

The Jai GON Parser has changed a lot over time, and the version currently in development is not really even GON anymore...
BUT if you're interested, go ahead and read about the parser at the link below. 

The current version on the main branch here is a DOM-style parser with some additional features over regular GON, in particular, there is some additional syntax for created 'references' between fields in a file.
There are value, pointer, and index references, which are exactly what they sound like.

Current work is being done on the `lead-sheets` branch, where I've integrated the file format with my scripting language module in order to allow the user to write arbitrary expressions into their data files, including dynamically calling into native code.

For a more extensive description of the project, please visit stuart-mouse.github.io/jai-gon.

