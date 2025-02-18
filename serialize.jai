// DATA SEGMENT

INDENTATION_STRING :: "    ";

Serialize_Proc :: #type (*Parser, *DOM_Node, *String_Builder, indent: int) -> bool;

serialize :: (parser: *Parser, builder: *String_Builder, proc: Serialize_Proc = serialize_dom_nodes_to_gon) -> bool {
    // manually iterate over root node's children
    // we don't want to call serialize_dom_nodes_to_gon() on the root node because we don't actually want to print that node explicitly
    for parser.dom_root.children
        if !proc(parser, it, builder, 0)
            then return false;
    
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
serialize_dom_nodes_to_gon :: (using parser: *Parser, node: *DOM_Node, builder: *String_Builder, indent := 0) -> bool {
    if parser == null || node == null  return false;

    in_array       := false;
    is_first_child := false;
    same_line      := false;

    if node.parent != null {
        in_array       = node.parent.type == .ARRAY;
        is_first_child = node == node.parent.children.first;
        same_line      = (.SAME_LINE & node.parent.flags).(bool);      // check for sameline on parent, not self (we do that later)
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
        append(builder, " ");
    }

    // For debugging, seeing type of data binding
    // if node.data_binding.value_pointer {
    //     print_to_builder(*builder, "(%) ", (cast(*Type) *node.data_binding.type).*);
    // }

    if node.type == {
      case .OBJECT; #through;
      case .ARRAY;
        // ensure that end of object/array gets printed on same line if sameline flag is set on self
        same_line ||= (.SAME_LINE & node.flags).(bool);

        is_array := (node.type == .ARRAY);
        if is_array && node.children.first && do_sameline_for_type(node.children.first.data_binding.type) {
            node.flags |= .SAME_LINE;
            same_line = true;
        }

        append(builder, ifx is_array then "[" else "{");

        // recurse for children
        for child: node.children
            if !serialize_dom_nodes_to_gon(parser, child, builder, indent + 1)
                then return false;

        if same_line {
            append(builder, " ");
        } else {
            append(builder, "\n");
            for 0..indent-1  append(builder, INDENTATION_STRING);
        }

        append(builder, ifx is_array then "]" else "}");

      case .FIELD;
        if node.data_binding.type.type == .STRING {
            append(builder, to_conformant_string(node.data_binding.value_pointer.(*string).*,, temp));
        } else {
            print_to_builder(builder, "%", node.data_binding);
        }
    }

    return true;
}

// determination is currently made based only on node's data binding and parent's data binding, but we will probably consider some other flags on the node later
// the type set here is authoritative, so when we go to actually serialize a node later, it must be serializable as this type
determine_node_type_for_serialization :: (node: *DOM_Node) -> Node_Type {
    if node.data_binding.value_pointer == null  return .OBJECT;

    io_data := table_find_pointer(*IO_Data_Lookup, node.data_binding.type);

    if node.data_binding.type.type == {
      case .INTEGER; #through;
      case .FLOAT;   #through;
      case .STRING;  #through;
      case .BOOL;
        return .FIELD;

      case .ENUM;
        ti_enum := node.data_binding.type.(*Type_Info_Enum);
        if !(ti_enum.enum_type_flags & .FLAGS) {
            return .FIELD;
        }
        // check if parent data binding is the same.
        if node.parent && node.parent.data_binding.value_pointer == node.data_binding.value_pointer {
            return .FIELD;
        }
        node.flags |= .SAME_LINE;
        return .ARRAY;

      // arrays of bytes/u8 are serialized as string
      // we will probably distinguish this later on u8 vs byte, where byte is serialized using some binary data blob
      case .ARRAY;
        ti_array := node.data_binding.type.(*Type_Info_Array);
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

      case;
        return .INVALID;
    }

    return .INVALID;
}

append_nodes_for_indirect_bindings :: (node: *DOM_Node) {
    if node == null || node.data_binding.value_pointer == null  return;

    if node.data_binding.type.type == {
      case .STRUCT;
        ti_struct := node.data_binding.type.(*Type_Info_Struct);

        for ti_struct.members {
            member_any := Any.{
                value_pointer = node.data_binding.value_pointer + it.offset_in_bytes,
                type          = it.type,
            };
            // figure out whether to prepend elems (will do for things that need to be attrs)
            append_data_node(node, it.name, member_any);
        }

        return;

      case .ARRAY;
        ti_array := node.data_binding.type.(*Type_Info_Array);

        data       : *void = ---;
        elem_count : int   = ---;

        if ti_array.array_type == .FIXED {
            data       = node.data_binding.value_pointer;
            elem_count = ti_array.array_count;
        } else {
            raw_array := node.data_binding.value_pointer.(*Resizable_Array);
            data       = raw_array.data;
            elem_count = raw_array.count;
            if elem_count == 0  return; // skip serializing empty dynamic arrays
        }

        if data == null  return;

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

to_conformant_string :: (s: string, force_quotes := false) -> string {
    if s == ""  return copy_string("\"\"");

    sb: String_Builder;

    write_quotes := force_quotes || (s.count == 0) || find_index_of_any_from_left(s, whitespace_and_reserved_chars) >= 0;

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