# Jai GON Parser

A GON parser written in Jai.

If you're not familiar with GON, see [Tyler Glaiel's original implementation in C++](https://github.com/TylerGlaiel/GON) for a better overview of the format itself..

In contrast to the original implementation, this parser was not really built with the intent that the user will directly access the DOM and manually navigate it to pull out data.
Instead, this parser leverages the power of Jai's runtime type information to automatically convert string data from the GON file into its proper internal binary type. 
This automates away all of the routine boilerplate that one often finds oneself writing in parsing and serialization code. All you have to do is tell the parser where in the GON file to find your desired data and what variable you want that data stored to.
The parser handles any necessary type conversions automatically. It also handles complex, nested structures and all types of arrays. 

NOTE: This parser recently underwent a major cleanup / refactoring, and I am now carefully considering how (and if) I want to go about reimplementing certain features that were removed. (Specifically, field references and certain aspects of IO Data handling.)
I would like to make this version of the parser as versatile as possible while still keeping it small and simple. 
For a more complex solution with more features, you should check out my LSD data file parser, which is essentially a branch of GON that finally outgrew this repository and flew the coop.


## Dependencies

This module depends on my [Utils](https://github.com/Stuart-Mouse/jai-utils) and [Convert](https://github.com/Stuart-Mouse/jai-convert) modules.
Sorry to make you go download more stuff, I really would prefer if I didn't need the dependencies, but it had become untennable to maintain all of the duplicated code across my modules.


## Motivation

Most parsers for text-based data formats (like JSON, XML, etc.) really only do about half the job, 
because even after they've lexed and parsed the text into some DOM representation, 
you still have to essentially parse the DOM out into your actual data structures.

And if you're actually checking for every possible error (missing nodes, invalid data, structural issues), 
this second stage of parsing turns out to be a considerable amount of code, basically all of which is boilerplate (yet still, error prone!).

The obvious solution to this problem is to use some sort of reflection, 
but unfortunately many statically-typed languages just didn't see the need to add this feature.
Thankfully, Jai has a very robust (yet simple) type info system. 
Using reflection, the parser applies recursive data bindings to the DOM, given only a field path and an `Any` (Jai's wildcard type).

In the following section, you can see an example of what this looks like in action.


## Data Bindings

The main feature of this parser is how it automatically handles all data marshalling through what I've taken to calling 'data bindings'.
A data binding is the relation of some piece of data in your program, say for example a struct, to a specific field path in the file being parsed.

Once the DOM has been parsed from the file, the data bindings you specify will be attached to the corresponding nodes as an `Any`. 
This process of inserting data bindings is recursive, meaning you can give only the data binding for a struct, and all of its members will bind to the DOM automatically.
The same is true of arrays, and the parser can allocate from context.allocator as needed. (In the near future I plan to provide better control over allocators and allocations generally).

An example, from `example.jai`:
```
// Suppose we have the following GON file:
file :: #string END
my_int  5
foo {
    my_float   3.5
    my_string  "this is a string"
}
END

// First, we parse the file. This will construct the DOM so that we can create data bindings to the data in the file.
// (A 'file path' can be provided as the second parameter for use in error logging.)
parser, ok := parse_file(file, "Example 1");
if !ok  return;

// Always remember to deinit the parser so that the DOM gets freed.
defer deinit_parser(*parser);

// Now we want to extract some information from this file into the following variables:
my_int:     int;
my_float:   float;
my_string:  string;

// So we create data bindings with the variables and the path to the data in the file:
ok = add_data_bindings(*parser, 
    .{ my_int,    "my_int"        },
    .{ my_float,  "foo/my_float"  },
    .{ my_string, "foo/my_string" },
);
if !ok  return;

// After processing our data bindings, the variables we bound will have their values filled in.
ok = process_data_bindings(*parser);
if !ok  return;

print("my_int:    %\n", my_int);            // my_int:    5
print("my_float:  %\n", my_float);          // my_float:  3.5
print("my_string: \"%\"\n", my_string);     // my_string: "this is a string"
```

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
- enum_flags

For examples of how data bindings are used in practice, run the included 'examples.jai'.
This file demonstrates both parsing and serialization with data bindings.


## IO Data

IO Data is a special informational structure that the user can define for any type, 
changing how the parser handles that type when evaluating data bindings.

Here are the primary features:
- serializing structs as GON arrays
- defining arrays as being indexed, and their indexing enum type (if applicable)
- serializing structs and arrays on one line
- omitting data which is zero-valued during serialization
- implementing fully custom parsing and serialization procedures

As mentioned above, in the near future I plan to provide a better means for controlling allocator use, and IO data will probably be a part of that.


## User Extension

This IO Data system is provided so that the user can extend the parser in some simple ways, 
but if your needs are not covered by what is already offered through IO Data, 
you may wish to just modify `add_data_binding_to_node` and `process_node_binding` directly.
Or, add a post-processing pass over the data you load after you load it. 

The parser used to have some additional features for handling references between fields, 
but that functionality was removed in a recent refactor. 
There were several reasons for this, but the main reason is that value add just didn't justify the extra code, so I chunked it.

However, field references and many other features are available in my LSD file parser: https://github.com/Stuart-Mouse/jai-lsd
I'm not gonna try to upsell you on the new model here, though. 
LSD may interest you if you want a more rich data format, but be warned it'll certainly be far less stable than GON moving forwards.
The simplicity of GON may also just be better for your use case too. 


