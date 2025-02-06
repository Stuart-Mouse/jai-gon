

Parser_Callback :: #type (*DOM_Node) -> bool;

// Parser_Flags :: enum_flags {
//     SKIP_PATHS_WITHOUT_BINDINGS;
// };

// used to build a DOM from a text file and evaluate data bindings on that DOM
Parser :: struct {
    tokenizer:          Tokenizer;
    dom_root:           *DOM_Node;
    node_pool:          Flat_Pool;
    node_allocator:     Allocator;
    callbacks:          [..] Parser_Callback;
    
    #if USING_LEAD_SHEETS {
        // TODO: could we use just portions of script? will require refactoring LS internals
        script:         LS.Script;
    }
};

init_parser :: (using parser: *Parser, _file: string) {
    reset(*node_pool, overwrite_memory = true);
    node_allocator = .{
        proc = flat_pool_allocator_proc,
        data = *node_pool,
    };
    tokenizer.file = _file;
    init_tokenizer(*tokenizer);
}

deinit_parser :: (using parser: *Parser) {
    fini(*node_pool);
    dom_root = null;
    
    array_free(callbacks);
}

// creates a dom parser with the given parameters, intializes it, and constructs the dom from the given file
// after calling this, you can just add your data bindings and then process them
parse_file_to_dom :: (file: string) -> (Parser, bool) {
    parser: Parser;
    init_parser(*parser, file);
    
    if !construct_dom_from_gon_file(*parser)  return .{}, false;
    if !validate_node_references   (*parser)  return .{}, false;
    
    return parser, true;
}

/*
    We are no longer appending to a dynamic array of data bindings, instead just inserting those data bindings immediately when this is called by the user.
    Which is nice because that means we save a little bit of memory on that and we don't need the Data_Binding struct Anymore.
    We also don't have to split the path into substrings, since we just process it one piece at a time as we insert the binding.
*/
add_data_binding_to_dom :: (using parser: *Parser, binding: Any, path: string) -> bool {
    node := find_node_by_path(parser.dom_root, path);
    return add_data_binding_to_node(node, binding);
}

add_data_bindings_to_dom :: (using parser: *Parser, bindings: [] struct { binding: Any; path: string; }) -> bool {
    for bindings
        if !add_data_binding_to_dom(parser, it.binding, it.path)  
            then return false;
    return true;
}


generate_script :: (using parser: *Parser) -> bool {
    generate_statements :: (using parser: *Parser, node: *DOM_Node) -> bool {
        if node.type == {
            case .OBJECT; #through;
            case .ARRAY;
                for node.children  if !generate_statements(parser, it)  return false;
                
            case .CODE;
                // TODO: if node does not have data binding
                left := LS.alloc_node(*parser.script, LS.Node_Literal);
                left.literal_type = .ANY;
                left.any = node.data_binding;
                
                assignment := LS.alloc_node(*parser.script, LS.Node_Operation);
                assignment.name = "=";
                assignment.operator_type = .ASSIGNMENT;
                assignment.flags |= .MUST_BE_STATEMENT_ROOT;
                assignment.left = left;
                
                // we have to reinit lexer for every expression
                // TODO: set the lexer source location based on dom node?
                LS.init_lexer(*script.lexer, node.code.text);
                assignment.right = LS.parse_expression(*parser.script, 0);
                if assignment.right == null {
                    log("Error: unable to parse expression '%'.", node.code.text);
                    return false;
                }
                
                // used for walk_nodes callback, so that we can search for nodes from relative or absolute path
                parser_and_node: struct { dom_parser: *Parser; dom_node: *DOM_Node; } = .{ parser, node };
                
                LS.walk_nodes(*script, *assignment.right, (script: *LS.Script, ast_node: *LS.Node, data: *void) -> (bool, *LS.Node) {
                    using data.(*type_of(parser_and_node));
                    print("dom_node: %\n", dom_node);
                    if ast_node.node_type == LS.Node_Identifier {
                        path := ast_node.(*LS.Node_Identifier).name;
                        print("path: %\n", path);
                        ref_node := find_node_by_path(dom_parser, dom_node.parent, path);
                        if ref_node == null {
                            log("Error: unable to resolve node path '%'.", path);
                            return false, null;
                        }
                        if ref_node.data_binding.value_pointer == null {
                            log("Error: node '%' referenced in expression '%' had no data binding!.", path, dom_node.code.text);
                            return false, null;
                        }
                        literal := LS.alloc_node(script, LS.Node_Literal);
                        literal.literal_type = .ANY;
                        literal.any = ref_node.data_binding;
                        return true, literal;
                    }
                    return true, null;
                }, *parser_and_node);
                
                if !LS.typecheck_node(*script, assignment, .IS_STATEMENT_ROOT) {
                    log("Error: failed to typecheck expression '%'.", node.code.text);
                    return false;
                }
                
                // TEMP DEBUG PRINTING
                builder: String_Builder;
                dbg := LS.print_node(*script, assignment, *builder, 0);
                print("%\n", builder_to_string(*builder));
                
                node.code.statement = assignment;
                
            case .INVALID;
                log("Invalid node type in generate_script().");
                return true;
        }
        
        return true;
    }
    
    LS.init_script(*script);
    LS.register_type(*script, "float", type_info(float));
    
    // if !generate_statements(parser, parser.dom_root)  return false;
    // script.flags |= .PARSED | .TYPECHECKED;
    
    return true;
}


