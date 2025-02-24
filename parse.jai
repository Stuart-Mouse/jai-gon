

Parser_Callback :: #type (*DOM_Node) -> bool;

// used to build a DOM from a text file and evaluate data bindings on that DOM
Parser :: struct {
    tokenizer:          Tokenizer;
    dom_root:           *DOM_Node;
    node_pool:          Flat_Pool;
    node_allocator:     Allocator;
    callbacks:          [..] Parser_Callback;
};

init_parser :: (using parser: *Parser, _file: string, use_pool := true) {
    if use_pool {
        reset(*node_pool, overwrite_memory = true);
        node_allocator = .{
            data = *node_pool,
            proc = flat_pool_allocator_proc,
        };
    } else {
        node_allocator = context.allocator;
    }
    tokenizer.file = _file;
    init_tokenizer(*tokenizer);
}

deinit_parser :: (using parser: *Parser) {
    delete_child_nodes_recursive(dom_root,, node_allocator);
    free(dom_root,, node_allocator);
    dom_root = null;
    if node_allocator.data == *node_pool {
        fini(*node_pool);
    }
    array_free(callbacks);
}

// creates a dom parser with the given parameters, intializes it, and constructs the dom from the given file
// after calling this, you can just add your data bindings and then process them
parse_file_to_dom :: inline (file: string) -> (Parser, bool) {
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

validate_node_references :: (using parser: *Parser) -> bool {
    Result :: enum_flags { NONE :: 0; ERROR :: 1; COMPLETE; PROGRESS; REMOVE_NODE; };
    
    recurse :: (using parser: *Parser, node: *DOM_Node, unresolved_refs: *[..] *DOM_Node) -> Result {
        if .REFERENCES_RESOLVED & node.flags  return .COMPLETE;
        
        if node.type == {
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
            path := node.ref.path;
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
                    dst = append_child_node(parent,, node_allocator);
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
                log("\t% -> %", format_node_path(it), it.ref.path);
            }
            return false;
        }
    }
    
    log("Resolved node references in % iterations.", iterations);
    return true;
}

process_data_bindings :: (using parser: *Parser) -> bool {
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
        name, text:         string;
        type:               Node_Type;
        flags:              DOM_Node_Flags;
        source_location:    Source_Location;
        
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
                    source_location = next_token.location;
                    
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
            node.ref.path = next_token.text;
            node.source_location = ifx source_location.line then source_location else next_token.location;
        }
        else {
            // read field value
            if next_token.type == {
              case .STRING;
                type = .FIELD;
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
            node.source_location = ifx source_location.line then source_location else next_token.location;
            if node.type == {
              case .OBJECT; #through;
              case .ARRAY;
                parent = node;
                
              case .FIELD;
                node.value = text;
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
                    This may prove to be one of the more fragile aspects of the DOM parser in contrast to the SAX implementation,
                    because this definitely seems like something that a user could break through a problematic callback procedure.
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
        
        
      case;
        // TODO: invalid node type error?
    }
    
    return true;
}
