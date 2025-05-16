
// serializes to the parser's internal string builder
// user will still need to write the constructed string out to a file
serialize :: (using parser: *Parser) -> bool {
    if parser.root_node == null  
        return false;
    
    for root_node.children 
        if !serialize_node(parser, it)
            return false;
    
    return true;
}

serialize_to_string :: (using parser: *Parser) -> (result: string, ok: bool) {
    if !serialize(parser)  return "", false;
    return builder_to_string(*parser.builder), true;
}

serialize_to_file :: (using parser: *Parser, file_path: string) -> bool {
    if !serialize(parser)  return false;
    write_entire_file(file_path, builder_to_string(*parser.builder));
    return true;
}

serializer_insert_binding :: (parser: *Parser, path: string, binding: Any, prepend: bool = false) {
    append_data_node(parser.root_node, path, binding, prepend);
}


// INTERNAL PROCEDURES

// We could convert this to an iterative process rather than a recursive one relatively easily,
//      because we don't currently have any need to use the stack to hold state.
// May be worth considering later once functionality is more complete.
serialize_node :: (using parser: *Parser, node: *Node) -> bool {
    if parser == null || node == null  return false;
    
    in_array       := false;
    is_first_child := false;
    same_line      := false;

    if node.parent != null {
        in_array       = node.parent.node_type == .ARRAY;
        is_first_child = node == node.parent.children.first;
        same_line      = (.SAME_LINE & node.parent.flags).(bool);      // check for sameline on parent, not self (we do that later)
    }
    
    if (same_line || in_array) && !is_first_child 
        append(*builder, ",");
    
    if same_line {
        append(*builder, " ");
    } else {
        append(*builder, "\n");
        for 0..indent-1  append(*builder, INDENTATION_STRING);
    }
    
    if !in_array {
        append(*builder, to_conformant_string(node.name,, temp));
        append(*builder, " ");
    }
    
    // For debugging, seeing type of data binding
    // if node.binding.value_pointer {
    //     print_to_builder(*builder, "(%) ", (cast(*Type) *node.binding.type).*);
    // }
    
    if node.node_type == {
      case .OBJECT; #through;
      case .ARRAY;
        // ensure that end of object/array gets printed on same line if sameline flag is set on self
        same_line ||= (.SAME_LINE & node.flags).(bool);
        
        is_array := (node.node_type == .ARRAY);
        if is_array && node.children.first && do_sameline_for_type(node.children.first.binding.type) {
            node.flags |= .SAME_LINE;
            same_line = true;
        }
        
        append(*builder, ifx is_array then "[" else "{");
        
        // recurse for children
        indent += 1;
        for child: node.children 
            if !serialize_node(parser, child)  
                then return false;
        indent -= 1;
        
        if same_line {
            append(*builder, " ");
        } else {
            append(*builder, "\n");
            for 0..indent-1  append(*builder, INDENTATION_STRING);
        }
        
        append(*builder, ifx is_array then "]" else "}");
        
      case .FIELD;
        // TODO: should probably switch on node.value.type
        string_value := node.value;
        if string_value == "" {
            if node.binding.value_pointer == null {
                log("ERROR: no value defined for node '%v'\n", format_node_path(node));
                return false;
            }
            
            // TODO: callback for custom serialization?
            string_value = tprint("%", node.binding); 
        }
        append(*builder, to_conformant_string(string_value,, allocator = temp));
    }
    
    return true;
}

// determination is currently made based only on node's data binding and parent's data binding, but we will probably consider some other flags on the node later
// the type set here is authoritative, so when we go to actually serialize a node later, it must be serializable as this type
determine_node_type_for_serialization :: (node: *Node) -> Node_Type {
    if node.binding.value_pointer == null  return .OBJECT;
    
    io_data := table_find_pointer(*IO_Data_Lookup, node.binding.type);
    
    if node.binding.type.type == {
      case .INTEGER; #through;
      case .FLOAT;   #through;
      case .STRING;  #through;
      case .BOOL;  
        return .FIELD;
        
      case .ENUM;
        ti_enum := node.binding.type.(*Type_Info_Enum);
        if !(ti_enum.enum_type_flags & .FLAGS) {
            return .FIELD;
        }
        // check if parent data binding is the same.
        if node.parent && node.parent.binding.value_pointer == node.binding.value_pointer {
            return .FIELD;
        }
        node.flags |= .SAME_LINE;
        return .ARRAY;
        
      case .ARRAY;
        // arrays of bytes/u8 are serialized as string
        // we will probably distinguish this later on u8 vs byte, where byte is serialized using some binary data blob
        ti_array := node.binding.type.(*Type_Info_Array);
        if ti_array.element_type.runtime_size == 1 {
            return .FIELD;
        }
        if io_data {
            if (.AS_OBJECT     & io_data.serialize.flags) ||
               (.ARRAY_INDEXED & io_data.serialize.flags) {
                return .OBJECT;
            }
        }
        return .ARRAY;
        
      case .STRUCT;
        if io_data {
            if .AS_ARRAY & io_data.serialize.flags {
                return .ARRAY;
            }
        }
        return .OBJECT;
    }
    
    return .INVALID;
}

append_nodes_for_indirect_bindings :: (node: *Node) {
    if node == null || node.binding.value_pointer == null  return;
    
    if node.binding.type.type == {
      case .STRUCT;
        ti_struct := node.binding.type.(*Type_Info_Struct);
        for ti_struct.members {
            member_any := Any.{
                value_pointer = node.binding.value_pointer + it.offset_in_bytes,
                type          = it.type,
            };
            // figure out whether to prepend elems (will do for things that need to be attrs)
            append_data_node(node, it.name, member_any);
        }
        return;
        
      case .ARRAY;
        ti_array := node.binding.type.(*Type_Info_Array);
    
        // TODO: use get_array_count_and_data?
        count, data := get_array_count_and_data(node.binding.value_pointer, ti_array);
        if count == 0 || data == null  return;
        
        for 0..elem_count-1 {
            elem_any := Any.{
                value_pointer = data + (ti_array.element_type.runtime_size * it),
                type          = ti_array.element_type
            };
            
            // TODO: as indexed, as object
            elem_name: string = tprint("%", it);
            append_data_node(node, elem_name, elem_any);
        }
        
        return;
    }
}

do_sameline_for_type :: (ti: *Type_Info) -> bool {
    return ti      == null
        || ti.type == .INTEGER
        || ti.type == .FLOAT 
        || ti.type == .ENUM;
}

is_escaped_char :: (char: u8) -> bool {
    return char == #char "\\" || char == #char "\"";
}

to_conformant_string :: (str: string, force_quotes := false) -> string {
    if str == ""  return copy_string("\"\"");
    
    sb: String_Builder;
    write_quotes := force_quotes || (str.count == 0) || find_index_of_any_from_left(str, whitespace_and_reserved_chars) >= 0;
    
    if write_quotes  append(*sb, "\"");
    for char: str {
        if char == 0  break;
        if is_escaped_char(char) {
            append(*sb, "\\");
        }
        append(*sb, char);
    }
    if write_quotes  append(*sb, "\"");
    
    return builder_to_string(*sb);
}

#scope_file

INDENTATION_STRING :: "    ";