validate_node_references :: (using parser: *Parser) -> bool {
    Result :: enum_flags { NONE :: 0; ERROR :: 1; COMPLETE; PROGRESS; REMOVE_NODE; };
    
    recurse :: (using parser: *Parser, node: *DOM_Node, unresolved_refs: *[..] *DOM_Node) -> Result {
        if .REFERENCES_RESOLVED & node.flags  return .COMPLETE;
        
        if node.type == {
          case .CODE; #through;
          case .FIELD;
            node.flags |= .REFERENCES_RESOLVED;
            return .PROGRESS | .COMPLETE;
    
          case .OBJECT; #through;
          case .ARRAY;
            result: Result = .COMPLETE;
            for child: node.children {
                child_result := recurse(parser, child, unresolved_refs);
                if .ERROR       & child_result  return .ERROR;
                if .REMOVE_NODE & child_result  remove;
                result |=  child_result & .PROGRESS;
                result &= (child_result & .COMPLETE) | ~.COMPLETE;
            }
            if .COMPLETE & result {
                node.flags |= .REFERENCES_RESOLVED;
            }
            return result;
                
          case .REF;
            path := node.ref.text;
            if path == "" {
                log("Empty reference on node '%'.", format_node_path(node));
                return .ERROR;
            }
            
            ref_node := find_node_by_path(parser, node.parent, path);
            
            if ref_node == null {
                // We just hold onto this until later, then if we really fail to resolve references, we print all nodes with unresolved refs at once.
                array_add_if_unique(unresolved_refs, node);
                return .NONE;
            }
            node.ref.node = ref_node;
            
            // pointer and index refs can be passed along and handled later
            if node.ref.type != .VALUE { 
                node.flags |= .REFERENCES_RESOLVED;
                return .PROGRESS | .COMPLETE;
            }
            
            // value ref to value ref cannot be resolved yet
            if node.ref.node.type == .REF && node.ref.node.ref.type == .VALUE {
                array_add_if_unique(unresolved_refs, node);
                return .NONE;
            }
            
            result: Result = .PROGRESS | .COMPLETE;
            
            if .BIND_PARENT & node.flags {
                assert(ref_node.type == .OBJECT, "ref node with bind parent flag was not pointing to an object.");
                
                // we can't copy these nodes until they are all resolved, otherwise we get issues
                if !(.REFERENCES_RESOLVED & ref_node.flags)  return .NONE;
                
                parent := node.parent;
                for child: ref_node.children {
                    dst := find_child_node_by_name(parent, child.name);
                    if dst != null  continue;
                    dst = append_child_node(parent);
                    if !clone_node_recursive(dst, child,, node_allocator)  return .ERROR;
                }
                result |= .REMOVE_NODE;
            }
            else {
                name := node.name;
                if !clone_node_recursive(node, ref_node,, node_allocator)  return .ERROR;
                node.name = name;
            }
            
            node.flags |= .REFERENCES_RESOLVED;
            return result;
            
          case .INVALID;
            log("Invalid node type in validate_node_references().");
            return .ERROR;
        }
        
        return .ERROR;
    }
    
    unresolved_refs: [..] *DOM_Node;
    defer array_free(unresolved_refs);
    
    iterations := 0;
    while true {
        iterations += 1;
        result: Result = .COMPLETE;
        for child: parser.dom_root.children {
            child_result := recurse(parser, child, *unresolved_refs);
            if child_result & .ERROR {
                log("Error while trying to resolve node references.");
                return false;
            }
            if child_result & .REMOVE_NODE {
                remove_node(child,, node_allocator);
            }
            result |=  child_result & .PROGRESS;
            result &= (child_result & .COMPLETE) | ~.COMPLETE;
        }
        if   .COMPLETE & result  break;
        if !(.PROGRESS & result) {
            log("Unable to resolve node references:");
            for unresolved_refs {
                if .REFERENCES_RESOLVED & it.flags  continue;
                log("\t% -> %", format_node_path(it), it.ref.text);
            }
            return false;
        }
    }
    
    log("Resolved node references in % iterations.", iterations);
    return true;
}

