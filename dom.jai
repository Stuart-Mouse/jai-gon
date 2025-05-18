
Node_Type :: enum { 
    UNINITIALIZED :: 0;
    FIELD         :: 1;
    OBJECT        :: 2;
    ARRAY         :: 3;
}

Node :: struct {
    parent, next, prev: *Node;
    
    name:       string;
    node_type:  Node_Type;
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


// ===== Finding Nodes =====

// TODO: add ability to index array nodes?
// relative path only
find_node_by_path :: (node: *Node, path: string) -> (*Node, int) {
    _path := path;
    
    if !_path  return node, get_lexical_index(node);
    index := 0;
    while node != null {
        next:, _path = path_next(_path);
        if next == ".." { 
            node  = node.parent;
            index = get_lexical_index(node);
        } else {
            node, index = find_child_node_by_name(node, next);
        }
        if !_path  break;
    }
    return node, index;
}

// relative or absolute path
find_node_by_path :: (parser: *Parser, node: *Node, path: string) -> (*Node, int) {
    _path := path;
    
    if !_path  return node, get_lexical_index(node);
    search_from_node := node;
    
    is_absolute_path := _path[0] == #char "/";
    if is_absolute_path {
        advance(*_path);
        search_from_node = parser.root_node;
    }
    
    ret, idx := find_node_by_path(search_from_node, _path);
    return ret, idx;
}

find_child_node_by_name :: (parent: *Node, name: string) -> (*Node, int) {
    if parent.node_type != .OBJECT && parent.node_type != .ARRAY {
        return null, -1;
    }
    
    for parent.children
        if it.name == name  
            return it, it_index;
            
    return null, -1;
}

get_lexical_index :: (node: *Node) -> int {
    if node == null  return -1;
    index := 0;
    while node {
        index += 1;
        node = node.prev;
    }
    return index;
}


// ===== Inserting and Removing Nodes =====

// Defines how to handle when an existing node resides at the same path on the DOM that we wish to insert into.
// Be aware that the default insert modes varies based on the procedure.
Node_Insert_Mode :: enum_flags {
    RETURN_EXISTING :: 0;
    OVERWRITE       :: 1;
    ALLOW_DUPLICATE;
    PREPEND;
}

insert_data_node :: (parent: *Node, path: string, binding: Any, insert_mode := Node_Insert_Mode.OVERWRITE) ->  *Node {    
    node := insert_node_with_path(parent, path, insert_mode);
    if node == null  return node;
    
    node.binding = binding;
    node.node_type = determine_node_type_for_serialization(node);
    
    // make indirect data bindings for objects and arrays
    if node.node_type == .OBJECT || node.node_type == .ARRAY {
        if node.binding.type.type == {
          case .STRUCT;
            iterate_struct_members(node.binding, #code {
                insert_data_node(node, it_info.name, it);
            });
            
          case .ARRAY;
            array := Any_Array.from(node.binding.type);
            for array {
                // TODO: better handling for indexed and object arrays using IO data
                elem_name: string = tprint("%", it_index);
                insert_data_node(node, elem_name, it);
            }
        }
    }
    
    return node;
}

// does the bare minimum to append a node, not even giving it a name
// after the node is appended, caller should initialize it
insert_child_node :: (parent: *Node, prepend := false) ->  *Node {
    node := New(Node);
    
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

get_or_insert_child_node :: (parent: *Node, name: string, insert_mode := Node_Insert_Mode.RETURN_EXISTING) ->  *Node {
    node: *Node;
    
    if !(insert_mode & .ALLOW_DUPLICATE) {
        node = find_child_node_by_name(parent, name);
    }
    if node == null {
        node = insert_child_node(parent, insert_mode & .PREPEND);
    }
    if insert_mode & .OVERWRITE {
        node.* = .{ name = name };
    }
    
    return node;
}

insert_node_with_path :: (parent: *Node, path: string, insert_mode := Node_Insert_Mode.OVERWRITE) -> *Node {
    node := parent;
    while true {
        next:, path = path_next(path);
        if !path  return get_or_insert_child_node(node, next, insert_mode);
        
        child := find_child_node_by_name(node, next);
        if child != null {
            if child.type != .OBJECT {
                log("GON DOM Error: Cannot create a named child node on an array or field node.");
                return null;
            }
            node = child;
            continue;
        }
        
        node           = insert_child_node(node, insert_mode & .PREPEND);
        node.name      = next;
        node.node_type = .OBJECT;
    }
    
    unreachable();
    return null;
}

// does not deallocate node, since we use a flat pool for node allocation
remove_node :: (node: *Node) {
    node.parent.children.count -= 1;
    if node.next != null  node.next.prev = node.prev;
    if node.prev != null  node.prev.next = node.next;
    if node.parent.children.first == node  node.parent.children.first = node.next;
    if node.parent.children.last  == node  node.parent.children.last  = node.prev;
}

// clone_child_nodes_recursive :: (dst: *Node, src: *Node) -> bool {
//     for child: src.children {
//         node := insert_child_node(dst, false);
//         if !clone_node_recursive(node, child)  return false;
//     }
//     return true;
// }

// clone_node_recursive :: (dst: *Node, src: *Node) -> bool {    
//     dst.name         = src.name;
//     dst.type         = src.type;
//     dst.flags        = src.flags;
//     dst.binding = src.binding;
//     dst.content      = .{};
    
//     if src.type == {
//       case .OBJECT; #through;
//       case .ARRAY;
//         return clone_child_nodes_recursive(dst, src);
        
//       case .FIELD;
//         dst.value = src.value;
        
//       case .UNINITIALIZED;
//         return false;
//     }
    
//     return true;
// }

// ===== Format Node Path =====

format_node_path :: (node: *Node) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    format_node_path(*builder, node);
    return builder_to_string(*builder);
}

format_node_path :: (builder: *String_Builder, node: *Node) {
    if node.parent != null {
        format_node_path(builder, node.parent);
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


// helper function that I may remove if I go back to just flagging the node...
is_indexed_array :: (node: *Node) -> bool {
    if node == null
    || node.node_type != .OBJECT 
    || node.binding.type == null 
    || node.binding.type.type != .ARRAY  
        return false;
    
    io_data := get_io_data(node.binding.type);
    return io_data && (io_data.flags & .ARRAY_INDEXED).(bool);
}

