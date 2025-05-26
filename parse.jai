
Parser :: struct {
    tokenizer:  Lexer;
    node_pool:  Flat_Pool;
    root_node:  *Node;
};

init_parser :: (parser: *Parser, file: string, file_path := "") {
    reset(*parser.node_pool, overwrite_memory = true);
    init_lexer(*parser.tokenizer, file, file_path);
    
    // NOTE: We unfortunately do have to allocate this node in the pool, 
    //       otherwise its address could change if the parser gets passed around.
    //       Were it not for this, we wouldn't even necessarily need the init proc so much.
    parser.root_node = New(Node,, get_pool_allocator(*parser.node_pool));
    parser.root_node.* = .{
        name      = "root",
        node_type = .OBJECT,
    };
}

deinit_parser :: (using parser: *Parser) {
    fini(*node_pool);
}


// ========== Load and Parse ==========

load_and_parse_file_with_bindings :: (file_path: string, bindings: ..Binding_With_Path) -> Parser, bool {
    file, ok := read_entire_file(file_path);
    if !ok  return .{}, false;
    parser:, ok = parse_file(file, file_path);
    return parser, ok;
}

load_and_parse_file :: (file_path: string) -> Parser, bool {
    file, ok := read_entire_file(file_path);
    if !ok  return .{}, false;
    parser:, ok = parse_file(file, file_path);
    return parser, ok;
}

parse_file :: (file: string, file_path: string) -> Parser, bool {
    parser: Parser;
    init_parser(*parser, file);
    if !construct_dom(*parser)  return .{}, false;
    return parser, true;
}


// ========== Data Bindings ==========

Binding_With_Path :: struct { binding: Any; path: string; }

add_data_binding :: (using parser: *Parser, binding: Any, path: string) -> bool {
    node := find_node_by_path(parser, parser.root_node, path);
    return add_data_binding_to_node(node, binding);
}

add_data_bindings :: (using parser: *Parser, bindings: ..Binding_With_Path) -> bool {
    for bindings
        if !add_data_binding(parser, it.binding, it.path)  
            return false;
    return true;
}

process_data_bindings :: (using parser: *Parser) -> bool {
    if !process_node_binding(parser, root_node)  return false;
    return true;
}


// ========== Implementation ==========

#scope_module

process_node_binding :: (using parser: *Parser, node: *Node) -> resolved: bool {
    if node.node_type == {
      case .OBJECT; #through;
      case .ARRAY;
        if node.binding.type && node.binding.type.type == .ENUM {
            enum_info := node.binding.type.(*Type_Info_Enum);
            assert(enum_info.enum_type_flags & .FLAGS == .FLAGS);
            for node.children 
                if !set_value_from_string(node.binding, it.value)
                    return false;
            return true;
        }
        
        for node.children
            if !process_node_binding(parser, it)
                return false;
        return true;
        
      case .FIELD;
        if node.binding.value_pointer == null  return true;
        
        io_data := get_io_data(node.binding.type);
        if io_data && io_data.parse_proc {
            if io_data.parse_proc(node.binding, node.value) {
                log_binding_error(node, "parse_proc failed.");
                return false;
            }
            return true;
        }
        
        return set_value_from_string(node.binding, node.value);
    }
    
    unreachable();
    return false;
}

/*
    The DOM is constructed in a nice big loop, rather than in some kind of recursive function. 
*/
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
        
        node := insert_child_node(parent);
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

log_binding_error :: (node: *Node, format: string, arguments: ..Any) {
    message := tprint(format, ..arguments);
    log("%:%,%: GON data binding error: %", node.location.fully_pathed_filename, node.location.line_number, node.location.character_number, message);
}

