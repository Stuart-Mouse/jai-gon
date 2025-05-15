
Parser_Callback :: #type (*Node) -> bool;

// used to build a DOM from a text file and evaluate data bindings on that DOM
Parser :: struct {
    tokenizer:  Lexer;
    node_pool:  Flat_Pool;
    root_node:  *Node;
    
    // serialization stuff
    builder:    String_Builder;
    indent:     int;
};

init_parser :: (parser: *Parser, file: string) {
    reset(*parser.node_pool, overwrite_memory = true);
    parser.tokenizer.file = file;
    init_tokenizer(*parser.tokenizer);
}

deinit_parser :: (using parser: *Parser) {
    fini(*node_pool);
}

// creates a dom parser with the given parameters, intializes it, and constructs the dom from the given file
// after calling this, you can just add your data bindings and then process them
parse_file_to_dom :: (file: string) -> (Parser, bool) {
    parser: Parser;
    init_parser(*parser, file);
    if !construct_dom      (*parser)  return .{}, false;
    // if !validate_references(*parser)  return .{}, false;
    return parser, true;
}

add_data_binding_to_dom :: (using parser: *Parser, binding: Any, path: string) -> bool {
    node := find_node_by_path(parser.root_node, path);
    return add_data_binding_to_node(node, binding);
}

add_data_bindings_to_dom :: (using parser: *Parser, bindings: [] struct { binding: Any; path: string; }) -> bool {
    for bindings
        if !add_data_binding_to_dom(parser, it.binding, it.path)  
            then return false;
    return true;
}

process_data_bindings :: (using parser: *Parser) -> bool {
    if !process_node_binding(parser, root_node)  return false;
    return true;
}

process_node_binding :: (using parser: *Parser, node: *Node) -> resolved: bool {
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
    }
    
    return true;
}

