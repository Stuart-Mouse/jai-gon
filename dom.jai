
Node_Flags :: enum_flags {
    // parsing flags
    // REFERENCES_RESOLVED;
    // BINDING_RESOLVED;
    // BINDING_ON_PATH;
    
    // ARRAY_AS_OBJECT;
    // ARRAY_INDEXED;
    // ARRAY_ENUMERATED;
    
    // PENDING_DEPENDENCY;
    
    // TODO: this can probably be removed
    // used to mark that we should not try to assign the name of a gon object to the name_member of a struct
    // DONT_ASSIGN_NAME;
    
    // used to indicate that a field assumes the parent object's binding, used for special field value ref syntax
    // BIND_PARENT;
    
    // formatting flags
    SAME_LINE;
}

Node_Type :: enum { 
    UNINITIALIZED :: 0;
    FIELD         :: 1;
    OBJECT        :: 2;
    ARRAY         :: 3;
}

// this struct is kinda big
// maybe we optimize this later, but for now just making it work
Node :: struct {
    parent, next, prev: *Node;
    
    name:       string;
    type:       Node_Type;
    flags:      Node_Flags;
    location:   Source_Code_Location;
    binding:    Any;
    
    using content: union {
        value:      string;
        children:   Node_List;
    };
}

Node_List :: struct { 
    first:  *Node;
    last:   *Node;
    count:  int;
};

for_expansion :: (list: *Node_List, body: Code, flags: For_Flags) #expand {
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


Node_Insert_Mode :: enum {
    DEFAULT;        // just insert nodes with no extra checks
    OVERWRITE;      // overwrite existing nodes with the same name
    UNDERWRITE;     // don't insert node if one with the same name already exists
}

get_node_index :: (node: *Node) -> int {
    index := 0;
    n := node.prev;
    while n != null {
        index += 1;
        n = n.prev;
    }
    return index;
}

// TODO: add ability to index array nodes?
// relative path only
find_node_by_path :: (node: *Node, path: string) -> (*Node, int) {
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
find_node_by_path :: (parser: *Parser, node: *Node, path: string) -> (*Node, int) {
    if !path  return node, get_node_index(node);
    _path := path;
    if !_path return null, -1;
    search_from_node := node;
    if _path[0] == #char "/" {
        advance(*_path);
        search_from_node = parser.root_node;
    }
    ret, idx := find_node_by_path(search_from_node, _path);
    return ret, idx;
}


// will return null if not found
find_child_node_by_name :: (parent: *Node, name: string) -> (*Node, int) {
    if parent.type != .OBJECT && parent.type != .ARRAY {
        return null, -1;
    }
    
    for parent.children
        if it.name == name  
            return it, it_index;
            
    return null, -1;
}

append_data_node :: (parent: *Node, path: string, binding: Any, prepend: bool = false) ->  *Node {    
    node := append_node_with_path(parent, path, prepend = prepend);
    if node == null  return node;
    
    node.binding = binding;
    node.type = determine_node_type_for_serialization(node); // TODO: combine into one  with the below indirect data bindings one below. maybe we just inline those here for now
    
    // make indirect bindings
    if node.type == .OBJECT || node.type == .ARRAY {
        append_nodes_for_indirect_bindings(node);
    }
    
    return node;
}

// does the bare minimum to append a node, not even giving it a name
// after the node is appended, caller should initialize it
append_child_node :: (parent: *Node, prepend := false) ->  *Node {
    node := New(Node);
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

// may be a little bit odd, but if you want tell if a node was overwritten or not, check if type == .UNINITIALIZED. if so, then the node was either created or overwritten
get_or_add_child_node :: (parent: *Node, name: string, behavior: Node_Insert_Mode = .DEFAULT, prepend := false) ->  *Node {
    node: *Node;
    
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

append_node_with_path :: (parent: *Node, path: string, behavior: Node_Insert_Mode = .DEFAULT, prepend: bool = false) -> *Node {
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

remove_node :: (node: *Node) {
    node.parent.children.count -= 1;
    if node.next != null  node.next.prev = node.prev;
    if node.prev != null  node.prev.next = node.next;
    if node.parent.children.first == node  node.parent.children.first = node.next;
    if node.parent.children.last  == node  node.parent.children.last  = node.prev;
}

clone_child_nodes_recursive :: (dst: *Node, src: *Node) -> bool {
    for child: src.children {
        node := append_child_node(dst, false);
        if !clone_node_recursive(node, child)  return false;
    }
    return true;
}

clone_node_recursive :: (dst: *Node, src: *Node) -> bool {    
    dst.name         = src.name;
    dst.type         = src.type;
    dst.flags        = src.flags;
    dst.binding = src.binding;
    dst.content      = .{};
    
    if src.type == {
      case .OBJECT; #through;
      case .ARRAY;
        return clone_child_nodes_recursive(dst, src);
        
      case .FIELD;
        dst.value = src.value;
        
      case .UNINITIALIZED;
        return false;
    }
    
    return true;
}

format_node_path :: (node: *Node) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    append_node_path_to_string_builder(*builder, node);
    return builder_to_string(*builder);
}

append_node_path_to_string_builder :: (builder: *String_Builder, node: *Node) {
    if node.parent != null {
        append_node_path_to_string_builder(builder, node.parent);
        append(builder, "/");
    }
    append(builder, node.name);
}



is_indexed_array :: (node: *Node) -> bool {
    if node == null
    || node.type != .OBJECT 
    || node.binding.type == null 
    || node.binding.type.type != .ARRAY  
        return false;
    
    io_data := get_io_data(node.binding.type);
    return io_data && (io_data.flags & .ARRAY_INDEXED).(bool);
}

is_object_array :: (node: *Node) -> bool {
    if node == null
    || node.type != .OBJECT 
    || node.binding.type == null 
    || node.binding.type.type != .ARRAY  
        return false;
    
    element_io_data := get_io_data(node.binding.type.(*Type_Info_Array).element_type);
    return element_io_data != null && element_io_data.name_member != null;
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

