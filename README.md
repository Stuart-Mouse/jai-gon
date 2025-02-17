# Jai GON Parser

The Jai GON Parser is a fast and powerful GON parser with a simple interface that one can begin using within minutes.

This parser leverages the power of Jai's runtime type information to automatically convert string data from the GON file into its proper internal binary type. 
This automates away all of the routine boilerplate that one often finds oneself writing in serialization code. All you have to do is tell the parser where in the GON file to find your desired data and what variable you want that data stored to. The parser handles any necessary type conversions automatically. It also handles complex, nested structures and all types of arrays. 

This parser has undergone several rewrites and iterations, initially starting life as a SAX-style parser and then evolving back into a more traditional DOM-style parser in order to support references between fields. In the future I plan to rewrite the SAX-style implementation as an option for applications where a very minimal, memory-conscious parser is preferred.

For a more extensive description of the project, please visit stuart-mouse.github.io/gon-parsers.
