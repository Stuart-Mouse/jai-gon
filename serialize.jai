
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

serialize_node :: (builder: *String_Builder, node: *Node, indent := 0, same_line := false, skip_if_empty := false) -> bool {
    if node == null  return false;
    
    io_data := get_io_data(node.binding.type);
    
    if skip_if_empty || (io_data && (io_data.flags & .SKIP_ELEMS_IF_EMPTY)) {
        if all_bytes_are_zero(node.binding) {
            return true;
        }
    }
    
    in_array       := false;
    is_first_child := false;

    if node.parent != null {
        in_array       = node.parent.node_type == .ARRAY;
        is_first_child = node == node.parent.children.first;
    }
    
    if (same_line || in_array) && !is_first_child 
        append(builder, ",");
    
    if same_line {
        append(builder, " ");
    } else {
        append(builder, "\n");
        for 0..indent-1  append(builder, INDENTATION_STRING);
    }
    
    // @Cleanup: this is all kinda gross and I don't like the temp string in node.name thing that we are doing in insert_data_node
    //           we can probably signify more precisely what should be done here if we pass some flags structure as parameter
    should_write_name := !in_array;
    
    if should_write_name {
        if node.parent && node.parent.binding.type {
            parent_io_data := get_io_data(node.parent.binding.type);
            if parent_io_data && (.ARRAY_INDEXED & parent_io_data.flags) {
                should_write_name = false;
                // node.name will have a temp string with the array index (see insert_data_node)
                append(builder, node.name);
                append(builder, " ");
            }
        }
    }
    
    if should_write_name {
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
            for child: node.children 
                if !serialize_node(builder, child, indent + 1, same_line, should_skip_empty_elements)  
                    then return false;
        }
        
        if same_line {
            append(builder, " ");
        } else {
            append(builder, "\n");
            for 0..indent-1  append(builder, INDENTATION_STRING);
        }
        
        append(builder, ifx is_array then "]" else "}");
        
      case .FIELD;
        // TODO: should probably switch on node.value.type
        if node.binding.type {
            append_field_value(builder, node.binding);
        } else if node.value {
            append_field_value(builder, node.value);
        } else {
            // TODO: maybe we can pass void as the value as a special case ?
            //       but this will not work as we still need the value type...
            //       and at this point we've already written the field name, so can't back out
            //       maybe we should jsut check if field is valid before writing the name. 
            //       any field which has no binding or string value should just be omitted
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

