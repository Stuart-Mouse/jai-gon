
## TODO

finish cleanup
    remove extraneous flags on nodes
re-test and create a somewhat comprehensive test suite 
hash map support


## Better User Extension & Setting Allocators

Just got the idea to use something like Print's formatter to create a better interface for user extension.

For example, if we wanted to make a data binding to a gon object, but we needed to use a custom alloc proc for the elements
    e.g., we are using a linked list
        in previous version, we had to just add a callback that would run for all nodes, 
        checking the parent binding's type and then manually setting the data binding on the node
        with the new method we would only run the callback on the single data binding, since we are just wrapping the base any with the extra data/procedures it needs

// structure for extending parsing of a GON object or array
// if we get one of these bound to a field, that's wrong
Container :: struct {
    binding: Any; // base data binding
    alloc: (Any) -> Any; // pass base binding, return a new element
}

problem: this will not actually work for recursive stuffs
because this only wraps a top-level object
Theoretically you could write alloc procs that also wrapped the next object down, but that seems like its starting to get ridiculous
    also that would probably not actually work bc we would need storage for the wrapping portion itself

maybe this would not be all that bad to have as a feature even if it only helped at the top level
since then we could do something like just setting an object to allocate all elements of a specifc type in a pool allocator
but simply having a set_allocator_for_type proc would probabyl be more useful, or something like io_data structures




## Cleanup and Rewrite

Temporarily remove field references to reconsider how these can be implemented better, more simply.
    Should have some means of serializing or inserting as nodes procedurally.
    Maybe restrict to them working purely lexically.

For user extension, will introduce something like directives which should be relatively versatile. 
    may be able to implement some level of control over allocators through directives

We are very close to being able to completely remove node flags, but I didnt feel like refactoring the sameline stuff for serialization just yet
    and I'm also somewhat hesitant about removing .ARRAY_INDEXED and .ARRAY_AS_OBJECT
    maybe we will want to add these back in behind some interface proc so that we can change things around in future if needed
    did go through with removing these, will see how it plays out long term

Lexer improvements
    I think it would be beneficial to lex numbers, identifiers, and strings as distinct tokens 
    then maybe we just store the 'name' and 'value' tokens on each node, so that we preserve info about the token type into the data binding stage
        number can bind to int/float/enum
        string can be as name of field or value for string
        identifier can be used as name of field or value for enum
            identifier could gain special usage in other cases if disambiguated from string?
        this is actually not working out really, no real point to keeping the token type after lexing
        
        may give this another try at some point so that we can enforce things like not assigning strings to numbers
            could also be a lsight speed improvement, since we can just parse numbers when we lex them, and convert to proper type later with Convert.jai
            could also help in preserving the type of quotation marks used around a string


add better logging functions a la tbd module report_parse_error

need to finish writing some basic test cases?
    at least need to manually test stuff again before publishing
    
try to remove some dependencies on Convert.jai and Utils module if possible?
    can't really, now that we use scanner.jai and just moved out set_value_form_string...
    just owrk on clarifying and organizing dependencies in the future


serialize.jai is pretty good right now
dom.jai is pretty good too, but maybe we should think about making more stuff #scope_module until it's more hardened
parse.jai is probably the most messy at the moment

## Directives

`#identifier(...)`

Capture everything inside the parenthesis, considers matching inner pairs of parens ?
    give the user the idrective parameters as one big string, or as an array of tokens?
    doing tokens is probably the best option since once can always just pass a string to the directive

What can directives do?
    produce a typed value? 
    modify previous/parent field?
    modify parser state?
    
    
    


