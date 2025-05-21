# Jai GON Parser

The Jai GON Parser is a fast and powerful parser for GON files with a simple interface that one can begin using within minutes.

This parser leverages the power of Jai's runtime type information to automatically convert string data from the GON file into its proper internal binary type. 
This automates away all of the routine boilerplate that one often finds oneself writing in parsing and serialization code. All you have to do is tell the parser where in the GON file to find your desired data and what variable you want that data stored to. The parser handles any necessary type conversions automatically. It also handles complex, nested structures and all types of arrays. 

For a more extensive description of the project, please visit stuart-mouse.github.io/jai-gon.

NOTE: This parser recently underwent a major cleanup / refactoring, and I am now carefully considering how (and if) I want to go about reimplementing certain features that were removed. (Specifically, field references and certain aspects of IO Data handling.)
I would like to make this version of the parser as versatile as possible while still keeping it small and simple. 
For a more complex solution with more features, you should check out my LSD data file parser, which is essentially a branch of GON that finally outgrew this repository and flew the coop.

## Overview

GON files consist of three basic strucutres: fields, objects, and arrays.
Fields consist of a simple key/value pair.
Objects enclose several fields in a matching pair of curly braces.
Arrays enclose several unnamed values in a pair of matching square brackets.

Again, it's basically just JSON but with sparser syntax.

## Data Bindings

The main feature of this parser is how it automatically handles all data marshalling through what I've taken to calling 'data bindings'.
A data binding is the relation of some piece of data in your program, say for example a struct, to a specific field path in the file being parsed.

Once the DOM has been parsed form the file, the data bindings you specify will be attached to the corresponding nodes as an `Any`. 
This process of inserting data bindings is recursive, meaning you can give only the data binding for a struct, and all of its members will bind to the DOM automatically.
The same is true of arrays, and the parser can allocate from context.allocator as needed. (In the near future I plan to provide better control over allocators and allocations generally).

### Supported Data Bindings

Any of the following data types can be bound to a GON field:
    - strings
    - all integer types
    - all float types
    - enum types which are NOT enum_flags
    - structs which define a custom parsing procedure in IO Data
    - arrays with element type `u8` (so that they can be treated like strings)

Any of the following data types can be bound to a GON object:
    - all structs
    - arrays of structs which define a name member in IO Data
    - integer- or enum-indexed arrays 

Any of the following data types can be bound to a GON array:
    - all structs
    - all arrays
    - enums_flags
    

## IO Data

IO Data is a special informational structure that the user can define for any type, 
changing how the parser handles that type when evaluating data bindings.

Here are the primary features:
    - serializing structs as GON arrays
    - defining arrays as being indexed, and their indexing enum type (if applicable)
    - serializing structs and arrays on one line
    - 


## User Extension

This IO Data system is provided so that the user can extend the parser in some simple ways, 
but if your needs are not covered by what is already offered through IO Data, 
you may wish to just modify `add_data_binding_to_node` and `process_node_binding` directly.

Or, add a post-processing pass over the data you load, after you load it. 
The parser used to have some additional features for handling references between fields, 
but that functionality was removed in a recent refactor. 
There were several reasons for this, but the main reason is that value add just didn't justify the extra code, so I chunked it.

However, field references and many other features are available in my LSD file parser: https://github.com/Stuart-Mouse/jai-lsd
I'm not gonna try to upsell you on the new model here, though. 
LSD may interest you if you want a more rich data format, but be warned it'll certainly be far less stable than GON moving forwards.
The simplicity of GON may also just be better for your use case too. 

