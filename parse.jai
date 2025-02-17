

Parser_Callback :: #type (*DOM_Node) -> bool;

// used to build a DOM from a text file and evaluate data bindings on that DOM
Parser :: struct {
    dom_root:           *DOM_Node;
    node_pool:          Flat_Pool;
    node_allocator:     Allocator;
    callbacks:          [..] Parser_Callback;
    
    // state pulled out from lexer
    file:               string;
    cursor_location:    Source_Location;
    
    // TODO: could we use just portions of script? will require refactoring LS internals
    script:             LS.Script;
};

init_parser :: (parser: *Parser, file: string) {
    // reset(*parser.node_pool, overwrite_memory = true);
    // parser.node_allocator = .{
    //     data = *parser.node_pool,
    //     proc = flat_pool_allocator_proc,
    // };
    parser.node_allocator = context.allocator;
    parser.file = file;
    
    LS.init_script(*parser.script);
    print("allocator: %\n", parser.script.allocator);
    
    // TODO: move this elsewhere, this is just for testing
    LS.register_common_types(*parser.script); 
}

deinit_parser :: (using parser: *Parser) {
    // fini(*node_pool);
    delete_child_nodes_recursive(dom_root);
    free(dom_root);
    dom_root = null;
    
    array_free(callbacks);
    
    LS.free_script(*parser.script);
}

// creates a dom parser with the given parameters, intializes it, and constructs the dom from the given file
// after calling this, you can just add your data bindings and then process them

// TODO: it is currently CRITICAL that this is an inline proc, since the allocators in the parser and script point to pools on the parser and script themselves, respectively.
//       this feels like maybe a bad thing, and perhaps both of these should instead just have the user set the allocator manually.
//       but on the other hand, using them with a pool is the most likely case, and shouldn't the default be nice to use?
parse_file_to_dom :: inline (file: string) -> (Parser, bool) {
    parser: Parser;
    init_parser(*parser, file);
    if !construct_dom_from_gon_file(*parser)  return .{}, false;
    return parser, true;
}

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

process_data_bindings :: (using parser: *Parser) -> bool {
    return process_node_binding(parser, dom_root);
}

