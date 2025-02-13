
DOM_Node_Flags :: enum_flags {
    // parsing flags
    REFERENCES_RESOLVED;
    BINDING_RESOLVED;
    BINDING_ON_PATH;
    
    ARRAY_AS_OBJECT;
    ARRAY_INDEXED;
    ARRAY_ENUMERATED;
    
    PENDING_DEPENDENCY;
    
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
    
    name:               string;
    type:               Node_Type;
    flags:              DOM_Node_Flags;
    data_binding:       Any;
    // source_location:    Source_Location;
    
    using content: union {
        ref: struct {
            text:   string;     // TODO: rename to 'path'
            node:   *DOM_Node;
            type:   DOM_Node_Ref_Type;
        };
        value:      string;
        children:   DOM_Node_List;
    };
}

DOM_Node_List :: struct { 
    first:  *DOM_Node;
    last:   *DOM_Node;
    count:  int;
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

// TODO: add ability to index array nodes?
// relative path only
find_node_by_path :: (node: *DOM_Node, path: string) -> (*DOM_Node, int) {
    if !path  return node, get_node_index(node);
    _path := path;
    index := 0;
    while node != null {
        next:, _path = path_next(_path);
        if next == ".." { 
            node  = node.parent;
            index = get_node_index(node);
        } else {
            node, index = find_child_node_by_name(node, next);
        }
        if !_path  break;
    }
    return node, index;
}

// relative or absolute path
find_node_by_path :: (parser: *Parser, node: *DOM_Node, path: string) -> (*DOM_Node, int) {
    if !path  return node, get_node_index(node);
    _path := path;
    if !_path return null, -1;
    search_from_node := node;
    if _path[0] == #char "/" {
        advance(*_path);
        search_from_node = parser.dom_root;
    }
    ret, idx := find_node_by_path(search_from_node, _path);
    return ret, idx;
}


// will return null if not found
find_child_node_by_name :: (parent: *DOM_Node, name: string) -> (*DOM_Node, int) {
    if parent.type != .OBJECT && parent.type != .ARRAY {
        return null, -1;
    }
    
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
    parent.children.count += 1;
    
    if prepend {
        if parent.children.first != null {
            parent.children.first.prev = node;
            node.next = parent.children.first;
        }
        parent.children.first = node;
        
        if parent.children.last == null {
            parent.children.last = node;
        }
    } else {
        if parent.children.last != null {
            parent.children.last.next = node;
            node.prev = parent.children.last;
        }
        parent.children.last = node;
        
        if parent.children.first == null {
            parent.children.first = node;
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
    _path := path;
    while true {
        next:, _path = path_next(_path);
        if !_path  return get_or_add_child_node(node, next, behavior, prepend);
        
        child := find_child_node_by_name(node, next);
        if child != null {
            if child.type != .OBJECT {
                return null; // error, we can't create a named subnode on an array or field type node
            }
            node = child;
            continue;
        }
        
        node      = append_child_node(node, prepend);
        node.name = next;
        node.type = .OBJECT;
    }
    
    assert(false, "unreachable");
    return null;
}

remove_node :: (node: *DOM_Node) {
    node.parent.children.count -= 1;
    if node.next != null          node.next.prev    = node.prev;
    if node.prev != null          node.prev.next    = node.next;
    if node.parent.children.first == node  node.parent.children.first = node.next;
    if node.parent.children.last  == node  node.parent.children.last  = node.prev;
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

format_node_path :: (node: *DOM_Node) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    append_node_path_to_string_builder(*builder, node);
    return builder_to_string(*builder);
}

append_node_path_to_string_builder :: (builder: *String_Builder, node: *DOM_Node) {
    if node.parent != null {
        append_node_path_to_string_builder(builder, node.parent);
        append(builder, "/");
    }
    append(builder, node.name);
}


#scope_module

/*
    Node paths follow essentially the same rules as file paths do on Windows.
    
    Instead of using the lexer to incrementally parse path strings, we just use this one procedure which returns the next path token and the remaining string.
    I was using the lexer for this previously, but in retrospect that was really dumb.
    
    The procedure does not currently do anything special to validate the content of the string, but perhaps we should?
    The caller will also have to check if the path is absolute or relative manually before they start splitting the path.
*/

path_next :: (path: string) -> (next: string, remaining: string, ok: bool) {
    found, left, right := split_from_left_by_any(path, "/\\");
    if !found  return path, "", true;
    return left, right, true;
}

