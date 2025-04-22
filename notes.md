

## TODO

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



## Integrating Scripts

While I would love to use gon for doing things like defining Enemy_Templates in my mario ripoff engine,
    it's currently not feasible to do so because I need to be able to compute certain vlaues based of off other values.

I could implement some very basic expression parsing and evaluation into GON directly, 
    but since I've been on a kick of offering optional integration between my various modules,
    it seems sensible to just use Lead_Sheets for the job.
    
In order to make this fully optional and unobtrusive though,
    I need to have some basic facility for tokenizer callbacks.
    This is an idea I had before, but basically it would just allow the user to use a single character token (e.g. `!`)
    that would take away control flow from the GON tokenizer and hand it over to the user.
    Once the user returns control, they should also return an Any with the value for the node.
    This Any could be of a special type that the user can recognize and intercept later when resolving data bindings.
    
    Now presumably we would also want to be able to get around the dom nodes when evaluating a script
    for example, we would want to be able to resolve field refs that are embedded inside a script
    which in turn would require some special parsing and typechecking on the lead sheets' side
    So in order to make all this work, we need to have a very solid interface for both the GON DOM and Lead Sheets AST.
    
    
### Tokenizing

Whether we hand control back and forth between tokenizers or not will depend on a few factors.
1. What is the desired syntax for the embedded expressions/scripts?
2. How will we go about evaluating the expressions?
3. How will expressions refer back to DOM nodes?


### Desired Syntax

Ideally the syntax for embedded expressions would be as simple as just enclosing the expression in parentheses.
```
gladiator {
    health 5
    stamina 7 
    magic_stamina (stamina * 2)
}
```
Very stupid example, but it gets the point across.
Basically, since parentheses are the only common structural tokens that I have not yet used, they would make a good fit for expressions

### Random Implementation Notes

I think we will need a better interface in lead sheets for doing only expressions after all
unless we just desugar all expressions into assignment statements by pulling the data binding from corresponding node

Combining the GON format with lead sheets is basically creating a whole little scripting language at this point
GON was supposed to be just simple data markup
and lead sheets were supposed to be just simple expressions, with the only data types being externally defined
but putting the tow together, I almost have a very simple javascript ripoff
now, the benefit is still that I can lean heavily on the typeinfo system in Jai and using actual Jai procedures
but still, there's definitely more complication here than is ideal

so on another note, I think I want to tak time at some point to rewrite or just generally improve the old sax style jai gon parser
because perhaps someone else will just appreciate the simplicity of that version more...
    I think it basically just needed a better interface and a better tokenizer to be MVP?

I think I need to go work on other things and then come back to this. 
both the gon parser and lead sheets are not developed enough at this point to start nailing down aspects of cross-functionality

lead sheets could already sort of do the job of setting up data in the way that gon does 
by just binding all the top level data bindings as variables, then using nested struct literals
    but the syntax is not quite as nice for doing simple data definition
    and we don't get the non-linear evaluation of field refs
        but is that such a bad thing to lose?
            yeah, bc e.g. tiles in mario game that need to reference one another circularly




integrating with lead sheets

will require being able to insert statements into script manually, without parsing directly from one source file
should jsu tbe able to create the assignment expression node manually, then parse_expression on the expression from gon file
then put the newly created statement into the main root block

```
parse_source_file :: (script: *Script, source: string) -> bool {
    if !(script.flags & .INITIALIZED)  return false;
    
    success: bool;
    defer if !success  free_script(script);
    
    script.ast_root = alloc_node(script, Node_Block);
    script.current_scoope = script.ast_root;
    
    // Split here, this is where we will manually add nodes to ast root block
    // so basically above, we will jus tinit and then alloc root node
    // perhaps we should just move the allocation of the root node to the init proc anyhow...
    
    if !typecheck_script(script) {
        log("Error: failed to typecheck script.\n");
        return false;
    }
    
    success = true;
    return true;
}
```

```
assignment := LS.alloc_node(script, Node_Operation)
assignment.name = "=";
assignment.operator_type = .ASSIGNMENT;
assignmnet.flags |= .MUST_BE_STATEMENT_ROOT;
assignment.left = gon_node.data_binding;

script.lexer.file = gon_node.value.text;
LS.init_lexer(&script.lexer);
assignment.right = parse_expression(script, 0);

// TODO: get last statement node in ast root
//       probably keep track of this on GON side, since we don't store that in LS script explicitly
last_ast_node.next = assignment;
```

