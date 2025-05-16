
Parser :: struct {
    tokenizer:  Lexer;
    node_pool:  Flat_Pool;
    root_node:  *Node;
    
    // serialization stuff
    builder:    String_Builder;
    indent:     int;
    
    get_allocator_for_node: #type (*Node) -> Allocator;
};

init_parser :: (parser: *Parser, file: string, filepath := "") {
    reset(*parser.node_pool, overwrite_memory = true);
    parser.tokenizer.file = file;
    init_lexer(*parser.tokenizer, filepath);
}

deinit_parser :: (using parser: *Parser) {
    fini(*node_pool);
}


parse_file :: (file: string) -> (Parser, bool) {
    parser: Parser;
    init_parser(*parser, file);
    if !construct_dom      (*parser)  return .{}, false;
    // if !validate_references(*parser)  return .{}, false;
    return parser, true;
}


add_data_binding :: (using parser: *Parser, binding: Any, path: string) -> bool {
    node := find_node_by_path(parser.root_node, path);
    return add_data_binding_to_node(node, binding);
}

add_data_bindings :: (using parser: *Parser, bindings: [] struct { binding: Any; path: string; }) -> bool {
    for bindings
        if !add_data_binding(parser, it.binding, it.path)  
            return false;
    return true;
}


process_data_bindings :: (using parser: *Parser) -> bool {
    if !process_node_binding(parser, root_node)  return false;
    return true;
}

