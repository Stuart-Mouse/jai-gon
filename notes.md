
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

