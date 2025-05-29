
## TODO

hash map support
    may be problematic that we separate placement and evaluation of bindings
    can we iterate children twice, inserting all elements and then doing bindings?
tagged_union support
    needed in convert.jai as well, probably do it there first 


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


need to finish writing some basic test cases?
    at least need to manually test stuff again before publishing
        need to test indexed arrays and enum-indexed arrays
        need to test custom io data parsing and serialization procs
    
try to remove some dependencies on Convert.jai and Utils module if possible?
    can't really, now that we use scanner.jai and just moved out set_value_form_string...
    just work on clarifying and organizing dependencies in the future





## How much to simplify?

If we remove the distinction between the steps of putting data bindings on the nodes and actually evalutating those data bindings,
    then we may get more flexibility in how we mkae/evaluate bindings
    could create a module which does this generically enough that it can be applied to various DOM structures, e.g. JSON, XML, etc.
        a sort of 'dom2data', if you will
    but, again, this would require completely cutting off the possibility of doing field references
        unless we can find some way to split the difference and maybe augment the the DOM nodes for the target parser and attach the additional 'binding' member
            this would be an interesting test case, but I'm not sure that Jai quite has a means to poke a data member into a struct from another module
            we could also just store the node->data binding relationship in a separate array, then iterate over this array upon evaluation.
            the propblem with that thouhg, is how to maintain a sort of hierarchical control now that the evaluation is decoupled form the DOM itself....
        

Another option, not really for GON, but for LSD with regard to field references would be to export the binding's names to the script as variables and just allow the user to access the bindings form teh text of the script directly.
this put a little more burden on the script context o provide all the right bindings, but that's pretty much already the direction that LSD is going, so no biggie i think


    
    



unfinished blog post thing:


# Why use a DOM instead of SAX-style parsing?

This question has been a constant in my mind while developing, porting, refactoring, and completely rewriting (several times) various GON parsers in various languages.
(I've taken this thing from C++ to C#, to C, to Jai, to Odin, and back to Jai, with complete overhauls at various stages.)
Well it comes down to basically just a couple reasons, but before I expound on those I'll explain the draw of using a SAX parser in the first place, in case you're not familiar with the concept.

## The Appeal of SAX    

(Thanks a lot tsoding, for sending me on this mad quest.)

The term SAX refers to [Simple API for XML](https://en.wikipedia.org/wiki/Simple_API_for_XML), an XML parser based around using a bunch of event callbacks to tell the parser what to actaully *do* as it reads through a file.
It's honestly sort of like just having a tokenizer, but the control is really inverted because instead of asking the tokenizer for tokens, the parser ask you what to do when it encounters all the file's *stuff*.
(I'm explaining this very poorly, but I linked the Wikipedia article, so you can actually just read that if you care. You have agency and such.)

I never actually used SAX myself, but I got the vague idea of what it's going for and thought that it would be just a lovely way to rewrite my GON parser (at this time, in C).
See, while I was writing my C implementation, I had originally gotten some big idea about how I would 


## Why Not

1. decoupling the GON document's structure from the data's internal structure
    
    In the SAX parser, evaluating paths to specific fields is not really as straightforward as one might think. 
    You have to do this weird sort of thing of tracking how far you currently are down each path as you step into and out of objects and arrays.
    And then when you get to the end of a given path, you've got to mark that path as complete in some way.
    It's not like it's particularly difficult logic to deal with, it's just kind of weird and finnicky.
    
    

2. symmetry between parsing and serialization
    
    Parsing/serialization is essentially a process of mapping one recusive structure onto another recursive structure.
    And when when performing this kind of a mapping procedurally, we have to choose which structure's navigation will control the flow of the program.
    This is very important to keep in mind because this brute fact creates a necessary asymmetry between parsing and serialization.
    
    For a more simple example of what I'm trying to get at here, consider iterating over two parallel arrays, where we want to map elements from one array onto the other:
    So we have our arrays:
    ```
    foos: [8] Foo;
    bars: [8] Bar;
    
    for foos  bars[it_index] = foo_to_bar(it);
    ```
    Great, easy peasy. But notice that we could also have written it differently, making the iteration of `bars` 'authoritative'.
    ```
    for *bars  it.* = foo_to_bar(foos[it_index]);
    ```
    Or, more neutrally:
    ```
    for 0..7  bars[it] = foo_to_bar(foos[it]);
    ```
    With two arrays of equal length, we have a 'one-to-one onto' mapping, which gives us lots of options about how to express that mapping procedurally in code.
    It doesn't matter which 
    
    
    
    Because SAX-stye parsing is highly linear, whatever wiggle room that we have when parsing
    Although SAX-style parsing is highly linear, perhaps you can see how we have a little bit of wiggle room and ability to 
    
    
    
    Serializing data structures directly into GON is very simple, and could even be implemented just thorugh some custom strucut formatting print rules.
    However, serializing to specific field paths is quite complicated, since we now need to keep track of where we are in the output file, and constantly check if other data bindings want to poke something in at the current path.
    
    Maybe this seems like a weird edge case or non-issue to you, but consider the following GON file:
    ```
    
    
    ```
    
    
3. simplicity (in some dimension)

    For parsing, my old SAX implementation was certainly less code than even my current DOM implementation.
    
    The DOM implementation gets a big simplicity boost with the addition of the flat pool allocator.
    Not having to really think about freeing node anymore just lifts off 90% of the additional mental burden that the DOM implementation would otherwise have over the SAX-style parser.
    
    
4. (bonus reason, because it's not really applicable anymore) extra features

    The main reason I went back to using a DOM in the first place was because I wanted to be able to evaluate references between fields, and this is not really possible in SAX-style parsing.
    By references, I mean being able to use some special syntax and a field path string to get the value, index, or a pointer to another field in the file.
    This may seem somewhat trivial, and for a DOM parser, it is. But not so for SAX.
    Implementing forward-references is not to hard with SAX-style parsing, 
        since you can just make a note to update the value of the referee when the referent is found.
    But because the parser only goes forwards, there's no way to make reference to fields found earlier in the file.
    
    Now, I may have gone a bit *too* ham on field references when I first implemented them in GON, particularly with value references.
    In addition to value references on individual fields, I implemented value references on objects, 
        which involved cloning entire subtrees on the DOM and pasting them into other places.
    And this means that the process of resolving field references becomes an iterative solver, 
        since we can end up in situations where we have a reference to with some path which does not yet exist, 
        but will exist after we clone some child nodes onto a different parent.
    While all of this worked, and the feature was pretty cool, it added too much additinal code (and complexity) to the module, 
        which I do not feel was justified by the marginal usefulness of the feature.
    
    And so, here we are now. I have ripped out all of that and more, and the parser is back in a more manageable (and readable) state.
        The focus now is to take the opportunity afforded by that newfound simplicity to 
    
