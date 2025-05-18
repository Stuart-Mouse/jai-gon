# Jai GON Parser

The Jai GON Parser is a fast and powerful parser for GON files with a simple interface that one can begin using within minutes.

This parser leverages the power of Jai's runtime type information to automatically convert string data from the GON file into its proper internal binary type. 
This automates away all of the routine boilerplate that one often finds oneself writing in parsing and serialization code. All you have to do is tell the parser where in the GON file to find your desired data and what variable you want that data stored to. The parser handles any necessary type conversions automatically. It also handles complex, nested structures and all types of arrays. 

For a more extensive description of the project, please visit stuart-mouse.github.io/jai-gon.

NOTE: This parser recently underwent a major cleanup / refactoring, and I am now carefully considering how (and if) I want to go about reimplementing certain features that were removed. (Specifically, field references and certain aspects of IO Data handling.)
I would like to make this version of the parser as versatile as possible while still keeping it small and simple. 
For a more complex solution with more features, you should check out my LSD data file parser, which is essentially a branch of GON that finally outgrew this repository and flew the coop.

