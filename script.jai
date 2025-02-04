
/*
    Lead Sheets integration in GON
    
    during tokenization, add CODE type
    mark CODE flag on dom nodes
    
    then the hard part, taking code form dom nodes and turning into statements in a scingle script
    we will have to add callbacks in Lead Sheets to resolve identifiers
    will have to figure out how to track dependencies between nodes
    then use the dependency graph to order the statements in the generated script
    the gon format is highly declarative, 
    
    need to add some way that identifiers can be arbitrary strings in lead sheets
        maybe enclosed in backticks?
            need to flag the identifier as being backticked
        these backticked identifiers will be used for field paths in the ogn file
        
    for now, require that all code in gon files are simple expressions
        each expressino is RHS of assignment statement to node data binding
            btw, pointer to each statment node needs to go on each gon DOM node
        node data bindings are added as external variables
            proabbyl have to add them all before cstarting the parsing of individual CODE expressions
            then after we have all statements, reorder based on dependencies
            for each node, move each node directly after a node it has a dependency on
                this will probably be sufficient to sort the statements
                    if there are cycles, error out
                        we will know this because we will be able to search back up the stack to previous dependent
    
    need to refactor how dependencies are searched currently to the recursive model instead of iterative model, since we proabbyl will need to be able to interleave the normal reference checking and the script depndencies
*/



