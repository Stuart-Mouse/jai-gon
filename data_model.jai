/*
    Data Model
    
    Because of the need to do arbitrary insertions and deletions of nodes, 
    the data model is represented as a sort of DOM or tree structure.
    
    The performances characteristics should still be 'not that bad' though,
    because we are using a flat pool allocator for the nodes and we are generally visiting them in the same order they are laid out in memory.
    I say this with absolutely no proof though, because I have not performance tested this code at all. 
    If someone else with more time wants to do that and tell me how slow it is, I will consider trying to improve it.
    
    For now, all the different node kinds are using the same struct. 
    I will probably keep it this way as well, since it is likely easier for people to extend this with new language support if we don't have some complex hierarchy of different node types.
    
*/

Data_Model :: struct {
    language:           Langauge_Info;
    root:               Node;
    
    memory_pool:        Flat_Pool;  // TODO: Give user control over the pool type used. Needs to match a specific interface.
    // node_free_list:     Node_List;
    
    Node :: struct {
        using links: struct {
            parent, next, previous: *Node;
        }
        
        // kind:           Kind;
        name:           string;
        location:       Source_Code_Location;
        binding:        Any;
        
        string_value:   string;
        value_flags:    Value_Flags;
        
        children:       Node_List;
        
        attributes:     [] Attribute;
        
        Attribute :: struct {
            key, value: string;
        }
        
        // Kind :: enum { 
        //     UNINITIALIZED :: 0;
        //     FIELD         :: 1;
        //     OBJECT        :: 2;
        //     ARRAY         :: 3;
        // }
    }
    
    Node_List :: struct { 
        first:      *Node;
        last:       *Node;  
        count:      int;
    }
    
    Node_Insertion_Behaviour :: struct 
        mode:   Mode; 
        flags:  Flags;
        
        Mode :: enum u8 {
            OVERWRITE        :: 0;
            ALLOW_DUPLICATES :: 1;
            RETURN_EXISTING  :: 2;
            
            LANGUAGE_DEFAULT :: 255;
        }
        
        Flags :: enum u8 {
            NONE    :: 0;
            PREPEND :: 1;
        }
    }
    
    DEFAULT_NODE_INSERTION_BEHAVIOUR :: Node_Insertion_Behaviour.{ mode = .LANGUAGE_DEFAULT };
}

for_expansion :: (list: *Node_List, body: Code, $flags: For_Flags) #expand {
    #assert (flags & .POINTER == 0);
    #if flags & .REVERSE {
        `it_index := list.count;
        `it := list.last;
        while it {
            prev := it.prev;
            defer { it = prev; it_index -= 1; }
            #insert body;
        }
    } else {
        `it_index := 0;
        `it := list.first;
        while it {
            next := it.next;
            defer { it = next; it_index += 1; }
            #insert body;
        }
    }
}

maybe_get_default :: inline (model: *Data_Model, insertion_behaviour: Node_Insertion_Behaviour.Mode) -> Node_Insertion_Behaviour.Mode {
    return ifx insertion_behaviour.mode == .LANGUAGE_DEFAULT 
        then model.language.default_node_insertion_behaviour
        else insertion_behaviour;
}

// ===== Navigating the Data_Model =====

find_node :: (model: *Data_Model, cursor: *Data_Model.Node, path: string) -> node: *Data_Model.Node, index: int {
    pathfinder := model.language.pathfinder;
    pathfinder.path = make_path(path);
    return find_node(model, cursor, pathfinder);
}

// returns null if the node was not found
find_node :: (model: *Data_Model, cursor: *Data_Model.Node, pathfinder: *Pathfinder) -> node: *Data_Model.Node, index: int {
    while cursor {
        path_step := step(pathfinder);
        if #complete path_step.kind == {
          case .ABSOLUTE;           cursor = model.root;
          case .STEP_INTO_BY_NAME;  cursor = get_child_node_by_name(cursor, path_step.name);
          case .STEP_INTO_BY_INDEX; cursor = get_child_node_by_index(cursor, path_step.index);
          case .STEP_OUT_OF;        cursor = cursor.parent;
          case .END;                break;
        }
    }
    return cursor;
}

get_child_node_by_name :: (parent: *Node_Field, name: string) -> *Data_Model.Node, int {
    if !is_aggregate(parent)  return null, -1;
    
    for parent.children
        if it.name == name
            return it, it_index;
    
    return null, -1;
}

get_child_node_by_index :: (parent: *Node_Field, index: int) -> *Data_Model.Node, int {
    if !is_aggregate(parent) || index > parent.children.count  return null, -1;
    
    // TODO: Could optimize by indexing from back when that would require fewer steps.
    child := parent.children.first;
    for 1..index  child = child.next;
    return child, index;
}


// ===== Inserting and Removing Nodes =====

