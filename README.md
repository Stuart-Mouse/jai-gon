# Jai GON Parser

The Jai GON Parser is a fast and powerful SAX-style parser for GON files with a simple interface that one can begin using within minutes.

This parser leverages the power of Jai's runtime type information to automatically convert string data from the GON file into its proper internal binary type. 
This automates away all of the routine boilerplate that one often finds oneself writing in serialization code. All you have to do is tell the parser where in the GON file to find your desired data and what variable you want that data stored to. The parser handles any necessary type conversions automatically. It also handles complex, nested structures and all types of arrays. 

The functionality of the parser can also be extended or modified through callback procedures. 
This can be used to implement custom data loading procedures for special types, or modify previously loaded data.

And all of this is done in a single linear pass over the source file.
The result is an extremely powerful and easy to use parser with a negligible memory footprint. 

For a more extensive description of the project, please visit https://github.com/Stuart-Mouse/jai-gon.