step 1 may be just to make the make the expressions work
    no ability to reference other fields yet
    no order of evaluation concerns
step 2 is implement the references by hijacking identifier resolution and inserting declarations as needed
step 3 is fix the evaluation order by tracking dependencies between nodes


```
resolve_gon_path_identifier :: (path: string, dependent: *DOM_Node) -> (data_binding: Any, ok: boolb) {
    // if there is no data binding, we should probably still be able to use the value on the node as whatever it is textually.
    // so we will try to parse it as a number/string.
    // in theory we could allow using objects and arrays as well if they can have a type hint provided by lead sheet, but that it probably a really messy idea...
    
    gon_node := find_node_by_path(path);
    if !gon_node {
        // log error
        return Any.{}, false;
    }
    
    // not sure if we want to do this here or not? 
    // but where else... need data binding as resolution to identifier, not dom node.
    // but maybe we just put the dom nodes as resolved type of identifier for now, and then fix that in typecheck pass?
    // not really sure on this one...
    if gon_node == dependent {
        // log error
        return Any.{}, false;
    }
    
    if gon_node.data_binding.value_pointer != null  
        return gon_node.data_binding, true;
    
    if gon_node.type 
}

```


```
for n1: script.ast_root.statements {
    for n2: script.ast_root.statements {
        if 
    }
    
}

```


We have a problem in trying to refactor the node reference validation from an iterative approach to a recursive one:
    When trying to find a referenced node by its path, we may not be able to find a node on the first pass because it does not *yet* exist, but will exist after a later object reference is evlauated
    since object refs can add new nodes onto the DOM by copying from one location to another.
    
So at least for now, it may not really be possible to change honode refs are evaluated.
but maybe this is okay, and we can just evaluate all ref nodes before worrying about code expressions
that way, we can be sure that the DOM is stable and will have no further modifications by the time that the code expressions are evaluated

NOTE: it would be totally possible to do the fully recursive validation approach if it weren't for the object-type value refs
    maybe we should consider just ditching value-refs for objects? but that feels like a weird hole...

standard node references are resolved iteratively, since new nodes may still be added to the DOM as references are resolved.
However, by the time we start trying to construct a script for the expressions on GON nodes, the DOM is stable and will not have new nodes added
so we are free to resolve the references in code expressions more straightforwardly 


THINKING

are we really sure that value refs are properly evaluated in an order-independent manner? 
    this is really pretty important, since it would be nonsensical to have the meaning of gon change based on the order of objects
    I think that this is the case, because we dont' allow a value ref to a value ref to be resolved
    

what happens if we have a value ref to a code node?
we can't evaluate that data binding until after the code for that node is evaluated...
this is really not nice because this means we can just cleanly eval the normal data bindings and then run the script after the fact.
and we also can't run the script before we do the data bindings because the normal nodes won't have had their values assigned to the data bindings yet...

maybe we could run the script first, but then early evaluate any bindings that are referenced in code
so these nodes would need to be flagged as having already had their data bindings evaluated, so that we don't repeat that when we walk the tree

OR maybe we really just don't want to even walk the tree to eval bindings
maybe we should just create a linear array of dom nodes to evaluate and reorder those based on dependencies



get all statically known nodes out of the way 

then we only have to worry about ordering value refs and code nodes

still do iterative thing for solving refs, since these can modify dom

then we can worry about finding dependency chain for each of value refs and code nodes
no dep chain means front of the line
    make problem smaller this way
    
then finally, order last nodes, some sort of simple bubble sort deal

value refs on their own dont have an evaluation order problem, only value refs ot code nodes
and this is really because of the code nodes, not the value refs
but in any case we cannot eval the refs' data bindings until after the ref'd code evaluates



then there's the identifier issue
so I think what we want to do here, even though its slightly a hack, is to just substitute the identifier node for an ANY literal.
The Any literal is already a bit of a hack, but it is super useful for this kind of manual node insertion stuff
and it makes the possibility of doing more of an eval rather than exec thing more plausible
    which may be desirable for the gon use case, since we just exec each statement once