process_data_bindings :: (using parser: *Parser) -> bool {
    #if USING_LEAD_SHEETS {
        if !generate_script(parser) return false;
    }
    
    // TODO: here, we can now do the recursive, jump-around-the-tree sort of thing and detect dependency loops as we go.
    //       this is fine becuase now the tree is stable, even if we have remaining value refs, since those refs can only refer to code nodes
    //       and those code nodes are all basically single-valued fields, even if that single value is a struct or array
    //       now this does create a weird thing where the value refs to code nodes must pull the data binding, rather than pulling the value textually
    //       so it's more strongly typed by neccessity...
    //       wait maybe I'm dumb? if we value ref to a code node, perhaps we should just copy the code node and evaluate inplace? Or is that wierd?
    //       in any case, I think that is what I will do for now, as it makes sense for the ref to ALL function wrt the DOM structure, while code expressions operate wrt data bindings.
    //       so the refs are more like pre-processor macros
    if !process_node_binding(parser, dom_root)  return false;
    
    return true;
}

process_node_binding :: (using parser: *Parser, node: *DOM_Node) -> resolved: bool {
    // We set BINDING_RESOLVED on exit in any case, since we only process each node once, 
    //      and it either succeeds or everything fails.
    if .BINDING_RESOLVED & node.flags {
        log("Info: node '%' was already resolved.", format_node_path(node));
        return true;
    }
    defer node.flags |= .BINDING_RESOLVED; 
    
    // We set the PENDING_DEPENDENCY flag on this node only for the duration of this call
    //      so that we know if we visit it again, we have gone in a loop.
    // TODO: would be better if we explicitly track the dependency chain so that we can print a better error here
    if node.flags & .PENDING_DEPENDENCY {
        log("Error: cyclic dependency on node '%'.", format_node_path(node));
        return false;
    }
    node.flags |= .PENDING_DEPENDENCY;
    defer node.flags &= ~.PENDING_DEPENDENCY;
    
    
    // TODO: reimplement callbacks here
    
    if node.type == {
      case .OBJECT; #through;
      case .ARRAY;
        for node.children
            if !process_node_binding(parser, it)
                return false;
        return true;
        
      case .FIELD;
        return node.data_binding.value_pointer == null 
            || set_value_from_string(node.data_binding, node.value);
        
      case .REF;
        assert(node.ref.node != null, "ref node was null");
        if node.ref.type == {
          case .INDEX;
            // TODO: expand index ref to also work on enums and map keys
            if node.data_binding.value_pointer == null  return true;
            if !is_numeric_type(node.data_binding.type) {
                log("Error: cannot assign node index to a data binding with non-numeric type. Node path was '%'.", format_node_path(node));
                return false;
            }
            if !remap_data(node.data_binding, get_node_index(node.ref.node)) {
                log("Error: remap_data failed for index ref on node '%'.", format_node_path(node));
                return false;
            }
            return true;
            
          case .POINTER;
            if node.data_binding.value_pointer == null  return true;
            if node.ref.node.data_binding.value_pointer == null {
                // TODO: have some option for this to be an error
                log("Warning: no data binding on pointer ref node '%'.", format_node_path(node));
                return true;
            }
            
            // COME BACK HERE (LATER: AND DO WHAT?)
            ref_ti     := node.ref.node.data_binding.type;
            binding_ti := node.data_binding.type.(*Type_Info_Pointer).pointer_to;
            if ref_ti != binding_ti {
                log("pointer type mismatch % vs %", ref_ti, binding_ti);
                return false;
            }
            node.data_binding.value_pointer.(**void).* = node.ref.node.data_binding.value_pointer;
            return true;
            
          case .VALUE;
            log("ERROR: got a value ref in process_node_binding. This should have already been resolved in validate_node_references.");
            return false;
        }
        
      case .CODE;
        if node.data_binding.value_pointer == null {
            return true;
        }
        // TODO: if node does not have data binding?
        // NOTE: Code expressions are not even parsed and evaluated if they don't have a data binding
        
        left := LS.alloc_node(*parser.script, LS.Node_Literal);
        left.literal_type = .ANY;
        left.any = node.data_binding;
        
        assignment := LS.alloc_node(*parser.script, LS.Node_Operation);
        assignment.name = "=";
        assignment.operator_type = .ASSIGNMENT;
        assignment.flags |= .MUST_BE_STATEMENT_ROOT;
        assignment.left = left;
        
        // we have to reinit lexer for every expression
        // TODO: set the lexer source location based on dom node?
        LS.init_lexer(*script.lexer, node.code.text);
        assignment.right = LS.parse_expression(*parser.script, 0);
        if assignment.right == null {
            log("Error: unable to parse expression '%'.", node.code.text);
            return false;
        }
        
        
        // used for walk_nodes callback, so that we can search for nodes from relative or absolute path
        parser_and_node: struct { dom_parser: *Parser; dom_node: *DOM_Node; } = .{ parser, node };
        
        walk_proc :: (script: *LS.Script, ast_node: *LS.Node, data: *void) -> (bool, *LS.Node) {
            using data.(*type_of(parser_and_node));
            if ast_node.node_type == LS.Node_Identifier {
                path := ast_node.(*LS.Node_Identifier).name;
                
                ref_node := find_node_by_path(dom_parser, dom_node.parent, path);
                if ref_node == null {
                    log("Error: unable to resolve node path '%'.", path);
                    return false, null;
                }
                
                if ref_node.data_binding.value_pointer == null {
                    // TODO: actually handle this case by creating instance of hinted type?
                    log("Error: node '%' referenced in expression '%' had no data binding!.", path, dom_node.code.text);
                    return false, null;
                }
                
                // jump to referenced node
                if !process_node_binding(dom_parser, ref_node) return false, null;
                
                literal := LS.alloc_node(script, LS.Node_Literal);
                literal.literal_type = .ANY;
                literal.any = ref_node.data_binding;
                return true, literal;
            }
            return true, null;
        };
        
        if !LS.walk_nodes(*script, *assignment.right, walk_proc, *parser_and_node)  return false;
        
        if !LS.typecheck_node(*script, assignment, .IS_STATEMENT_ROOT) {
            log("Error: failed to typecheck expression '%'.", node.code.text);
            return false;
        }
        
        // TEMP DEBUG PRINTING
        builder: String_Builder;
        dbg := LS.print_node(*script, assignment, *builder, 0);
        print("%\n", builder_to_string(*builder));
        
        node.code.statement = assignment;
        
        return LS.execute_node(*script, node.code.statement);
    }
    
    return true;
}

