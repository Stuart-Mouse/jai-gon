// DATA SEGMENT

INDENTATION_STRING :: "    ";

Serialize_Proc :: #type (*Parser, *Node_Field, *String_Builder, indent: int) -> bool;

serialize :: (parser: *Parser, builder: *String_Builder, proc: Serialize_Proc = serialize_dom_nodes_to_gon) -> bool {
    // manually iterate over root node's children
    // we don't want to call serialize_dom_nodes_to_gon() on the root node because we don't actually want to print that node explicitly
    for get_fields(parser.dom_root)
        if !proc(parser, it, builder, 0)
            return false;
    return true;
}

serialize_to_string :: (parser: *Parser, proc: Serialize_Proc = serialize_dom_nodes_to_gon) -> (result: string, ok: bool) {
    builder: String_Builder;
    if !serialize(parser, *builder, proc)  return "", false;
    return builder_to_string(*builder), true;
}

serialize_to_file :: (parser: *Parser, file_path: string, proc: Serialize_Proc = serialize_dom_nodes_to_gon) -> bool {
    builder: String_Builder;
    if !serialize(parser, *builder, proc)  return false;
    str := builder_to_string(*builder); defer free(str);
    write_entire_file(file_path, str);
    return true;
}


// We could convert this to an iterative process rather than a recursive one relatively easily,
//      because we don't currently have any need to use the stack to hold state.
// May be worth considering later once functionality is more complete.
serialize_dom_nodes_to_gon :: (using parser: *Parser, node: *Node_Field, builder: *String_Builder, indent := 0) -> bool {
    if parser == null || node == null  return false;
    
    in_array       := false;
    is_first_child := false;
    same_line      := false;
    
    if node.parent != null {
        in_array       = is_array(node.parent);
        is_first_child = node == get_fields(node.parent).first;
        same_line      = (.SAME_LINE & node.parent.field_flags).(bool);      // check for sameline on parent, not self (we do that later)
    }
    
    if (same_line || in_array) && !is_first_child
        append(builder, ",");

    if same_line {
        append(builder, " ");
    } else {
        append(builder, "\n");
        for 0..indent-1  append(builder, INDENTATION_STRING);
    }

    if !in_array {
        append(builder, to_conformant_string(node.name,, temp));
        append(builder, ": ");
    }

    // For debugging, seeing type of data binding
    // if node.binding.value_pointer {
    //     print_to_builder(*builder, "(%) ", (cast(*Type) *node.binding.type).*);
    // }

    if is_aggregate(node) {
        // ensure that end of object/array gets printed on same line if sameline flag is set on self
        same_line ||= (.SAME_LINE & node.field_flags).(bool);
        fields := get_fields(node);

        _is_array := is_array(node);
        if _is_array && fields.first && do_sameline_for_type(fields.first.binding.type) {
            node.field_flags |= .SAME_LINE;
            same_line = true;
        }

        append(builder, ifx _is_array then "[" else "{");

        // recurse for children
        for fields  if !serialize_dom_nodes_to_gon(parser, it, builder, indent + 1)  return false;

        if same_line {
            append(builder, " ");
        } else {
            append(builder, "\n");
            for 0..indent-1  append(builder, INDENTATION_STRING);
        }

        append(builder, ifx _is_array then "]" else "}");
    } else {
        if node.binding.type.type == .STRING {
            append(builder, to_conformant_string(node.binding.value_pointer.(*string).*,, temp));
        } else {
            print_to_builder(builder, "%", node.binding);
        }
    }

    return true;
}

// determination is currently made based only on node's data binding and parent's data binding, but we will probably consider some other flags on the node later
// the type set here is authoritative, so when we go to actually serialize a node later, it must be serializable as this type
determine_node_type_for_serialization :: (node: *Node_Field) -> *Type_Info {
    if node.binding.value_pointer == null  return .OBJECT;
    
    io_data := get_io_data(node.binding.type);
    
    type: Type;
    if node.binding.type.type == {
      case .INTEGER; #through;
      case .FLOAT;   #through;
      case .STRING;  #through;
      case .ENUM;    #through;
      case .BOOL;
        type = Node_Field;
        
      case .ARRAY;
        ti_array := node.binding.type.(*Type_Info_Array);
        
        // arrays of bytes/u8 are serialized as string
        // we will probably distinguish this later on u8 vs byte, where byte is serialized using some binary data blob
        if ti_array.element_type.runtime_size == 1 {
            type = Node_Field;
        } else {
            if io_data && (.AS_OBJECT | .ARRAY_INDEXED) & io_data.serialize.flags
                then type = Node_Object;
                else type = Node_Array;
        }
        
      case .STRUCT;
        if io_data && .AS_ARRAY & io_data.serialize.flags 
            then type = Node_Array;
            else type = Node_Object;
    }
    
    return type.(*Type_Info);
}

append_nodes_for_indirect_bindings :: (node: *Node_Field) {
    if node == null || node.binding.value_pointer == null  return;

    if node.binding.type.type == {
      case .STRUCT;
        ti_struct := node.binding.type.(*Type_Info_Struct);
        for ti_struct.members {
            member_any := Any.{ it.type, node.binding.value_pointer + it.offset_in_bytes };
            // figure out whether to prepend elems (will do for things that need to be attrs)
            append_data_node(node, it.name, member_any);
        }
        return;

      case .ARRAY;
        array := make_any_array(node.binding.type);
        for array {
            // TODO: as indexed, as object
            elem_name := tprint("%", it_index);
            append_data_node(node, elem_name, it);
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

to_conformant_string :: (s: string, force_quotes := false) -> string {
    if s == ""  return copy_string("\"\"");

    sb: String_Builder;

    write_quotes := force_quotes || (s.count == 0) || !is_legal_identifier(s);

    if write_quotes  append(*sb, "\"");

    for c: s {
        if c == 0  break;
        if is_escaped_char(c) {
            append(*sb, "\\");
        }
        append(*sb, c);
    }

    if write_quotes  append(*sb, "\"");

    return builder_to_string(*sb);
}