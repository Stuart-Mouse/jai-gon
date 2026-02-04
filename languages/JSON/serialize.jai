#scope_module

/*
    Most of the serialization logic is all #scope_module because it's still somewhat subject to change over time, 
    but there's also little enough code here, I think, that it's relatively understandable if you feel the need to modify it.
*/

JSON_Serialize_Flags :: enum_flags {
    NONE :: 0;
    SAME_LINE :: 1;
    SKIP_IF_EMPTY;
    IS_FIRST_CHILD;
}

JSON_serialize_node :: (builder: *String_Builder, model: *Data_Model, node: *Data_Model.Node) -> bool {
    return JSON_serialize_node(builder, model, node, 0, .IS_FIRST_CHILD);
}

JSON_serialize_node :: (builder: *String_Builder, model: *Data_Model, node: *Data_Model.Node, indent: int, flags: JSON_Serialize_Flags) -> bool {
    using json_context := model.language.language_context.(*JSON_Context);
    
    if node == null  return false;
    
    io_data := get_io_data(model, node.binding.type);
    
    if (flags & .SKIP_IF_EMPTY) || (io_data && (io_data.flags & .SKIP_IF_EMPTY)) {
        if all_bytes_are_zero(node.binding) {
            return true;
        }
    }
    
    same_line := (flags & .SAME_LINE).(bool);
    
    if !(flags & .IS_FIRST_CHILD) {
        append(builder, ",");
    }
    
    if same_line {
        append(builder, " ");
    } else {
        append(builder, "\n");
        for 0..indent-1  append(builder, indentation_string);
    }
    
    // TODO: 
    if node.parent.kind != .ARRAY {
        omit_quotes := (lexer_flags & .PERMIT_IDENTIFIERS_AS_KEYS) && lexer.is_legal_identifier(node.name);
        if omit_quotes
            then append(builder, node.name);
            else JSON_append_string(builder, node.name);
        append(builder, ": ");
    }
    
    if node.kind == {
      case .OBJECT; #through;
      case .ARRAY;
        should_skip_empty_elements := io_data && (io_data.flags & .SKIP_ELEMS_IF_EMPTY);
        
        is_array := (node.kind == .ARRAY);
        if is_array && node.children.first {
            element_type := node.children.first.binding.type;
            same_line |= element_type      == null
                      || element_type.type == .INTEGER
                      || element_type.type == .FLOAT 
                      || element_type.type == .ENUM; 
        }
        
        append(builder, ifx is_array then "[" else "{");
        
        child_flags := JSON_Serialize_Flags.IS_FIRST_CHILD 
            | (ifx same_line then .SAME_LINE)
            | (ifx should_skip_empty_elements then .SKIP_IF_EMPTY);
            
        // enum_index_type := ifx io_data then io_data.enum_index_type;
        for node.children {
            if !#this(builder, model, it, indent + 1, child_flags)  return false;
            child_flags &= ~.IS_FIRST_CHILD;
        }
        
        if same_line {
            append(builder, " ");
        } else {
            append(builder, "\n");
            for 0..indent-1  append(builder, indentation_string);
        }
        
        append(builder, ifx is_array then "]" else "}");
        
      case .ATTRIBUTE;
        // TODO: add configurable prefix for attributes that get serialized as JSON fields
        #through;
        
      case .FIELD;
        if node.binding.type {
            JSON_append_field_value(builder, node.binding);
        } else if node.string_value {
            JSON_append_field_value(builder, node.string_value);
        } else {
            log("Error: no value defined for node '%v'\n", format_node_path(model, node));
            return false;
        }
    }
    
    return true;
}

JSON_append_string :: (builder: *String_Builder, text: string, quote_char: u8 = "\"") -> bool {
    append(builder, quote_char);
    ok := unescape_string(builder, text);
    append(builder, quote_char);
    return ok;
}

JSON_append_field_value :: (builder: *String_Builder, value: Any, io_data: *IO_Data = null, quote_char: u8 = "\"") -> bool {
    if io_data && io_data.to_string {
        ok, string_value := io_data.to_string(value);
        JSON_append_string(builder, string_value);
        return ok;
    }
    
    if value.type.type == {
      case .STRING;
        JSON_append_string(builder, value.value_pointer.(*string).*);
        
      case .INTEGER;    #through;
      case .FLOAT;      #through;
      case .BOOL;
        print_item_to_builder(builder, value);
        
      case .ENUM;
        // TODO: this should be a language context procedure
        append(builder, quote_char);
        print_item_to_builder(builder, value);
        append(builder, quote_char);
        
      case .STRUCT;
        log("Error: unable to serialize struct as GON field without a custom serialization proc.");
        
      case .ARRAY;
        array_info := value.type.(*Type_Info_Array);
        assert(array_info.element_type.runtime_size == 1);
        
        count, data := get_array_count_and_data(array_info, value.value_pointer);
        JSON_append_string(builder, string.{ count, data });
    }
    return true;
}

