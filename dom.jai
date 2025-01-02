
DOM_Node_Flags :: enum_flags {
    // parsing flags
    REFERENCES_RESOLVED;
    BINDING_RESOLVED;
    BINDING_ON_PATH;
    
    ARRAY_AS_OBJECT;
    ARRAY_INDEXED;
    ARRAY_ENUMERATED;
    
    // used to mark that we should not try to assign the name of a gon object to the name_member of a struct
    DONT_ASSIGN_NAME;
    
    // used to indicate that a field assumes the parent object's binding, used for special field value ref syntax
    BIND_PARENT;

    // formatting flags
    SAME_LINE;
}

DOM_Node_Ref_Type :: enum { 
    VALUE; 
    POINTER; 
    INDEX; 
};

Node_Type :: enum { 
    INVALID :: 0;
    FIELD   :: 1;
    OBJECT  :: 2;
    ARRAY   :: 3;
    REF     :: 4;
}

// this struct is kinda big
// maybe we optimize this later, but for now just making it work
DOM_Node :: struct {
    parent, next, prev: *DOM_Node;
    
    // src_loc      : Source_Location;
    
    name:  string;
    type:  Node_Type;
    flags: DOM_Node_Flags;
    
    data_binding: Any;
    
    using content: union {
        ref: struct {
            text: string;
            node: *DOM_Node;
            type: DOM_Node_Ref_Type;
        };
        
        value: string;
        
        using children: DOM_Node_List;
    };
}

DOM_Node_List :: struct { 
    first : *DOM_Node;
    last  : *DOM_Node;
    count : int;
};

for_expansion :: (list: *DOM_Node_List, body: Code, flags: For_Flags) #expand {
    #if flags & .REVERSE {
        `it_index := list.count;
        `it := list.last;
        while it {
            prev := it.prev;
            defer { it = prev; it_index -= 1; }
            #insert(remove={remove_node(it);}) body;
        }
    } else {
        `it_index := 0;
        `it := list.first;
        while it {
            next := it.next;
            defer { it = next; it_index += 1; }
            #insert(remove={remove_node(it);}) body;
        }
    }
}


Node_Insertion_Behaviour :: enum {
    DEFAULT;        // just insert nodes with no extra checks
    OVERWRITE;      // overwrite existing nodes with the same name
    UNDERWRITE;     // don't insert node if one with the same name already exists
}

get_node_index :: (node: *DOM_Node) -> int {
    index := 0;
    n := node.prev;
    while n != null {
        index += 1;
        n = n.prev;
    }
    return index;
}

// does not delete the passed node or its neighbors, only children
// delete_child_nodes_recursive :: (node: *DOM_Node) {
//     if node.type == .OBJECT || node.type == .ARRAY {
//         for child: node.children {
//             delete_child_nodes_recursive(child);
//             free(child);
//         }
//     }
// }

find_node_by_path :: (node: *DOM_Node, path: string) -> (*DOM_Node, int) {
    t: Tokenizer = .{ file = path };
    get_token(*t); // TODO: note why?
    
    index := 0;
    while node != null {
        next := get_next_token_from_path_string(*t);
        if next.type == .ERROR return null, 0;
        if next.type == .EOF break;
        if next.type == .PATH_PARENT { 
            node = node.parent; 
            continue;
        };
        node, index = find_child_node_by_name(node, next.text);
    }
    
    return node, index;
}

// will return null if not found
find_child_node_by_name :: (parent: *DOM_Node, name: string) -> (*DOM_Node, int) {
    for parent.children
        if it.name == name  
            return it, it_index;
            
    return null, -1;
}

append_data_node :: (parent: *DOM_Node, path: string, data_binding: Any, prepend: bool = false) ->  *DOM_Node {    
    node := append_node_with_path(parent, path, prepend = prepend);
    if node == null  return node;
    
    node.data_binding = data_binding;
    node.type = determine_node_type_for_serialization(node); // TODO: combine into one  with the below indirect data bindings one below. maybe we just inline those here for now
    
    // make indirect bindings
    if node.type == .OBJECT || node.type == .ARRAY {
        append_nodes_for_indirect_bindings(node);
    }
    
    return node;
}