process_node_binding :: (using parser: *Parser, node: *Node) -> resolved: bool {
    if node.node_type == {
      case .OBJECT; #through;
      case .ARRAY;
        for node.children
            if !process_node_binding(parser, it)
                return false;
        return true;
        
      case .FIELD;
        if node.binding.value_pointer == null  return true;
        
        io_data := get_io_data(node.binding.type);
        if io_data && io_data.parse_proc {
            if io_data.parse_proc(node.binding, node.value) {
                log("%:%,%: GON Data Binding Error: parse_proc failed.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            return true;
        }
        
        return set_value_from_string(node.binding, node.value);
    }
    
    return true;
}


construct_dom :: (using parser: *Parser) -> bool {
    log_unexepected_token :: (token: Token) {
        if token.type == .ERROR {
            log("%:%,%: GON lexer error: %.", token.location.fully_pathed_filename, token.location.line_number, token.location.character_number, token.text);
        } else {
            log("%:%,%: GON parser error: Unexpected % token: '%'.", token.location.fully_pathed_filename, token.location.line_number, token.location.character_number, token.type, token.text);
        }
    }
    
    push_allocator(get_pool_allocator(*parser.node_pool));
    
    next_token: Token;
    ok: bool;
    
    root_node      = New(Node);
    root_node.name = "root";
    root_node.node_type = .OBJECT;
    
    parent := root_node;
    while L_Loop := (parent != null) {
        name, value: Token;
        node_type:   Node_Type;
        
        // read field name
        if parent.node_type != .ARRAY {
            next_token = get_token(*tokenizer);
            if next_token.type == {
              case .IDENTIFIER; #through;
              case .NUMBER;     #through;
              case .STRING;
                name = next_token;
                
              case .EOF;
                if parent != root_node {
                    log_unexepected_token(next_token);
                    return false;
                }
                break L_Loop;
                
              case .OBJECT_END;
                if parent.node_type != .OBJECT {
                    log_unexepected_token(next_token);
                    return false;
                }
                parent = parent.parent;
                continue;
                
              case;
                log_unexepected_token(next_token);
                return false;
            }
        }
        
        next_token = get_token(*tokenizer);
        if next_token.type == .ERROR {
            log_unexepected_token(next_token);
            return false;
        }
    
        // read field value
        if next_token.type == {
          case .IDENTIFIER; #through;
          case .NUMBER;     #through;
          case .STRING;
            node_type = .FIELD;
            value = next_token;
            
          case .OBJECT_BEGIN;
            node_type = .OBJECT;
            
          case .ARRAY_BEGIN;
            node_type = .ARRAY;
            
          case .ARRAY_END;
            if parent.node_type != .ARRAY {
                log_unexepected_token(next_token);
                return false;
            }
            parent = parent.parent;
            continue;
            
          case;
            log_unexepected_token(next_token);
            return false;
        }
        
        assert(node_type != .UNINITIALIZED);
        
        node := append_child_node(parent);
        node.name      = name.text;
        node.node_type = node_type;
        node.location  = ifx name.location.line_number then name.location else value.location;
        
        if node.node_type == {
          case .OBJECT; #through;
          case .ARRAY;
            parent = node;
            
          case .FIELD;
            node.value = value.text;
        }
    }
    
    return true;
}



add_data_binding_to_node :: (node: *Node, binding: Any) -> bool  {
    if node == null || binding.value_pointer == null  return true;
    
    if node.binding.value_pointer != null {
        log("Error, node already has a data binding set...");
        return false;
    }
    
    node.binding = binding;
    
    name_member:      *Type_Info_Struct_Member;
    name_member_any:  Any;
    
    io_data := get_io_data(node.binding.type);
    if io_data {
        // because we may rebind the node, we need to assign the name_member_any ahead of time
        // if this Any is still set after making bindings to child nodes, then we will assign to it
        if io_data.name_member {
            name_member = io_data.name_member;
            name_member_any = Any.{ name_member.type, node.binding.value_pointer + name_member.offset_in_bytes };
        }
        
        if io_data.bind_proc {
            node.binding = io_data.bind_proc(node.binding);
            io_data = get_io_data(node.binding.type);
        }
    }
    
    if is_indexed_array(node.parent) {
        name_member = null; // don't assign name member if in an indexed array
    }
    
    defer if name_member {
        return remap_data(name_member_any, node.name);
    }
    
    // TODO: think about whether we want to reimplement this functionality
    // node.binding = deref_any_pointer(node.binding);
    
    // make indirect bindings onto child nodes
    if node.node_type == {
      case .OBJECT;
        if binding.type.type == {
          case .STRUCT;            
            for node.children {
                member := get_field(xx node.binding.type, it.name);
                if !member || (member.flags & .CONSTANT)  continue;
                
                // we don't want to set it if the name member has a binding to a child node
                if member == name_member then name_member = null;
                
                member_any := Any.{ member.type, node.binding.value_pointer + member.offset_in_bytes };
                if !add_data_binding_to_node(it, member_any)  return false;
            }
            
            
          case .ARRAY;
            ti_array := node.binding.type.(*Type_Info_Array);
            
            is_indexed := io_data != null && (.ARRAY_INDEXED & io_data.flags) != 0;
            
            element_io_data   := get_io_data(ti_array.element_type);
            element_is_struct := ti_array.element_type.type == .STRUCT;
            element_has_name  := element_io_data != null && element_io_data.name_member != null;
            
            if element_is_struct && !element_has_name {
                log("%:%,%: GON data binding error: GON object with binding to array of structs must contain a struct type with a defined IO_Data name member.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            
            if !is_indexed && !element_is_struct {
                log("%:%,%: GON data binding error: GON object with binding to array must either be indexed or contain a struct type with a defined IO_Data name member.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            
            get_element_index :: (node: *Node, array_io_data: *IO_Data) -> int, bool {
                if array_io_data.enum_index_type {
                    index, ok := enum_name_to_value(xx array_io_data.enum_index_type, node.name);
                    if !ok {
                        log("%:%,%: GON data binding error: Unable to parse enum value from string: %", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, node.name);
                        return 0, false;
                    }
                    return index, true;
                } else {
                    index, ok, remainder := to_integer(node.name);
                    if !ok || remainder {
                        log("%:%,%: GON data binding error: Unable to parse integer from string: %", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, node.name);
                        return 0, false;
                    }
                    return index, true;
                }
            }
            
            if ti_array.array_type == .RESIZABLE {
                raw_array := node.binding.value_pointer.(*Resizable_Array);
                if is_indexed {
                    for node.children {
                        elem_index, ok := get_element_index(it, io_data);
                        if !ok  return false;
                        
                        elem_any := array_add_any_at_index(node.binding, elem_index);
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
                array_count, array_data := get_array_count_and_data(node.binding.value_pointer, ti_array);
                
                if is_indexed {
                    // NOTE: we don't dynamically allocate for views with indexed elements, since it's not clear exactly how that should work.
                    for node.children {
                        elem_index, ok := get_element_index(it, io_data);
                        if !ok  return false;
                        
                        if elem_index < 0 || elem_index >= array_count {
                            log("%:%,%: GON data binding error: array index is out of bounds.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                            return false;
                        }
                        
                        element_any := Any.{ ti_array.element_type, array_data + (ti_array.element_type.runtime_size * elem_index) };
                        if !add_data_binding_to_node(it, element_any)  return false;
                    }
                } else {
                    // TODO: should we really be using realloc here? 
                    // Seems like it could be risky if original memory was allocated with a different allocator.
                    // Perhaps if the view already has some memory allocated, we should just leave it or fail?
                    // Or maybe we just add some user configuration to specify how to handle this situation...
                    // This consideration is probably why I didn't have such allocation implemented in the first place.
                    if ti_array.array_type == .VIEW {
                        raw_array   := node.binding.value_pointer.(*Array_View_64);
                        array_count  = node.children.count;
                        new_size    := array_count * ti_array.element_type.runtime_size;
                        array_data   = realloc(raw_array.data, new_size, raw_array.count * ti_array.element_type.runtime_size);
                        raw_array.*  = .{ array_count, array_data };
                    }
                    
                    if node.children.count > array_count {
                        log("%:%,%: GON data binding error: GON array contains % elements, but data binding only contains space for %.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, node.children.count, array_count);
                        return false;
                    }
                    
                    for node.children {
                        element_any := Any.{ ti_array.element_type, array_data + (ti_array.element_type.runtime_size * it_index) };
                        if !add_data_binding_to_node(it, element_any)  return false;
                    }
                }
            }
            
          case;
            log("%:%,%: GON data binding error: GON object cannot be bound to type %.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, as_type(node.binding.type));
            return false;
        }
        
        
      case .ARRAY;
        if binding.type.type == {
          case .ENUM;
            ti_enum := node.binding.type.(*Type_Info_Enum);
            if !(ti_enum.enum_type_flags & .FLAGS) {
                log("%:%,%: GON data binding error: cannot bind an enum to an array unless it is an enum_flags.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            if node.parent.binding.value_pointer == node.binding.value_pointer {
                log("%:%,%: GON data binding error: invalid structure in GON array with binding to enum_flags.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            for node.children {
                if !add_data_binding_to_node(it, node.binding)  return false;
            }
            
          case .STRUCT;
            ti_struct := node.binding.type.(*Type_Info_Struct);

            if node.children.count > ti_struct.members.count {
                log("%:%,%: GON data binding error: GON array contains more elements than can be mapped to the struct members of type: %", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, as_type(ti_struct));
                return false;
            }
            for node.children {
                // TODO: will need to to more work here because of constant struct members
                member := ti_struct.members[it_index];
                member_any := Any.{ member.type, node.binding.value_pointer + member.offset_in_bytes };
                if !add_data_binding_to_node(it, member_any)  return false;
            }
            
          case .ARRAY;
            ti_array := node.binding.type.(*Type_Info_Array);
            
            if ti_array.array_type == .RESIZABLE {
                raw_array := node.binding.value_pointer.(*Resizable_Array);
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
                array_count, array_data := get_array_count_and_data(node.binding.value_pointer, ti_array);
                
                // TODO: same issues here with realloc as are noted above in OBJECT case
                if ti_array.array_type == .VIEW {
                    raw_array   := node.binding.value_pointer.(*Array_View_64);
                    array_count  = node.children.count;
                    new_size    := array_count * ti_array.element_type.runtime_size;
                    array_data   = realloc(raw_array.data, new_size, raw_array.count * ti_array.element_type.runtime_size);
                    raw_array.*  = .{ array_count, array_data };
                }
                
                if node.children.count > array_count {
                    log("%:%,%: GON data binding error: bounds check failed on array or slice.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                    return false;
                }
                
                for node.children {
                    elem_any := Any.{ ti_array.element_type, array_data + (ti_array.element_type.runtime_size * it_index) };
                    if !add_data_binding_to_node(it, elem_any)  return false;
                }
            }
            
          case;
            log("%:%,%: GON data binding error: GON array cannot be bound to type: %", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, as_type(node.binding.type));
            return false;
        }
        
        
      case .FIELD;
        if node.binding.type.type == {
          case .INTEGER;    // no op
          case .BOOL;       // no op
          case .FLOAT;      // no op
          case .STRING;     // no op
          case .ENUM;
            // For enum flags, both the enclosing array and the individual elements have the same binding
            // For fields, we must verify that the parent binding is the same as the field binding
            ti_enum := node.binding.type.(*Type_Info_Enum);
            if (ti_enum.enum_type_flags & .FLAGS) && node.parent.binding.value_pointer != node.binding.value_pointer {
                log("%:%,%: GON data binding error: GON field cannot be bound directly to an enum_flags, use a GON array instead.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            
          case .ARRAY;
            if node.binding.type.(*Type_Info_Array).element_type == type_info(u8) {
                log("%:%,%: GON data binding error: Unable to bind GON field to array type. (A special exception is made for arrays of u8, so that they can be treated like strings.)", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            
          case .STRUCT;
            if !io_data || !io_data.parse_proc {
                log("%:%,%: GON data binding error: Unable to bind GON field to struct type unless an IO_Data parse_proc is defined.", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number);
                return false;
            }
            
          case;
            log("%:%,%: GON data binding error: Unable to bind GON field to type: %", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, as_type(node.binding.type));
            return false;
        }
        
      case;
        // TODO: invalid node type error?
    }
    
    return true;
}


// TODO: probbaly clean this up further and move into utils or remap.jai
// modified version of set_value_from_string in Reflection.jai
set_value_from_string :: (any: Any, text: string) -> bool {
    if text.count <= 0  return true; // empty string -> return true
    
    if any.type.type == {
        case .INTEGER;
            // TODO: we do not really handle full range of u64 here, because we string_to_int with s64
            // TODO: we also do not handle hexadecimal, octal, binary cases
            result, ok, remainder := string_to_int(text);
            if !ok || remainder {
                return false;
            }
            return int_to_int(any, result);
            
            
        case .FLOAT;
            value, ok, remainder := string_to_float64(text);
            if !ok || remainder  {
                return false;
            }
            
            if any.type.runtime_size == {
              case 4; any.value_pointer.(*float32).* = value.(float32);
              case 8; any.value_pointer.(*float64).* = value;
            }
            return true;
            
            
        case .BOOL;
            // OK, maybe we should be a bit more rigorous here...
            b := (to_upper(text[0]) == #char "T");
            any.value_pointer.(*bool).* = b; 
            return true;
            
            
        case .STRING;
            // TODO: add conditional logic to NOT copy string if desired
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
            } else {
                log("Failed to parse enum value from string '%'", text);
            }
            return success;
    }

    log("unsupported type in set_value_from_string");
    return false;
}
