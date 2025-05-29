
serialize_to_string :: (using parser: *Parser) -> (result: string, ok: bool) {
    builder: String_Builder;
    if !serialize_to_builder(parser, *builder) {
        free_buffers(*builder);
        return "", false;
    }
    return builder_to_string(*builder), true;
}

serialize_to_file :: (using parser: *Parser, file_path: string) -> bool {
    builder: String_Builder;
    if !serialize_to_builder(parser, *builder) {
        free_buffers(*builder);
        return "", false;
    }
    return write_entire_file(file_path, builder_to_string(*builder));
}

serialize_to_builder :: (using parser: *Parser, builder: *String_Builder) -> bool {
    if parser.root_node == null  return false;
    
    for root_node.children 
        if !serialize_node(builder, it)
            return false;
    
    return true;
}


#scope_module

/*
    Most of the serialization logic is all #scope_module because it's still somewhat subject to change over time, 
    but there's also little enough code here, I think, that it's relatively understandable if you feel the need to modify it.
*/

Serialize_Flags :: enum_flags {
    SAME_LINE;
    SKIP_IF_EMPTY;
    IN_ARRAY;
    IN_INDEXED_ARRAY;
    IS_FIRST_CHILD;
}

serialize_node :: (builder: *String_Builder, node: *Node, indent := 0, flags: Serialize_Flags = xx 0, enum_index_type: *Type_Info = null) -> bool {
    if node == null  return false;
    
    io_data := get_io_data(node.binding.type);
    
    if (flags & .SKIP_IF_EMPTY) || (io_data && (io_data.flags & .SKIP_IF_EMPTY)) {
        if all_bytes_are_zero(node.binding) {
            return true;
        }
    }
    
    same_line := (flags & .SAME_LINE).(bool);
    
    if (flags & (.SAME_LINE | .IN_ARRAY)) && !(flags & .IS_FIRST_CHILD) {
        append(builder, ",");
    }
    
    if same_line {
        append(builder, " ");
    } else {
        append(builder, "\n");
        for 0..indent-1  append(builder, INDENTATION_STRING);
    }
    
    if flags & .IN_INDEXED_ARRAY {
        // determine real index within parent array
        parent_array := Any_Array.from(node.parent.binding);
        index := get_element_index(parent_array, node.binding.value_pointer);
        print(builder, "% ", Any.{ ifx enum_index_type else xx int, *index });
    } else if !(flags & .IN_ARRAY) {
        if is_legal_identifier(node.name) 
            then append(builder, node.name);
            else append_gon_string(builder, node.name);
        append(builder, " ");
    }
    
    if node.node_type == {
      case .OBJECT; #through;
      case .ARRAY;
        should_skip_empty_elements := io_data && (io_data.flags & .SKIP_ELEMS_IF_EMPTY);
        
        is_array := (node.node_type == .ARRAY);
        if is_array && node.children.first {
            element_type := node.children.first.binding.type;
            same_line |= element_type      == null
                      || element_type.type == .INTEGER
                      || element_type.type == .FLOAT 
                      || element_type.type == .ENUM; 
        }
        
        append(builder, ifx is_array then "[" else "{");
        
        // special case for serializing enum flags
        // we ignore child nodes and just write the array of flags values directly
        if node.binding.type && node.binding.type.type == .ENUM {
            ti_enum := node.binding.type.(*Type_Info_Enum);
            assert(ti_enum.enum_type_flags & .FLAGS == .FLAGS); 
            same_line = true; // currently always on one line
            
            // NOTE: the below logic for printing the enum_flags values has been copied from Print.jai
            
            target_value := get_u64_from_void_pointer(node.binding.value_pointer, node.binding.type.runtime_size);  // Treat flags as unsigned, even for signed types. Simpler.

            if target_value == 0 {
                // Check for a named 0-value before printing 0.
                name := "0";
                for ti_enum.values  if it == 0 {
                    name = ti_enum.names[it_index];
                    break;
                }
                
                append(builder, name);
                return true;
            }

            // I felt like doing this in unsigned for some reason!
            flags_total := target_value;
            flags_printed : u64 = 0;

            first := true;
            for ti_enum.values {
                value := cast(u64) it;
                matching := flags_total & value;
                if matching != value  matching = 0;  // We need to match all of the bits in the enum member.

                if !matching continue;
                if !(matching & ~flags_printed) continue;

                flags_printed |= matching;

                if first  append(builder, " ");
                else      append(builder, ", ");
                append(builder, ti_enum.names[it_index]);
                first = false;
            }
            
            unmatched := flags_total & ~flags_printed;
            if unmatched {
                if !first  append(builder, ", 0x");
                format := FormatInt.{base=16};
                print_u64_base_n(builder, unmatched, format);
            }
        } else {
            flags: Serialize_Flags = .IS_FIRST_CHILD 
                | (ifx is_array then .IN_ARRAY)
                | (ifx io_data && (io_data.flags & .ARRAY_INDEXED) then .IN_INDEXED_ARRAY)
                | (ifx same_line then .SAME_LINE)
                | (ifx should_skip_empty_elements then .SKIP_IF_EMPTY);
                
            enum_index_type := ifx io_data then io_data.enum_index_type;
            for node.children {
                if !serialize_node(builder, it, indent + 1, flags, enum_index_type)  return false;
                flags &= ~.IS_FIRST_CHILD;
            }
        }
        
        if same_line {
            append(builder, " ");
        } else {
            append(builder, "\n");
            for 0..indent-1  append(builder, INDENTATION_STRING);
        }
        
        append(builder, ifx is_array then "]" else "}");
        
      case .FIELD;
        if node.binding.type {
            append_field_value(builder, node.binding);
        } else if node.value {
            append_field_value(builder, node.value);
        } else {
            log("Error: no value defined for node '%v'\n", format_node_path(node));
            return false;
        }
    }
    
    return true;
}

append_gon_string :: (builder: *String_Builder, text: string, quote_char: u8 = "\"") -> bool {
    append(builder, quote_char);
    ok := revert_escape_sequences(builder, text);
    append(builder, quote_char);
    return ok;
}

append_field_value :: (builder: *String_Builder, value: Any) -> bool {
    io_data := get_io_data(value.type);
    if io_data && io_data.serialize_proc {
        string_value, ok := io_data.serialize_proc(value);
        append_gon_string(builder, string_value);
        return ok;
    }
    
    if value.type.type == {
      case .STRING;
        // always enclose in quotes and escape any characters which need to be escaped
        // for GON we really should only need to escape quotation marks and backslashes
        append_gon_string(builder, value.value_pointer.(*string).*);
        
      case .INTEGER;    #through;
      case .FLOAT;      #through;
      case .BOOL;
        print(builder, "%", value);
        
      case .ENUM;
        // assert not enum_flags
        ti_enum := value.type.(*Type_Info_Enum);
        assert(ti_enum.enum_type_flags & .FLAGS == 0);
        print(builder, "%", value);
        
      case .STRUCT;
        log("Error: unable to serialize struct as GON field without a custom serialization proc.");
        
      case .ARRAY;
        ti_array := value.type.(*Type_Info_Array);
        assert(ti_array.element_type.runtime_size == 1);
        
        array_count, array_data := get_array_count_and_data(ti_array, value.value_pointer);
        append_gon_string(builder, string.{ array_count, array_data });
    }
    return true;
}

#scope_file

INDENTATION_STRING :: "    ";