// NOTE: Once the first node is inserted at the given path, the binding will create new child nodes recursively for all struct members and array elements.
insert_node_with_binding :: (model: *Data_Model, parent: *Data_Model.Node, path: string, binding: Any, insert_mode := Node_Insert_Mode.OVERWRITE) -> *Data_Model.Node {    
    if binding.type == null || binding.value_pointer == null {
        log("Data Model Error: Cannot insert node with null binding.");
        return null;
    }
    
    parent = ifx parent else model.root;
    
    node := insert_node_with_path(model, parent, path, insert_mode);
    if node == null  return node;
    
    // determine node kind for inserted data node
    node.binding = binding;
    io_data := get_io_data(node.binding.type);
    
    // make indirect data bindings for aggregates, unless the aggregate has defined its own serializer.
    if is_aggregate(binding) &&  {
        if node.binding.type.type == {
          case .STRUCT;
            structure := Any_Structure.from(node.binding);
            for structure {
                insert_data_node(parser, node, it_info.name, it);
            }
            
          case .ARRAY;
            array := Any_Array.from(node.binding);
            element_io_data := get_io_data(array.element_type);
            for array {
                elem_name: string;
                if element_io_data && element_io_data.name_member {
                    name_member := get_struct_member(it, element_io_data.name_member);
                    Convert.any_to_any(elem_name, name_member,, temp);
                }
                insert_data_node(parser, node, elem_name, it, .ALLOW_DUPLICATES);
            }
        }
    }
    
    return node;
}

insert_child_node :: (
    model: *Data_Model, 
    parent: *Data_Model.Node, 
    name := "", 
    // kind := Data_Model.Node.Kind.UNINITIALIZED, 
    prepend := false,
) -> *Data_Model.Node {
    node := New(Data_Model.Node,, get_allocator(model));
    node.name = name;
    // node.kind = kind;
    
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

maybe_insert_child_node :: (
    model: *Data_Model, 
    parent: *Data_Model.Node, 
    name: string, 
    // kind: Data_Model.Node.Kind, 
    insertion_behaviour := DEFAULT_NODE_INSERTION_BEHAVIOUR
) -> (
    node: *Data_Model.Node, 
    returned_existing: bool
) {
    // if parent.kind != .OBJECT {
    //     log("Data Model Error: Cannot create a named child node on an array or field node.");
    //     return null;
    // }
    
    mode  := maybe_get_default(model, insertion_behaviour.mode);
    flags := insertion_behaviour.flags;
    
    node: *Data_Model.Node;
    
    if #complete mode == {
      case .OVERWRITE;
        // TODO: If we overwrite some node with children, we should 'free' those child nodes.
        //       This is not a big deal right now, because we don't actually *need* to free any nodes individually, 
        //       but maybe in the future I will add some mechanism to put 'freed' nodes on a freelist and recycle them where possible. (This should actually be very easy to do...)
        node = find_child_node_by_name(parent, name);
        node = .{ name = name, kind = kind, links = node.links }; // NOTE: It is important that we keep the existing links!
        
      case .RETURN_EXISTING;
        node = find_child_node_by_name(parent, name);
        
      case .ALLOW_DUPLICATES;
        // no op
        
      case .LANGUAGE_DEFAULT; 
        unreachable();
    }
    
    // base case
    if node == null {
        node = insert_child_node(model, parent, name, kind, flags & .PREPEND == .PREPEND);
    }
    
    return node;
}

insert_node_with_path :: (model: *Data_Model, cursor: *Data_Model.Node, path: string, insertion_behaviour := DEFAULT_NODE_INSERTION_BEHAVIOUR) -> *Data_Model.Node {
    pathfinder := model.language.pathfinder;
    pathfinder.path = make_path(path);
    
    while cursor {
        path_step, is_final := step(*pathfinder);
        if #complete path_step.kind == {
          case .ABSOLUTE;
            cursor = model.root;
            
          case .STEP_INTO_BY_NAME;
            cursor = get_child_node_by_name(cursor, path_step.name);
            
            // TODO: Consider reimplementing logic like this to create empty objects if necessary, but only when some insertion flag is present.
            // child := find_child_node_by_name(cursor, path_step.name);
            // if child == null {
            //     child = insert_child_node(node, insertion_behaviour.flags & .PREPEND == .PREPEND);
            //     child.name = path_step.name;
            //     child.kind = .OBJECT;
            // }
            // cursor = child;
            
          case .STEP_INTO_BY_INDEX;
            cursor = get_child_node_by_index(cursor, path_step.index);
            
          case .STEP_OUT_OF;
            cursor = cursor.parent;
            
          case .END;
            break;
        }
    }
    
    return null;
}

// TODO
// remove_node :: (model: *Data_Model, node: *Data_Model.Node) {
//     node.parent.children.count -= 1;
//     if node.next != null  node.next.prev = node.prev;
//     if node.prev != null  node.prev.next = node.next;
//     if node.parent.children.first == node  node.parent.children.first = node.next;
//     if node.parent.children.last  == node  node.parent.children.last  = node.prev;
//     add_node_to_free_list(model, node);
// }

// clone_child_nodes_recursive :: (dst: *Data_Model.Node, src: *Data_Model.Node) -> bool {
//     for child: src.children {
//         node := insert_child_node(dst, false);
//         if !clone_node_recursive(node, child)  return false;
//     }
//     return true;
// }

// clone_node_recursive :: (dst: *Data_Model.Node, src: *Data_Model.Node) -> bool {    
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


#scope_module

get_allocator :: (model: *Data_Model) -> Allocator {
    return .{ flat_pool_allocator_proc, *model.memory_pool };
}