// does the bare minimum to append a node, not even giving it a name
// after the node is appended, caller should initialize it
append_child_node :: (parent: *DOM_Node, prepend := false) ->  *DOM_Node {
    node := New(DOM_Node);
    // if !node return null;
    
    node.parent = parent;
    parent.count += 1;
    
    if prepend {
        if parent.first != null {
            parent.first.prev = node;
            node.next = parent.first;
        }
        parent.first = node;
        
        if parent.last == null {
            parent.last = node;
        }
    } else {
        if parent.last != null {
            parent.last.next = node;
            node.prev = parent.last;
        }
        parent.last = node;
        
        if parent.first == null {
            parent.first = node;
        }
    }
    
    return node;
}

// may be a little bit odd, but if you want tell if a node was overwritten or not, check if type == .INVALID. if so, then the node was either created or overwritten
get_or_add_child_node :: (parent: *DOM_Node, name: string, behavior: Node_Insertion_Behaviour = .DEFAULT, prepend := false) ->  *DOM_Node {
    node: *DOM_Node;
    
    if behavior != .DEFAULT {
        node = find_child_node_by_name(parent, name);
    }
    
    if node == null {
        node = append_child_node(parent, prepend);
    } 
    else if behavior == .UNDERWRITE {
        return node;
    }
    
    node.* = .{ name = name };
    return node;
}

append_node_with_path :: (parent: *DOM_Node, path: string, behavior: Node_Insertion_Behaviour = .DEFAULT, prepend: bool = false) -> *DOM_Node {
    node := parent;
    
    t: Tokenizer = .{ file = path };
    get_token(*t);
    
    while true {
        next := get_next_token_from_path_string(*t);
        if next.type == .ERROR  return null;
        
        if peek_token(*t).type == .EOF {
            return get_or_add_child_node(node, next.text, behavior, prepend);
        }
        
        child := find_child_node_by_name(node, next.text);
        if child != null {
            if child.type != .OBJECT {
                return null; // error, we can't create a named subnode on an array or field type node
            }
            node = child;
            continue;
        }
        
        node      = append_child_node(node, prepend);
        node.name = next.text;
        node.type = .OBJECT;
    }
    
    assert(false, "unreachable");
    return null;
}

remove_node :: (node: *DOM_Node) {
    node.parent.count -= 1;
    if node.next != null          node.next.prev    = node.prev;
    if node.prev != null          node.prev.next    = node.next;
    if node.parent.first == node  node.parent.first = node.next;
    if node.parent.last  == node  node.parent.last  = node.prev;
    // NOTE: no need to free now that we are using pool for allocating nodes
}


clone_child_nodes_recursive :: (dst: *DOM_Node, src: *DOM_Node) -> bool {
    for child: src.children {
        node := append_child_node(dst, false);
        if !clone_node_recursive(node, child)  return false;
    }
    return true;
}

clone_node_recursive :: (dst: *DOM_Node, src: *DOM_Node) -> bool {    
    // free child nodes so we can overwrite
    // if dst.type == .OBJECT {
    //     delete_child_nodes_recursive(dst);
    // }
    
    dst.name         = src.name;
    dst.type         = src.type;
    dst.flags        = src.flags;
    dst.data_binding = src.data_binding;
    dst.content      = .{};

    if src.type == {
      case .OBJECT; #through;
      case .ARRAY;
        return clone_child_nodes_recursive(dst, src);
        
      case .REF;
        dst.ref = src.ref;
        if dst.ref.type == .VALUE {
            log_error("ERROR: cloned a value ref node @ %v", format_node_path(dst));
        }
        
      case .FIELD;
        dst.value = src.value;
        
      case .INVALID;
        return false;
    }
    
    return true;
}

get_next_token_from_path_string :: (t: *Tokenizer) -> Token {
    next := get_token_or_return(t, .{ type = .ERROR });
    
    if next.type == {
        case .EOF;
        case .PATH_PARENT;
        case .STRING; 
            // no op
        case; 
            return .{ type = .ERROR };
    }
    
    expect_token_type(t, .PATH_SPLIT);
    return next;
}

format_node_path :: (node: *DOM_Node) -> string {
    recurse :: (builder: *String_Builder, node: *DOM_Node) {
        if node.parent != null {
            recurse(builder, node.parent);
            append(builder, "/");
        }
        append(builder, node.name);
    }
    
    builder: String_Builder;
    init_string_builder(*builder);
    recurse(*builder, node);
    return builder_to_string(*builder);
}