New syntax for LSON:
```
// normal c-style comments

// field name and value must now be separated by colon
// fields must be separated by commas (no penalty for extraneous comma in objects)
things: {
    `Thing 1`: {
        number:     100 + 5,        // expressions don't need to be enclosed in parentheses
        friend:     &`Thing 2`,     // 
    },
    `Thing 2`: {
        integers:   [ 1, 2, $'/things/Thing 1/'.number, 4, 5 - 1 ],
        color:      RED,
        text:       "this is a string",
    }
}
```

Not yet sure if I want to enforce that string-like identifiers use backticks or can also use normal quotation marks
reason being that we want to use identifiers as field paths in value expressions, since otherwise there's ambiguity over what's just a string and whats a field name
we could just makethe ref (`$`, `&`, and `*`) operators act on strings and return a node
    this could be better if we still need to solve file iteratively
        since we don't need to re-typecheck each time we exec if we evaluate a field path dynamically as an operator anyhow.
        
even if we use normal identifiers and subscripting to navigate the dom in value expressions, 
    we still have the issue of getting from to a parent node from a child node
    we could implement this with a unary operator as well, but what syntax to use? maybe prefix `^` with really high prec
    
    





## Field ref operators in LSD

for this we want ot implement an operator that is actually aware of node type instead of just value type
but this is not currently supported....

could return value type of `DOM_Node` when resolving identifier
    but then we can't just use the data binding directly...
    we would need some operator to get the data binding as well, which we *could* do with `$` or something
        i don't exactly like that, but it may be the easiest option
    this is probably the way to go for now until I hav ebetter options
    we would need to be able to resolve some operators as if they were directives,
        and I don't want to do that unitl I fix and refactor directives anyhow
        

we can't exactly use normal operator overloading for this because that would give us the data bindings with a value type of Any, which we don't want.

so for now we will actually just have to walk nodes and really hack the operators and force resolve them to the dom node operators we need




we can now reimplement these using directives
    in the future, would be nice to have the single character operators for syntax again, but in the mean time its a fair compromise to use `#identifier` directives instead, for the sake of consistency
    `#index`, `#address`, `#value`



We should just rewrite the gon parser to use the Lead sheets lexer directly, that way there's not the silly handoff logic required to switch back and forth

we probably still want to be able to disable certain LS language / syntax constructs with a flag so that those are handled purely by GON
    wonder where I put my notes about the syntax of brackets and braces in LS vs gon
        probabyl in wonky kong notes ngl
            ah yeah, here they are...
            
            
`&&` operator (or otherwise) for doing struct merging in gon
    then enforce single-assignment, no aliasing of fields/data bindings
    