process_node_binding :: (using parser: *Parser, node: *DOM_Node) -> resolved: bool {
    // We set BINDING_RESOLVED on exit in any case, since we only process each node once, 
    //      and it either succeeds or everything fails.
    if .BINDING_RESOLVED & node.flags {
        log("Info: node '%' was already resolved.", format_node_path(node,, temp));
        return true;
    }
    defer node.flags |= .BINDING_RESOLVED; 
    
    // We set the PENDING_DEPENDENCY flag on this node only for the duration of this call
    //      so that we know if we visit it again, we have gone in a loop.
    // TODO: would be better if we explicitly track the dependency chain so that we can print a better error here
    if node.flags & .PENDING_DEPENDENCY {
        log("Error: cyclic dependency on node '%'.", format_node_path(node,, temp));
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
        if node.data_binding.value_pointer == null {
            return true;
        }
        
        print("%\n", format_node_path(node,, temp));
        
        // used for walk_nodes callback, so that we can search for nodes from relative or absolute path
        parser_and_node: struct { dom_parser: *Parser; dom_node: *DOM_Node; } = .{ parser, node };
        
        walk_proc :: (script: *LS.Script, ast_node: *LS.Node, data: *void) -> (bool, *LS.Node) {
            using data.(*type_of(parser_and_node));
            if ast_node.node_type == LS.Node_Identifier {
                path := ast_node.(*LS.Node_Identifier).name;
                
                ref_node := find_node_by_path(dom_parser, dom_node.parent, path);
                if ref_node == null {
                    // log("Error: unable to resolve node path '%'.", path);
                    // NOTE: returning true here so that we still default to normal idnetifier resolution
                    return true, null; 
                }
                
                if ref_node.data_binding.value_pointer == null {
                    // TODO: actually handle this case by creating instance of hinted type?
                    log("Error: node '%' referenced in expression '%' had no data binding!.", path, "(TODO: print node)");
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
        
        if !LS.walk_nodes(*script, *node.expr, walk_proc, *parser_and_node)  return false;
        
        expr_value_type := LS.typecheck_node(*script, node.expr, hint_type = node.data_binding.type);
        if expr_value_type != node.data_binding.type {
            log("Error: failed to typecheck expression '%'.", "(TODO: print node)");
            return false;
        }
        
        // TEMP DEBUG PRINTING
        builder: String_Builder;
        dbg := LS.print_node(*script, node.expr, *builder, 0);
        str := builder_to_string(*builder);
        defer free(str);
        print("%\n", str);
        
        value, ok := LS.evaluate_node(*script, node.expr);
        if !ok {
            log("Error: failed to evaluate expression '%'!", "(TODO: print node)");
            return false;
        }
        assert(value.type == node.data_binding.type, "% != %", as_type(value.type), as_type(node.data_binding.type));
        
        memcpy(node.data_binding.value_pointer, value.value_pointer, value.type.runtime_size);
        
        return true;
    }
    
    return true;
}

/*
    Construction of the dom is done iteratively instead of recursively, since we can trivially track the current parent node and retrieve it's parent node when we would otherwise return.
    Although, if we ever remove the pointer to parent from DOM nodes, we may go ahead and just make this recursive.
    
    TODO: don't require comma after objects or arrays
          maybe we can just consume the comma in the lexer as an expression-ending delimiter and then 
          we can remove the need to even check for it here.
          Maybe we can even just make the comma be whitespace to GON again?
*/
construct_dom_from_gon_file :: (using parser: *Parser) -> bool {
    dom_root      = New(DOM_Node,, node_allocator);
    dom_root.name = "root";
    dom_root.type = .OBJECT;
    
    // ideally, we would just be able to replace the token after it's consumed so that we are always kind of peeking it, but the problem is that we need to be able to tell the lexer what we expect to see (name or value)
    next_token: Token;
    first_child := true;
    
    parent := dom_root;
    while L_Loop := (parent != null) {
        name:   string;
        expr:   *LS.Node;
        type:   Node_Type;
        name_location:  Source_Location;
        
        // NOTE: Unlike JSON, we don't enforce that there is NOT a trailing comma after the last field in a scope
        if !first_child {
            // NOTE: We put the token back manually here instead of implementing a peek_token() proc, 
            //       since peeking a token is potentially non-trivial with how things currently are factored.
            //       In this case it is fine though, since the only case where it would be non-trivial is an error.
            _file := parser.file;
            next_token = lex_next_token(parser);
            if next_token.type == {
              case .COMMA;          // no op, consume the token
              case .OBJECT_END;     #through;
              case .ARRAY_END;      #through;
              case .EOF;            parser.file = _file; // put the token back manually
              case;
                log("GON parse error: Expected comma or end of scope after field value, got % \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line, next_token.location.char);
                return false;
            }
        }
        first_child = false;
        
        // read field name
        if parent.type != .ARRAY {
            next_token = lex_next_token(parser);
            if next_token.type == {
              case .STRING;
                name = next_token.text;
                name_location = next_token.location;
                
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
            
            next_token = lex_next_token(parser);
            if next_token.type != .COLON {
                log("GON parse error: Expected colon after field name, got % \"%\".", next_token.type, next_token.text);
                return false;
            }
        }
        
        // read field value
        next_token = lex_next_token(parser, expect_expression = true);
        if next_token.type == {
          case .EXPRESSION;
            type = .FIELD;
            expr = next_token.expr;
            
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
        node.source_location = ifx name then name_location else next_token.location;
        if node.type == {
          case .OBJECT; #through;
          case .ARRAY;
            parent = node;
            first_child = true;
            
          case .FIELD;
            node.expr = expr;
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
                    array_reserve_nonpoly(xx raw_array, count_before + node.children.count, ti_array.element_type.runtime_size);
                    raw_array.count += node.children.count;
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
                    if node.children.count > elem_count {
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
                    log("Data binding error: tried to bind an enum to an array on field %", format_node_path(node,, temp));
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

                if node.children.count > ti_struct.members.count {
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
                    array_reserve_nonpoly(xx raw_array, count_before + node.children.count, ti_array.element_type.runtime_size);
                    raw_array.count += node.children.count;
                    for node.children {
                        elem_any := Any.{
                            value_pointer = raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size), 
                            type          = ti_array.element_type
                        };
                        add_data_binding_to_node(it, elem_any);
                    }
                } else {
                    elem_count, data := get_array_count_and_data(node.data_binding.value_pointer, ti_array);
                    if node.children.count > elem_count {
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

      case;
        // TODO: invalid node type error?
    }
    
    return true;
}


as_type :: inline (ti: *Type_Info) -> Type { return (cast(*Type)*ti).*; }