construct_dom_from_gon_file :: (using parser: *Parser) -> bool {
    next_token: Token;
    ok: bool;
    
    dom_root      = New(DOM_Node,, node_allocator);
    dom_root.name = "root";
    dom_root.type = .OBJECT;
    
    parent := dom_root;
    while L_Loop := (parent != null) {
        name, text: string;
        type:       Node_Type;
        flags:      DOM_Node_Flags;
        
        // field value ref without name inside an object will create an unnamed field with the same data binding as the parent object
        if parent.type == .OBJECT && peek_token(*tokenizer).type == .REF_VALUE {
            flags |= .BIND_PARENT;
        } else {
            // read field name
            if parent.type != .ARRAY {
                next_token = get_token(*tokenizer);
                if next_token.type == .ERROR {
                    log("GON tokenization error: Unexpected % token \"%\".", next_token.type, next_token.text);
                    return false;
                }
                if next_token.type == {
                  case .STRING;
                    name = next_token.text;
                    
                  case .EOF;
                    if parent != dom_root {
                        log("GON parse error: Unexpected % token \"%\".", next_token.type, next_token.text);
                        return false;
                    }
                    break L_Loop;
                    
                  case .OBJECT_END;
                    if parent.type != .OBJECT {
                        log("GON parse error: Unexpected % token \"%\".", next_token.type, next_token.text);
                        return false;
                    }
                    parent = parent.parent;
                    continue;
                    
                  case;
                    log("GON parse error: Unexpected % token \"%\".", next_token.type, next_token.text);
                    return false;
                }
            }
        }
        
        next_token = get_token(*tokenizer);
        if next_token.type == .ERROR {
            log("GON tokenization error: Unexpected % token \"%\".", next_token.type, next_token.text);
            return false;
        }
        
        if next_token.type == .REF_INDEX   || 
           next_token.type == .REF_POINTER || 
           next_token.type == .REF_VALUE {
            
            node := append_child_node(parent,, node_allocator);
            node.name  = name;
            node.type  = .REF;
            node.flags = flags;
            
            if next_token.type == {
              case .REF_INDEX;    node.ref.type = .INDEX;
              case .REF_POINTER;  node.ref.type = .POINTER;
              case .REF_VALUE;    node.ref.type = .VALUE;
            }
            
            next_token = get_token(*tokenizer);
            if next_token.type == .ERROR {
                log("GON tokenization error: Unexpected % token \"%\".", next_token.type, next_token.text);
                return false;
            }
            if next_token.type != .STRING {
                log("GON parsing error: Field ref path must be a valid string value.");
                return false;
            } 
            node.ref.text = next_token.text;
        }
        else {
            // read field value
            if next_token.type == {
              case .STRING;
                type = .FIELD;
                text = next_token.text;
              case .CODE;
                type = .CODE;
                text = next_token.text;
              case .OBJECT_BEGIN;
                type = .OBJECT;
              case .ARRAY_BEGIN;
                type = .ARRAY;
              case .ARRAY_END;
                if parent.type != .ARRAY {
                    log("GON parse error: Unexpected % token \"%\".", next_token.type, next_token.text);
                    return false;
                }
                parent = parent.parent;
                continue;
              case;
                log("GON parse error: Unexpected % token \"%\".", next_token.type, next_token.text);
                return false;
            }
            
            assert(type != .INVALID);
            
            node := append_child_node(parent,, node_allocator);
            node.name  = name;
            node.type  = type;
            node.flags = flags;
            if node.type == {
              case .OBJECT; #through;
              case .ARRAY;
                parent = node;
              case .FIELD;
                node.value = text;
              case .CODE;
                node.code.text = text;
            }
        }
    }
    
    return true;
}

