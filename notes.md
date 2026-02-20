
# Data Model Refactoring

I realized this a while ago, but now seems like a decent time to act on it:
The primary value of this module that I would like to package up in a way that others can use it is not primarily in it being a JSON / GON parser, 
it's in the work that it does to map a DOM structure into internal data structures. 
And that part of the code can be pretty cleanly separated from whatever language parser you want to use it in conjunction with.
It's really a lot like the convert module's remapping stuff, but with slightly looser structures involved.

So now I think the move is to really isolate that DOM to internal data structures part.

## TODO

Pass some flag for implicit vs explicit root object

Framework
    [x] serialization framework
    [x] submodule system
        [ ] find workaround for compiler warning 
        [x] handle single-files submodules in addition to folder-based submodules
    [x] logging system
        [ ] add proc to get last error message from model
    [x] lexer utilities

JSON
    [x] serialization
        [ ] handle all language flags
    [ ] test cases


XML
    [ ] parse attributes
        [ ] add proper handling for xml node types in data model
    [ ] parse CDATA
    [ ] parse header stuff
    [ ] add serialization

Languages to Add:
    XML
    Human JSON (just add config flags for json)
    YAML (1.2)
    TOML

dependencies
    figure out what to do about set_value_from_string
    try to clean up utils file and maybe put that stuff in a parser utils module. i dunno.


Marshaller (for immediate-mode data processing)


support parsing of hex floats in parse_number






## Marshaller 

the interface between the marshaller and the language should be roughly the same for both parsing and serialization
but the queries the marshaller will make to the type info and io_data in either case will vary

marshaller <--> language
    begin_object / end object
    begin_array / end_array
    begin_field / end_field (also, put_field as a convenience)
    put_attribute

serializer interface:
    io data --> marshaller
        preferred_node_kind
        
    
parser interface:
    on_bind(node, binding) -> idk yet
    get_member(name, index) -> bool, Any
    from_string
    


## Node Kind

Now, the strict distinction between simple and aggregate types is unfortunately a bit blurrier, since in languages like XML, 
there is almost no syntactic difference between single-valued and multi-valued tags.
Maybe the solution will be just make Kind a u64 and let the language store its own tag in there.
That way the tag is still useful for differentiating node types, but only on the level of a single language.
The only problem with this approach is that we cannot then use the same data model as a sort of IR between two langauge, say JSON and XML.
This seems like it would be a rather useful feature, so I will try not to preclude its inclusion for the time being...


## High-Level Design

language (parser + lexer) -> data model -> internal structures

langauge (parser + lexer) -> data model is the simplest part. mostly just requires that our data model can represent the semantics of the language

data model -> internal structures is more involved because we want a lot more user control at this stage


in addition to the stuff that can be configured on a per-language basis, we will want to have some other interfaces for things that work globally
maybe these things can just go in the context 
    one example is things like a generalized set_value_from_string that will be used for instances like setting the name member of a struct
    on second thought, maybe this can just go in io data. IDK


## Language & Data Type Extensions

The module will take program parameters indicating submodules to include in the build.
Haven't seen another module do this before, but it seems like a nice way that I can just include whatever little helpful extras I want to without forcing other users to include that code in their project.

TODO: create a base logging system that each language implementation will call through to report logs.
      we want to have relatively standardized formatting and such







What we really want here is something like a Data_Model struture that we acts as the intermediate between any file format and 

augment the lexer/parser to support proper JSON

then allow for the particular language to be more decoupled so that we can implement XML, YAML, and other languages as well

hash map support
    may be problematic that we separate placement and evaluation of bindings
    can we iterate children twice, inserting all elements and then doing bindings?
    we should be able to reserve space up front so that the table does not realloc while we insert the placeholder values for each key
        (while testing we should have some logic to verify this)
    and then we can just handle child bindings as per usual

tagged_union support
    needed in convert.jai as well, probably do it there first 

add a generic value type similar to what Jaison has with JSON_Value

reimplement a macro-based parser


## Doumentation for Node Kinds

The kind specified for a node may mean slightly different things or be handled differently depending on the language used.
The three basic node kinds (FIELD, OBJECT, and ARRAY) are derived from the structure of JSON.

A FIELD is single-valued, and generally has no child nodes. 
    (I say generally because we do actually allow child nodes on a field for the sake of enum_flags and other 'single-binding but multi-valued' types.)
    JSON and GON do not support this syntax by default, but you can enable it if you so wish.

An OBJECT is a multi-valued type in which all child nodes are expected to have a unique name.

An ARRAY is a multi-valued type in which child nodes are not expected to have a name.

JSON will not parse anything into an ATTRIBUTE, but it will serialize attributes as though they were just regular child nodes, optionally with some special prefix attached.











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