add_data_binding_to_node :: (node: *Node, binding: Any) -> bool  {
    if node == null || binding.type == null  return true;
    
    if node.binding.type != null {
        log_binding_error(node, "node already has a data binding set. Node path: %", format_node_path(node));
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
    
    // name_member would conflict with indexing, so index takes precedence
    if is_indexed_array(node.parent) {
        name_member = null;
    }
    
    defer if name_member {
        return Convert.any_to_any(name_member_any, node.name);
    }
    
    // TODO: think about whether we want to reimplement pointer dereferencing stuff
    //       this is maybe something people could do with IO Data bind proc, but maybe that's too type-specific actually
    
    // TODO: Need to seriously consider whether or not the making of bindings should be separate from the evaluation.
    //       Since I removed field references, there's no longer really a need for this to be two separate steps, 
    //       but I may still add those back in in a more limited form, so... i dunno yet.
    
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
            array := Any_Array.from(node.binding);
            
            is_indexed := io_data != null && (.ARRAY_INDEXED & io_data.flags) != 0;
            
            element_io_data   := get_io_data(array.element_type);
            element_is_struct := array.element_type.type == .STRUCT;
            element_has_name  := element_io_data != null && element_io_data.name_member != null;
            
            if element_is_struct && !element_has_name {
                log_binding_error(node, "GON object with binding to array of structs must contain a struct type with a defined IO_Data name member.");
                return false;
            }
            
            if !is_indexed && !element_is_struct {
                log_binding_error(node, "GON object with binding to array must either be indexed or contain a struct type with a defined IO_Data name member.");
                return false;
            }
            
            if is_indexed {
                min_index, max_index := S64_MAX, S64_MIN;
                if io_data.enum_index_type {
                    for node.children {
                        index, ok := enum_name_to_value(xx io_data.enum_index_type, node.name);
                        if !ok {
                            log_binding_error(node, "unable to parse enum value from string: %", node.name);
                            return false;
                        }
                        min_index = min(min_index, index);
                        max_index = max(max_index, index);
                    }
                } else {
                    for node.children {
                        index, ok, remainder := to_integer(node.name);
                        if !ok || remainder {
                            log_binding_error(node, "unable to parse integer from string: %", node.name);
                            return false;
                        }
                        min_index = min(min_index, index);
                        max_index = max(max_index, index);
                    }
                }
                
                // TODO: add a configurable absolute max index so that we don't resize to some insane amount.
                if min_index < 0 || max_index < 0 {
                    log_binding_error(node, "invalid array index: %, index cannot be negative.", min_index);
                    return false;
                }
                if array.array_type == {
                  case .RESIZABLE;
                    resize(array, max_index);
                    
                  case .FIXED; #through;
                  case .VIEW;
                    count, data := get_count_and_data(array);
                    if data {
                        if node.children.count > count {
                            log_binding_error(node, "bounds check failed on array or slice.");
                            return false;
                        }
                    } else if array.array_type == .VIEW {
                        assert(count == 0);
                        resize(array, max_index);
                    }
                }
                
                if io_data.enum_index_type {
                    for node.children {
                        index := enum_name_to_value(xx io_data.enum_index_type, node.name);
                        if !add_data_binding_to_node(it, array[it_index])  return false;
                    }
                } else {
                    for node.children {
                        index := to_integer(node.name);
                        if !add_data_binding_to_node(it, array[it_index])  return false;
                    }
                }
                
            } else {
                count, data := get_count_and_data(array);
                if array.array_type == {
                  case .RESIZABLE;
                    resize(array, node.children.count + count);
                    
                  case .FIXED; #through;
                  case .VIEW;
                    if data {
                        if node.children.count > count {
                            log_binding_error(node, "bounds check failed on array or slice.");
                            return false;
                        }
                    } else if array.array_type == .VIEW {
                        assert(count == 0);
                        resize(array, node.children.count);
                    }
                }
                for node.children {
                    if !add_data_binding_to_node(it, array[it_index])  return false;
                }
            }
            
            
          case;
            log_binding_error(node, "GON object cannot be bound to type %.", as_type(node.binding.type));
            return false;
        }
        
        
      case .ARRAY;
        if binding.type.type == {
          case .ENUM;
            // We don't actually make data bindings onto the child nodes for enum_flags array.
            // Instead, we will just validate the structure here and iterate over the child fields directly when we evaluate the data bindings.
            // This is done partially to prevent any possible complications that the duplicated bindings could cause during serialization.
            ti_enum := node.binding.type.(*Type_Info_Enum);
            if !(ti_enum.enum_type_flags & .FLAGS) {
                log_binding_error(node, "cannot bind an enum to an array unless it is an enum_flags.");
                return false;
            }
            for node.children {
                if it.node_type != .FIELD {
                    log_binding_error(node, "invalid structure in GON array with binding to enum_flags. All elements in array must be simple fields, since each value represents a flag which is set in the enum_flags value.", it.location.fully_pathed_filename, it.location.line_number, it.location.character_number);
                }
            }
            
            
          case .STRUCT;
            ti_struct := node.binding.type.(*Type_Info_Struct);

            if node.children.count > ti_struct.members.count {
                log_binding_error(node, "GON array contains more elements than can be mapped to the struct members of type: %", as_type(ti_struct));
                return false;
            }
            for node.children {
                // TODO: will need to to more work here to handle constant struct members
                member := ti_struct.members[it_index];
                member_any := Any.{ member.type, node.binding.value_pointer + member.offset_in_bytes };
                if !add_data_binding_to_node(it, member_any)  return false;
            }
            
            
          case .ARRAY;
            array := Any_Array.from(node.binding);
            if array.array_type == .RESIZABLE {
                /*
                    IMPORTANT NOTE: 
                    It is critical that the proper amount of space is pre-allocated for the dynamic array 
                    and that we don't have to realloc when we make data bindings for elements below.
                    Because if we realloc then that invalidates the pointers in the data bindings that we created
                    for all previous elements, since those are now pointing to the old locations of each element.
                    This may prove to be one of the more fragile aspects of the DOM parser in contrast to the SAX implementation,
                    because this definitely seems like something that a user could break through a problematic callback procedure.
                    
                    AND A NEW NOTE FOR ME:
                    As mentioned in the other comment up top, this complication is now completely unnecessary because we don't 
                    actually need to separate the making and evaluation of data bindings when we aren't concerned with field references.
                    But, until I am sure that I won't be adding those back in, we're stuck in limbo.
                */
                raw_array    := node.binding.value_pointer.(*Resizable_Array);
                count_before := raw_array.count;
                
                array_reserve(raw_array, count_before + node.children.count, array.element_type.runtime_size);
                raw_array.count += node.children.count;
                
                for node.children {
                    if !add_data_binding_to_node(it, array[it_index])  return false;
                }
            } else {
                count, data := get_count_and_data(array);
                if data {
                    if node.children.count > count {
                        log_binding_error(node, "bounds check failed on array or slice.");
                        return false;
                    }
                } else if array.array_type == .VIEW {
                    assert(count == 0);
                    resize(array, node.children.count);
                }
                
                for node.children {
                    if !add_data_binding_to_node(it, array[it_index])  return false;
                }
            }
            
            
          case;
            log_binding_error(node, "GON array cannot be bound to type: %", as_type(node.binding.type));
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
                log_binding_error(node, "GON field cannot be bound directly to an enum_flags, use a GON array instead.");
                return false;
            }
            
          case .ARRAY;
            if node.binding.type.(*Type_Info_Array).element_type == type_info(u8) {
                log_binding_error(node, "unable to bind GON field to array type. (A special exception is made for arrays of u8, so that they can be treated like strings.)");
                return false;
            }
            
          case .STRUCT;
            if !io_data || !io_data.parse_proc {
                log_binding_error(node, "unable to bind GON field to struct type unless an IO_Data parse_proc is defined.");
                return false;
            }
            
          case;
            log_binding_error(node, "unable to bind GON field to type: %", as_type(node.binding.type));
            return false;
        }
        
      case;
        // TODO: invalid node type error?
    }
    
    return true;
}


set_value_from_string :: (value: Any, text: string, should_copy_strings := true) -> bool {
    if text.count <= 0  return true;
    
    // special handling for strings, so that we process escape sequences properly
    if value.type.type == .STRING {
        string_value_pointer := value.value_pointer.(*string);
        if !should_copy_strings {
            string_value_pointer.* = text;
        } else {
            str, ok := convert_escape_sequences(text);
            if !ok  return false;
            string_value_pointer.* = str;
        }
        return true;
    } 
    
    return Convert.set_value_from_string(value, text, should_copy_strings);
}