add_data_binding_to_node :: (node: *DOM_Node, binding: Any) -> bool  {
    if node == null || binding.value_pointer == null  return true;
    
    if node.data_binding.value_pointer != null {
        log("Error, node already has a data binding set...");
        return false;
    }
    node.data_binding = binding;
    
    // If we re-implement the below code, we will need to update all the places below where we use binding instead of node.binding...
    // binding, _ = deref_any_pointer(binding)
    
    // make indirect bindings onto child nodes
    if node.type == {
      case .OBJECT;
        for child: node.children {
            if .BIND_PARENT & child.flags { // necessarily a value ref
                child.data_binding = node.data_binding;
            }
        }
        
        if binding.type.type == {
          case .STRUCT;
            io_data := table_find_pointer(*IO_Data_Lookup, node.data_binding.type);
        
            for child: node.children {
                member := get_field(xx node.data_binding.type, child.name);
                if !member  continue; // TODO: also check that member is non constant
                
                if io_data && io_data.name_member == member 
                    then node.flags |= .DONT_ASSIGN_NAME;
                
                member_any := Any.{
                    value_pointer = node.data_binding.value_pointer + member.offset_in_bytes,
                    type          = member.type,
                };
                add_data_binding_to_node(child, member_any);
            }
            
            // TODO: either just make this a condition for the below directly or set this flag from parent...
            if node.parent && (node.parent.flags & .ARRAY_INDEXED)
                then node.flags |= .DONT_ASSIGN_NAME;
            
            // we don't want to set the name member if the parent exists and is an indexed array, because then the gon name is being used for the index
            // we also don't want to set it if the name member has a binding to a child node
            if !(node.flags & .DONT_ASSIGN_NAME) {
                if io_data && io_data.name_member {
                    member_any := Any.{
                        value_pointer = node.data_binding.value_pointer + io_data.name_member.offset_in_bytes,
                        type          = io_data.name_member.type,
                    };
                    if !set_value_from_string(member_any, node.name) {
                        return false;
                    }
                }
            }
            
            
          case .ARRAY;
            ti_array := node.data_binding.type.(*Type_Info_Array);
            
            io_data  := table_find_pointer(*IO_Data_Lookup, ti_array.element_type);
            if io_data && (.ARRAY_INDEXED & io_data.parse.flags)
                then node.flags |= .ARRAY_INDEXED;
            else if ti_array.element_type.type == .STRUCT 
                then node.flags |= .ARRAY_AS_OBJECT;
                        
            if ti_array.array_type == .RESIZABLE {
                raw_array := node.data_binding.value_pointer.(*Resizable_Array);

                if .ARRAY_INDEXED & node.flags {
                    for child: node.children {
                        elem_index := to_integer(child.name);
                        elem_any   := array_add_any_at_index(node.data_binding, elem_index);
                        add_data_binding_to_node(child, elem_any);
                    }
                } else {
                    count_before := raw_array.count;
                    array_reserve_nonpoly(xx raw_array, count_before + node.count, ti_array.element_type.runtime_size);
                    raw_array.count += node.count;
                    for node.children {
                        elem_any := Any.{
                            value_pointer = raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size), 
                            type          = ti_array.element_type
                        };
                        add_data_binding_to_node(it, elem_any);
                    }
                }
            } else { // .ARRAY and .VIEW
                io_data := table_find_pointer(*IO_Data_Lookup, node.data_binding.type);

                elem_count, data := get_array_count_and_data(node.data_binding.value_pointer, ti_array);
                
                if io_data && (.ARRAY_INDEXED & io_data.parse.flags) {
                    node.flags |= .ARRAY_INDEXED;
                    for child: node.children {
                        elem_index := to_integer(child.name); // TODO: add error handling?
                        if elem_index >= elem_count {
                            log("Error: array index is out of bounds.");
                            return false;
                        }
                        
                        elem_any := Any.{
                            value_pointer = data + (ti_array.element_type.runtime_size * elem_index),
                            type          = ti_array.element_type,
                        };
                        add_data_binding_to_node(child, elem_any);
                    }
                } else {
                    if node.count > elem_count {
                        log("Error: too many elements in array.");
                        return false;
                    }
                    
                    if ti_array.element_type.type == .STRUCT {
                        node.flags |= .ARRAY_AS_OBJECT;
                        // TODO: also check the io data to see if name member is defined
                    } else {
                        log("Data binding error: object-type array must contain a struct with a defined name member.");
                        return false;
                    }
                    
                    for child: node.children {
                        elem_any := Any.{
                            value_pointer = data + (ti_array.element_type.runtime_size * it_index),
                            type          = ti_array.element_type,
                        };
                        add_data_binding_to_node(child, elem_any);
                    }
                }
            }

            /* 
                TODO: 
                GON objects can only validly be bound to arrays when the element type is a struct,
                or if it is an indexed array (where the name of each field is the index to which the value will be stored).
                So, we should perform a check to ensure that these conditions are met, else return an error.
                The user will have to state explicitly that they want to parse a given array binding as an indexed array, otherwise there is some ambiguity as to how to handle ths situation.
            */
            
          case;
            log("Invalid data binding, mismatched gon(OBJECT)/internal(%) type on node %.", (cast(*Type)*node.data_binding.type).*, node.*);
            return false;
        }
    
    
      case .ARRAY;
        if binding.type.type == {
            case .ENUM;
                ti_enum := node.data_binding.type.(*Type_Info_Enum);
                if !(ti_enum.enum_type_flags & .FLAGS) {
                    log("Data binding error: tried to bind an enum to an array on field %", format_node_path(node));
                    return false;
                }
                if node.parent.data_binding.value_pointer == node.data_binding.value_pointer {
                    return false;
                }
                for child: node.children {
                    add_data_binding_to_node(child, node.data_binding);
                }
            
            case .STRUCT;
                ti_struct := node.data_binding.type.(*Type_Info_Struct);

                if node.count > ti_struct.members.count {
                    log("Data binding error: array-type struct contains too many elements.");
                    return false;
                }
                for child: node.children {
                    // TODO: will need to to more work here because of constant struct members
                    member := ti_struct.members[it_index];
                    member_any := Any.{
                        value_pointer = node.data_binding.value_pointer + member.offset_in_bytes,
                        type          = member.type,
                    };
                    add_data_binding_to_node(child, member_any);
                }
                
            case .ARRAY;
                ti_array := node.data_binding.type.(*Type_Info_Array);
                
                if ti_array.array_type == .RESIZABLE {
                    raw_array := node.data_binding.value_pointer.(*Resizable_Array);
                    /*
                        IMPORTANT NOTE: 
                        
                        It is critical that the proper amount of space is pre-allocated for the dynamic array 
                        and that we don't have to realloc when we make data bindings for elements below.
                        Because if we realloc then that invalidates the pointers in the data bindings that we created
                        for all previous elements, since those are now pointing to the old locations of each element.
                        This may prove to be more fragile aspects of the DOM parser in contrast to the SAX implementation.
                        Because this definitely seems like something that a user could break through a problematic callback procedure.
                        
                        We could potentially fix this by changing how we store data bindings.
                        For array elements, instead of storing a pointer to data, store a pointer to a the base pointer and also element offset.
                        We could have a node flag to indicate that we should use this scheme instead of the usual one.
                        We won't do this unless we need to though. For now, the current method is fine.
                    */
                    count_before := raw_array.count;
                    array_reserve_nonpoly(xx raw_array, count_before + node.count, ti_array.element_type.runtime_size);
                    raw_array.count += node.count;
                    for node.children {
                        elem_any := Any.{
                            value_pointer = raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size), 
                            type          = ti_array.element_type
                        };
                        add_data_binding_to_node(it, elem_any);
                    }
                } else {
                    elem_count, data := get_array_count_and_data(node.data_binding.value_pointer, ti_array);
                    if node.count > elem_count {
                        log("Data binding error: bounds check failed on array or slice.");
                        return false;
                    }
                    
                    for child: node.children {
                        elem_any := Any.{
                            value_pointer = data + (ti_array.element_type.runtime_size * it_index),
                            type          = ti_array.element_type,
                        };
                        add_data_binding_to_node(child, elem_any);
                    }
                }
                
            case;
                log("Data binding error: mismatched gon(ARRAY)/internal(%) type on node %.", (*node.data_binding.type).(*Type).*, node.*);
                return false;
        }
        

      case .FIELD;
        if node.data_binding.type.type == {
          case .INTEGER;
          case .BOOL;
          case .FLOAT;
          case .STRING;
          case .ENUM;
            // For enum flags, both the enclosing array and the individual elements have the same binding
            // For fields, we must verify that the parent binding is the same as the field binding
            ti_enum := node.data_binding.type.(*Type_Info_Enum);
            if (ti_enum.enum_type_flags & .FLAGS) 
            && node.parent.data_binding.value_pointer != node.data_binding.value_pointer
                return false;
        
          case .ARRAY; 
            // Arrays of bytes/u8 are permitted as single-valued fields so that we can parse them as strings
            if node.data_binding.type.(*Type_Info_Array).element_type.runtime_size != 1  
                return false;
        
        // TODO: permit structs which have custom parsing procedures defined
        
          case;
            log("Invalid data binding, mismatched gon(FIELD)/internal(%) type on node %.", (*node.data_binding.type).(*Type).*, node.*);
            return false;
        }


      case .REF;
        if node.ref.type == {
          case .VALUE;
            log("ERROR: Trying to bind to a value ref node @ %!", format_node_path(node));
            return false;
            
          case .INDEX;
            if binding.type.type == {
              case .INTEGER;
              case .FLOAT;
              case .ENUM; // TODO: will need special handling here for enum-indexed arrays
              case;
                return false;
            }
            
          case .POINTER;
            // all we can do here is check that the data binding is actually a pointer type
            if binding.type.type != .POINTER  return false;
        }
        
        
      case .CODE; 
        // TODO: we probably need extra validation stuff here
        
      case;
        // TODO: invalid node type error?
    }
    
    return true;
}