construct_dom :: (using parser: *Parser) -> bool {
    push_allocator(get_pool_allocator(*parser.node_pool));
    
    next_token: Token;
    ok: bool;
    
    root_node      = New(Node);
    root_node.name = "root";
    root_node.type = .OBJECT;
    
    parent := root_node;
    while L_Loop := (parent != null) {
        name, text:         string;
        type:               Node_Type;
        flags:              Node_Flags;
        source_location:    Source_Code_Location;
        
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
                if parent != root_node {
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
        
        next_token = get_token(*tokenizer);
        if next_token.type == .ERROR {
            log("GON tokenization error: Unexpected % token \"%\".", next_token.type, next_token.text);
            return false;
        }
    
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
        
        assert(type != .UNINITIALIZED);
        
        node := append_child_node(parent);
        node.name  = name;
        node.type  = type;
        node.flags = flags;
        node.source_location = ifx source_location.line_number then source_location else next_token.location;
        
        if node.type == {
          case .OBJECT; #through;
          case .ARRAY;
            parent = node;
            
          case .FIELD;
            node.value = text;
        }
    }
    
    return true;
}

add_data_binding_to_node :: (node: *Node, binding: Any) -> bool  {
    if node == null || binding.value_pointer == null  return true;
    
    if node.data_binding.value_pointer != null {
        log("Error, node already has a data binding set...");
        return false;
    }
    
    node.data_binding = binding;
    name_member: *Type_Info_Struct_Member;
    name_member_any: Any;
    
    io_data := get_io_data(node.data_binding.type);
    if io_data {
        // because we may rebind the node, we need to assign the name_member_any
        // if this Any is still set after making bindings to child nodes, then we will assign to it
        if io_data.name_member {
            name_member = io_data.name_member;
            name_member_any = Any.{ name_member.type, node.data_binding.value_pointer + name_member.offset_in_bytes };
        }
        
        if io_data.parse.bind_proc {
            node.data_binding = io_data.parse.bind_proc(node.data_binding);
            if node.data_binding.value_pointer == null {
                log("Error, bind_proc() returned null.");
                return false;
            }
            // get new io data for new binding
            io_data = get_io_data(node.data_binding.type);
        }
    }
    
    defer if name_member {
        return remap_data(name_member_any, node.name);
    }
    
    // TODO: think about whether we want to reimplement this functionality
    // node.data_binding = deref_any_pointer(node.data_binding);
    
    // make indirect bindings onto child nodes
    if node.type == {
      case .OBJECT;
        if binding.type.type == {
          case .STRUCT;            
            for node.children {
                member := get_field(xx node.data_binding.type, it.name);
                if !member || (member.flags & .CONSTANT)  continue;
                
                // we don't want to set it if the name member has a binding to a child node
                if member == name_member then name_member = null;
                
                member_any := Any.{ member.type, node.data_binding.value_pointer + member.offset_in_bytes };
                if !add_data_binding_to_node(it, member_any)  return false;
            }
            
            // we don't want to set the name member if the parent exists and is an indexed array, because then the gon name is being used for the index
            if node.parent && (node.parent.flags & .ARRAY_INDEXED) then name_member = null;
            
            
          case .ARRAY;
            ti_array := node.data_binding.type.(*Type_Info_Array);
            
            if io_data && (.ARRAY_INDEXED & io_data.parse.flags) {
                node.flags |= .ARRAY_INDEXED;
            }
            
            element_io_data   := get_io_data(ti_array.element_type);
            element_is_struct := ti_array.element_type.type == .STRUCT;
            
            if element_is_struct {
                node.flags |= .ARRAY_AS_OBJECT;
                if !element_io_data.name_member {
                    log("Data binding error: object-type array must contain a struct with a defined name member.");
                    return false;
                }
            }
            
            if !(node.flags & (.ARRAY_AS_OBJECT | .ARRAY_INDEXED)) {
                log("Data binding error: object-type array must contain a struct with a defined name member.");
                return false;
            }
            
            if ti_array.array_type == .RESIZABLE {
                raw_array := node.data_binding.value_pointer.(*Resizable_Array);

                if .ARRAY_INDEXED & node.flags {
                    for node.children {
                        elem_index: int;
                        ok: bool;
                        if io_data.enum_index_type {
                            elem_index, ok = enum_name_to_value(xx io_data.enum_index_type, it.name);
                            if !ok {
                                log("Data Binding Error: Unable to parse enum value from string: %", it.name);
                                return false;
                            }
                        } else {
                            elem_index, ok = to_integer(it.name);
                            if !ok {
                                log("Data Binding Error: Unable to parse integer from string: %", it.name);
                                return false;
                            }
                        }
                        elem_any := array_add_any_at_index(node.data_binding, elem_index);
                        if !add_data_binding_to_node(it, elem_any)  return false;
                    }
                } else {
                    count_before := raw_array.count;
                    array_reserve_nonpoly(xx raw_array, count_before + node.children.count, ti_array.element_type.runtime_size);
                    raw_array.count += node.children.count;
                    for node.children {
                        element_any := Any.{ ti_array.element_type, raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size) };
                        if !add_data_binding_to_node(it, element_any)  return false;
                    }
                }
            } else { // .FIXED and .VIEW
                array_count, array_data := get_array_count_and_data(node.data_binding.value_pointer, ti_array);
                
                if .ARRAY_INDEXED & node.flags {
                    for node.children {
                        elem_index := to_integer(it.name);
                        if elem_index < 0 || elem_index >= array_count {
                            log("Data Binding Error: array index is out of bounds.");
                            return false;
                        }
                        
                        element_any := Any.{ ti_array.element_type, array_data + (ti_array.element_type.runtime_size * elem_index) };
                        if !add_data_binding_to_node(it, element_any)  return false;
                    }
                } else {
                    if ti_array.array_type == .VIEW {
                        raw_array   := node.data_binding.value_pointer.(*Array_View_64);
                        array_count  = node.children.count;
                        new_size    := array_count * ti_array.element_type.runtime_size;
                        array_data   = realloc(raw_array.data, new_size, raw_array.count * ti_array.element_type.runtime_size);
                        raw_array.*  = .{ array_count, array_data };
                        log("raw array: %", raw_array.*);
                    }
                    
                    if node.children.count > array_count {
                        log("Data Binding Error: GON array contains % elements, but data binding only contains space for %.", node.children.count, array_count);
                        return false;
                    }
                    
                    for node.children {
                        element_any := Any.{ ti_array.element_type, array_data + (ti_array.element_type.runtime_size * it_index) };
                        if !add_data_binding_to_node(it, element_any)  return false;
                    }
                }
            }
            
          case;
            log("Invalid data binding, mismatched gon(OBJECT)/internal(%) type on node %.", as_type(node.data_binding.type), node.*);
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
            for node.children {
                if !add_data_binding_to_node(it, node.data_binding)  return false;
            }
            
          case .STRUCT;
            ti_struct := node.data_binding.type.(*Type_Info_Struct);

            if node.children.count > ti_struct.members.count {
                log("Data binding error: array-type struct contains too many elements.");
                return false;
            }
            for node.children {
                // TODO: will need to to more work here because of constant struct members
                member := ti_struct.members[it_index];
                member_any := Any.{ member.type, node.data_binding.value_pointer + member.offset_in_bytes };
                if !add_data_binding_to_node(it, member_any)  return false;
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
                    elem_any := Any.{ ti_array.element_type, raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size) };
                    if !add_data_binding_to_node(it, elem_any)  return false;
                }
            } else {
                array_count, array_data := get_array_count_and_data(node.data_binding.value_pointer, ti_array);
                
                if ti_array.array_type == .VIEW {
                    raw_array   := node.data_binding.value_pointer.(*Array_View_64);
                    array_count  = node.children.count;
                    new_size    := array_count * ti_array.element_type.runtime_size;
                    array_data   = realloc(raw_array.data, new_size, raw_array.count * ti_array.element_type.runtime_size);
                    raw_array.*  = .{ array_count, array_data };
                    log("raw array: %", raw_array.*);
                }
                
                if node.children.count > array_count {
                    log("Data binding error: bounds check failed on array or slice.");
                    return false;
                }
                
                for node.children {
                    elem_any := Any.{ ti_array.element_type, array_data + (ti_array.element_type.runtime_size * it_index) };
                    if !add_data_binding_to_node(it, elem_any)  return false;
                }
            }
            
          case;
            log("Data binding error: mismatched gon(ARRAY)/internal(%) type on node %.", (*node.data_binding.type).(*Type).*, node.*);
            return false;
        }
        

      case .FIELD;
        if node.data_binding.type.type == {
          case .INTEGER;    // no op
          case .BOOL;       // no op
          case .FLOAT;      // no op
          case .STRING;     // no op
          case .ENUM;
            // For enum flags, both the enclosing array and the individual elements have the same binding
            // For fields, we must verify that the parent binding is the same as the field binding
            ti_enum := node.data_binding.type.(*Type_Info_Enum);
            if (ti_enum.enum_type_flags & .FLAGS) && node.parent.data_binding.value_pointer != node.data_binding.value_pointer
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


// modified version of set_value_from_string in Reflection.jai
set_value_from_string :: (any: Any, text: string) -> bool {
    if text.count <= 0  return true; // empty string -> return true
    
    if any.type.type == {
        case .INTEGER;
            result, success := string_to_int(text);
            if !success return false;
            
            ti_integer := any.type.(*Type_Info_Integer);
            if ti_integer.signed {
                valid, low, high := range_check_and_store(result, ti_integer, any.value_pointer);
                // @ToDo: We could log an error with the ranges here, similar to Command_Line.parse_and_write_integer
                if !valid return false;
            } else {
                valid, low, high := range_check_and_store(result.(u64), ti_integer, any.value_pointer);
                // @ToDo: We could log an error with the ranges here, similar to Command_Line.parse_and_write_integer
                if !valid return false;
            }  
            return true;  
  
        case .FLOAT;
            if any.type.runtime_size == {
              case 4;
                val, ok, text := string_to_float(text);
                if !ok return false;
                any.value_pointer.(*float).* = val;
              case 8;
                val, ok, text := string_to_float64(text);
                if !ok return false;
                any.value_pointer.(*float64).* = val;
            }
            return true;
            
        case .BOOL;
            b := (to_upper(text[0]) == #char "T");
            any.value_pointer.(*bool).* = b; 
            return true;
            
        case .STRING;
            // TODO: add conditional logic to NOT copy string if desired
            // any.value_pointer.(*string).* = text;
            any.value_pointer.(*string).* = copy_string(text);
            return true;
  
        case .ENUM;
            enum_type := any.type.(*Type_Info_Enum);  
            value := Small_Any.{ type = any.type };
            success := false;
            
            for enum_type.names {
                if it == text {
                    if enum_type.runtime_size == {
                        case 1; value.value_number.as_s\8 = enum_type.values[it_index].(s\8); 
                        case 2; value.value_number.as_s16 = enum_type.values[it_index].(s16); 
                        case 4; value.value_number.as_s32 = enum_type.values[it_index].(s32); 
                        case 8; value.value_number.as_s64 = enum_type.values[it_index].(s64); 
                    }
                    success = true;
                    break;
                }
            }
            
            if !success {
                success = set_value_from_string(Any.{ enum_type.internal_type, *value.value_bytes }, text);
            }
            
            if success {
                if (enum_type.enum_type_flags & .FLAGS) {
                    old_value := Small_Any.from(any);
                    value.value_number.as_u64 |= old_value.value_number.as_u64;
                    memcpy_any(any, to_any(*value));
                } else {
                    memcpy_any(any, to_any(*value));
                }
            }
            return success;
    }

    return false;
}
