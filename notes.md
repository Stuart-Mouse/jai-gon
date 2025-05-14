
## TODO

try to remove some of the extraneous flags on nodes

implement flag for not setting name member

maybe implement built-in hash map support because why not?

expression evaluator using lead sheets, with special syntax for field refs
    cannot pre type check, just due to nature of the beast

refactor DOM to use flat pool allocator for nodes

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

## Field References

`&` gets then index of a node within it's parent object or array
`*` gets a pointer to a node's data binding
`$` gets the value of a node (by simply pointing the node at the same underlying string value) 

value refs are resolved differently than index or pointer refs
    as we are validating node references, we actually get rid of all value refs by simply cloning the nodes they refer to, recursively
    so a value ref actually involves copying a section of the dom and pasting it where requested

Currently, we have no mechanism for serializing field references.
We could probably create some way to do this with distinct int and pointer types, but that still would not be very useful when inserting nodes recursively for serialization.




## Cleanup and Rewrite

May remove field references for the time being and re-introduce at a later date
for now, it's sort of better if everything is just POD

For user extension, will introduce something like directives which should be relatively versatile. 