GON / LSD needs a general overhaul to clean up the codebase
    tighter integration of DOM nodes and expresison nodes, use a common pool for allocation
    better typehchecking for field references
    becuase we now have actual struct literals in LSD, there is no real reason to use GON arrays for structs
    also, the current fact of syntactic difference in GON / LS using many of the same tokens is mildly confusing
    concerns:
        more tightly integrating LS with GON could make it more difficul to serialize data
        how to disambiguate/disentangle structs in expressions vs GON objects/arrays
            the trick here is that we really don't need the dot-brace syntax in LSD / GON since the only type of scopes that we have are data scopes
            and as far as gon markup is concerned, the clearest use of brace vs brackets is to denote when we are parsing key/value pairs or just value
            for the sake of a declarative data file format, this is more desirable that allowing the 'maybe expressions, maybe declarations' sort of struct literals that Jai uses
            so we will probably want to just adjust the syntax of struct literals in LSD such that they use brackets instead of braces
                (and anyhow, we don't actually have array literals in LS, nor will we likely ever have them. so perhaps we are more free to use brackets for 'user-level' syntax)
                
remove need for io data in some aspects
    since LS now allows for much more expressive parsing that simple GON, we coudl actaully remove the need for certain io data stuff by using simple annotations in the data file itself
    for example, indexed arrays
        no reason we should have to mark them explicitly as such, could either make that totally implicit when an array is bound to a GON object,
        OR we could add some supporting syntax like a `#` before the array to denote that it's indexed
            still, there's some tricky situation there when it comes to enum-indexed arrays, as we still need some way to explicitly tell what enum type to use
            and in that case the io data still seems ideal...

figure out how to do serialization goodly now that things have changed so much
    the proper answer will probably be just giving the user some kind of get_nodes() callback in serialization io_data, for the most general case
    we will want to be able to write out certain fields as LS expressions, just as we can read them in as such
    now a nice general-purpose solution should exist for the simple cases where we just serialize as before, name and data binding value

    for certain applications, we may actaully want to keep entire GON source files loaded in as DOM while the program runs, so that we can also use GON or LSD data in the same way as I plan to use scripts, making them sort of living data
    because as soon as we drop the DOM after parsing, we loose all information about the expressions we had for a file
    and perhaps we want to be able to back-propogate some stuff liek in LS (malleable literals) but make it more generic and automatic in GON

    in any case, I am definitely getting ahead of myself here again, and in all likelihood, LSD files will be used almost exclusively as read-only data
    I don't see myself writing over most of my data files like entity_templates or tilesets, but may do so for simple things like palettes which won't use complex expressions anyhow

maybe add some directive to top of GON file (or use different file extension) which denotes that a file will be "dumb"
    which is to say that it will only use value expressions (a single literal), and will not use field references
    maybe this would allow us to parse faster by just skipping expression parsing entirely and only using set_value_from_string ? 




so the consistent thing to do for LS/GON integration is to disable parsing of struct literals in LS, and instead 
    probably also need to disable blocks at expression-level, since those also conflict syntactically

or, maybe we can somehow leverage named blocks already existing as a syntax construct ?

nah.... but we do really want a more integrated node AST for this as well, like we have for the Java mapper thing
    but for the sake of generalized expressions, it's still quite necessary to have struct literals
    so we need a syntax that works for both that and gon object/array 
    
    maybe we can just always allow a type identifier (or typeexpression in parenthesis) before either a `{...}` or `[...]` block
    and maybe we do also use `{}` only for structs and `[]` only for arrays, so that we can still create array literals for e.g. passing to procedures
        we could allow using either one for either one, and make it syntactic-based, but that feels kind of bad?
        honestly if we get this far it's not too big of a deal to try either way. there's already a lot that we would have to do just to refactor GON enough for this.
    the real tricky thing about using either syntax thing for object/array literals is that we will probably ultimately need custom node types, which means callbacks in LS for parsing, typechecking, executing
        not like that's gonna be a *huge* deal though, and should be a good opportunity for development
        
so baby steps are:
    remove gon lexer entirely (or what's left of it)
    lex gon files entirely with LS lexer (no handoff)
    


not sure yet how to typecheck the dom
    can't really reference nodes inside of an object by path if that object is assigned some merged object value
        this isn't a thing yet, but it surely will be




refactor notes

overall flow
    1. parse the dom out like before
    2. append data bindings
    3. typecheck
    4. evaluate

this process is frustrating me a bit, even though it's more or less coming along
before we can really fully integrate the typechecking and evaluation of Gon nodes with normal LS nodes, we will need ot implement a few things on the LS side
    1. evaluation callbacks, so that we can just call evaluate_node on the dom root
    2. parsing callbacks and some way to disable parsing certain types of language constructs
        - specifically, we want to disable struct literals and add in the ability to parse objects / arrays instead 
        - we only need to disable things that are expression-level constructs atm, since we will only be calling parse_expression form GON
        - we will only need ot hook into parse_leaf witha callback atm, though maybe later we will need to extend some other parsing proc     

we now have the abiltiy to override the parsing and lexing procedures used by LS
and we have callbacks for parsing and evaluation

we need to now remove as much code as possible from the gon module and maybe reorganize what's left
we also need to refactor the evaluation stuff for LS so that the error handling is cleaner
    also might want to find a way to automate the hint_storage handling

then we can think about making gon objects and arrays work as arbitrary expression values
    with some added comptime operators for patch/merge type behavior

maybe make arrays work in arbitrary expressions first, since this will be very similar to struct literals
    main issue will be not being able to provide an explicit type...





