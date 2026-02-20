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
    language:           Language;
    root:               *Node;
    io_data_table:      *IO_Data_Table;
    
    memory_pool:        Flat_Pool;  // TODO: Just allow user to set any Allocator here, and make sure we free nodes individually if the allocator does not support freeing all at once. 
    node_free_list:     Node_List;
    
    last_error_string:  string;     // NOTE: allocated with temporary allocator
    
    Node :: struct {
        using links: struct {
            parent, next, previous: *Node;
        }
        
        kind:           Kind;
        name:           string;
        location:       Source_Code_Location;
        binding:        Any;
        
        // TODO: may add some indication of the enclosing quotation mark character used
        string_value:   string;
        attributes:     Node_List;
        children:       Node_List;
        
        Kind :: enum { 
            UNINITIALIZED   :: 0;
            
            // JSON
            FIELD           :: 1;
            OBJECT          :: 2;
            ARRAY           :: 3;
            
            // XML
            TAG             :: 4;
            ATTRIBUTE       :: 5;
            CHARACTER_DATA  :: 6;
        }
    }
    
    Node_List :: struct { 
        first:      *Node;
        last:       *Node;  
        count:      int;
    }
    
    Node_Insertion_Behaviour :: struct {
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
            
            IS_ATTRIBUTE :: 2; // TODO: implement logic to handle this!
        }
    }
    
    DEFAULT_NODE_INSERTION_BEHAVIOUR :: Node_Insertion_Behaviour.{ mode = .LANGUAGE_DEFAULT };
}

for_expansion :: (list: *Data_Model.Node_List, body: Code, $flags: For_Flags) #expand {
    #assert (flags & .POINTER == 0);
    #if flags & .REVERSE {
        `it_index := list.count;
        `it := list.last;
        while it {
            previous := it.previous;
            defer { it = previous; it_index -= 1; }
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

maybe_get_default :: inline (model: *Data_Model, insertion_mode: Data_Model.Node_Insertion_Behaviour.Mode) -> Data_Model.Node_Insertion_Behaviour.Mode {
    return ifx insertion_mode == .LANGUAGE_DEFAULT 
        then model.language.default_node_insertion_behaviour.mode
        else insertion_mode;
}

init_data_model :: (model: *Data_Model) {
    reset(*model.memory_pool, overwrite_memory = true);
    init(*model.memory_pool);
}

deinit_data_model :: (model: *Data_Model) {
    model.language.deinit(model);
    fini(*model.memory_pool);
}

is_aggregate :: (node: *Data_Model.Node) -> bool {
    return node.children.count != 0;
}

contains_only_character_data :: (node: *Data_Model.Node) -> bool {
    return !is_aggregate(node) || node.children.first.kind == .CHARACTER_DATA;
}

// ===== Navigating the Data_Model =====

find_node :: (model: *Data_Model, cursor: *Data_Model.Node, path: string) -> node: *Data_Model.Node, index: int {
    pathfinder := model.language.pathfinder;
    set_path(*pathfinder, path);
    node, index := find_node(model, cursor, *pathfinder);
    return node, index;
}

// returns null if the node was not found
find_node :: (model: *Data_Model, cursor: *Data_Model.Node, pathfinder: *Pathfinder) -> node: *Data_Model.Node, index: int {
    while cursor {
        path_step := get_step(pathfinder);
        if #complete path_step.kind == {
          case .ABSOLUTE;           cursor = model.root;
          case .STEP_INTO_BY_NAME;  cursor = get_child_node_by_name(cursor, path_step.name);
          case .STEP_INTO_BY_INDEX; cursor = get_child_node_by_index(cursor, path_step.index);
          case .STEP_OUT_OF;        cursor = cursor.parent;
          case .END;                break;
        }
    }
    return cursor, 0;   // TODO: need to return index here!
}

get_child_node_by_name :: (parent: *Data_Model.Node, name: string) -> *Data_Model.Node, int {
    // if !is_aggregate(parent)  return null, -1;
    
    for parent.children
        if it.name == name
            return it, it_index;
    
    return null, -1;
}

get_child_node_by_index :: (parent: *Data_Model.Node, index: int) -> *Data_Model.Node, int {
    // if !is_aggregate(parent) || index > parent.children.count  return null, -1;
    if index > parent.children.count  return null, -1;
    
    // TODO: Could optimize by indexing from back when that would require fewer steps.
    child := parent.children.first;
    for 1..index  child = child.next;
    return child, index;
}


// ===== Inserting and Removing Nodes =====

// NOTE: Once the first node is inserted at the given path, the binding will create new child nodes recursively for all struct members and array elements.
insert_node_with_binding :: (model: *Data_Model, parent: *Data_Model.Node, path: string, binding: Any, override_kind := Data_Model.Node.Kind.UNINITIALIZED, insertion_mode := Data_Model.DEFAULT_NODE_INSERTION_BEHAVIOUR) -> *Data_Model.Node {    
    if parent == null {
        ensure_root_node_exists(model);
        parent = model.root;
    }
    
    if binding.type == null || binding.value_pointer == null {
        report_error(model, parent, "Cannot insert node with null binding into data model.");
        return null;
    }
    
    io_data := get_io_data(model, binding.type);
    node_kind := ifx override_kind else ifx io_data then io_data.preferred_node_kind_for_serialization;
    
    node: *Data_Model.Node;
    if path {
        node = insert_node_with_path(model, parent, path, node_kind, insertion_mode);
    } else {
        node = insert_child_node(model, parent, "", node_kind, insertion_mode.flags & .PREPEND == .PREPEND);
    }
    if node == null  return node;
    
    node.binding = binding;
    
    // make indirect data bindings for aggregates, unless the aggregate has defined to_string() in its io data.
    if io_data && io_data.to_string {
        node.kind = ifx node.kind else .FIELD;
    } else {
        base_type := get_variant_base_type(binding.type);
        if base_type.type == {
          case .STRUCT;
            node.kind = ifx node.kind else .OBJECT;
            
            structure := Any_Structure.{ xx base_type, binding.value_pointer };
            for structure {
                #this(model, node, it_info.name, it, insertion_mode = insertion_mode);
            }
            
          case .ARRAY;
            node.kind = ifx node.kind else .ARRAY;
            
            array := Any_Array.{ xx base_type, binding.value_pointer };
            element_io_data := get_io_data(model, array.element_type);
            get_name := ifx node.kind != .ARRAY && element_io_data then element_io_data.get_name;
            
            for array {
                name := ifx get_name then get_name(it);
                #this(model, node, name, it, insertion_mode = insertion_mode);
            }
            
          case;
            node.kind = ifx node.kind else .FIELD;
        }
    }
    
    assert(node.kind != .UNINITIALIZED, "node.kind was uninitialized for node @ %", format_node_path(model, node,, temp));   
    return node;
}

insert_child_node :: (
    model: *Data_Model, 
    parent: *Data_Model.Node, 
    name := "", 
    kind := Data_Model.Node.Kind.UNINITIALIZED, 
    prepend := false,
) -> *Data_Model.Node {
    node := New(Data_Model.Node,, get_allocator(model));
    node.name   = name;
    node.kind   = kind;
    node.parent = parent;
    add_node_to_list(*parent.children, node, prepend);
    return node;
}

maybe_insert_child_node :: (
    model: *Data_Model, 
    parent: *Data_Model.Node, 
    name: string, 
    kind: Data_Model.Node.Kind, 
    insertion_mode := Data_Model.DEFAULT_NODE_INSERTION_BEHAVIOUR,
) -> (
    node: *Data_Model.Node, 
    found_existing: bool
) {
    // if parent.kind != .OBJECT {
    //     log("Data Model Error: Cannot create a named child node on an array or field node.");
    //     return null;
    // }
    
    mode  := maybe_get_default(model, insertion_mode.mode);
    flags := insertion_mode.flags;
    
    node: *Data_Model.Node;
    found_existing := false;
    
    if #complete mode == {
      case .OVERWRITE;
        // TODO: If we overwrite some node with children, we should 'free' those child nodes.
        //       This is not a big deal right now, because we don't actually *need* to free any nodes individually, 
        //       but maybe in the future I will add some mechanism to put 'freed' nodes on a freelist and recycle them where possible. (This should actually be very easy to do...)
        node = get_child_node_by_name(parent, name);
        node.* = .{ name = name, kind = kind, links = node.links }; // NOTE: It is important that we keep the existing links!
        
      case .RETURN_EXISTING;
        node = get_child_node_by_name(parent, name);
        
      case .ALLOW_DUPLICATES;
        // no op
        
      case .LANGUAGE_DEFAULT; 
        assert(false, "unreachable");
    }
    
    // base case
    if node == null {
        node = insert_child_node(model, parent, name, kind, flags & .PREPEND == .PREPEND);
    } else {
        found_existing = true;
    }
    return node, found_existing;
}

insert_node_with_path :: (model: *Data_Model, cursor: *Data_Model.Node, path: string, kind := Data_Model.Node.Kind.UNINITIALIZED, insertion_mode := Data_Model.DEFAULT_NODE_INSERTION_BEHAVIOUR) -> *Data_Model.Node {
    pathfinder := model.language.pathfinder;
    set_path(*pathfinder, path);
    
    while cursor {
        path_step, is_final := get_step(*pathfinder);
        if #complete path_step.kind == {
          case .ABSOLUTE;
            cursor = model.root;
            
          case .STEP_INTO_BY_NAME;
            if is_final {
                return insert_child_node(model, cursor, path_step.name, kind, insertion_mode.flags & .PREPEND == .PREPEND);
            } else {
                cursor = get_child_node_by_name(cursor, path_step.name);
            }
            
            // TODO: Consider reimplementing logic like this to create empty objects if necessary, but only when some insertion flag is present.
            // child := find_child_node_by_name(cursor, path_step.name);
            // if child == null {
            //     child = insert_child_node(node, insertion_mode.flags & .PREPEND == .PREPEND);
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
    
    report_error(model, cursor, "Path given to insert_node_with_path does not terminate with a valid node name.");
    return null;
}

// ========== Node Manipulation ==========

/*
    Nodes are all stored in a pool, so we don't technically need to free nodes when we remove them from the data model.
    But in order to prevent unnecessary memory use, we will opportunistically recycle nodes that were previously removed.
    At the time a node is removed, we just add it to out free list. We don't even bother with removing the child nodes recursively.
    When a node is pulled from the free list, we will then remove any existing child nodes and add those to the free list as well.
    This ensures that we aren't spending any time unnecessarily removing nodes that are no longer connected to the root, but at the same time we won't leak any nodes that could potentially be recycled.
*/

remove_node :: (model: *Data_Model, node: *Data_Model.Node) {
    node.parent.children.count -= 1;
    if node.next != null  node.next.previous = node.previous;
    if node.previous != null  node.previous.next = node.next;
    if node.parent != null {
        list := ifx node.kind == .ATTRIBUTE then node.parent.attributes else node.parent.children;
        if list.first == node {
            list.first = node.next;
        }
        if list.last == node {
            list.last = node.previous;
        }
    }
    add_node_to_list(model.node_free_list, node);
}

get_node_from_free_list :: (model: *Data_Model) -> *Data_Model.Node {
    node := list_pop_front(model.node_free_list);
    if node {
        for node.children   remove_node(model, it);
        for node.attributes remove_node(model, it);
    }
    node.* = .{};
    return node;
}

add_node_to_list :: (list: *Data_Model.Node_List, node: *Data_Model.Node, prepend := false) {
    if prepend {
        if list.first != null {
            list.first.previous = node;
            node.next = list.first;
        }
        list.first = node;
        
        if list.last == null {
            list.last = node;
        }
    } else {
        if list.last != null {
            list.last.next = node;
            node.previous = list.last;
        }
        list.last = node;
        
        if list.first == null {
            list.first = node;
        }
    }
    list.count += 1;
}

list_pop_front :: (list: *Data_Model.Node_List) {
    if list.count == 0  return null;
    list.count -= 1;
    
    node := list.first;
    list.first = node.next;
    if list.last == node {
        list.last = null;
    }
    
    node.parent = null;
    node.next   = null;
    return node;
}

list_pop_back :: (list: *Data_Model.Node_List) {
    if list.count == 0  return null;
    list.count -= 1;
    
    node := list.last;
    list.last = node.next;
    if list.first == node {
        list.first = null;
    }
    
    node.parent   = null;
    node.previous = null;
    return node;
}

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


// ========== Data Bindings ==========

Binding_With_Path :: struct { binding: Any; path: string; }

has_valid_binding :: (node: *Data_Model.Node) -> bool {
    return node.binding.type != null && node.binding.value_pointer != null;
}

add_data_binding :: (model: *Data_Model, binding: Any, path: string) -> bool {
    node := find_node(model, model.root, path);
    // TODO: should warn when unable to find node
    if node {
        return add_data_binding_to_node(model, node, binding);
    } else {
        log("warning: unable to locate node: %", path);
        return true;
    }
}

add_data_bindings :: (model: *Data_Model, bindings: ..Binding_With_Path) -> bool {
    for bindings
        if !add_data_binding(model, it.binding, it.path)  
            return false;
    return true;
}

process_data_bindings :: (model: *Data_Model) -> bool {
    return process_node_binding(model, model.root);
}

process_node_binding :: (model: *Data_Model, node: *Data_Model.Node) -> bool {
    io_data := get_io_data(model, node.binding.type);
    
    if has_valid_binding(node) {
        if io_data && io_data.set_name {
            io_data.set_name(node.binding, node.name);
        }
        if node.string_value && contains_only_character_data(node) {
            if io_data && io_data.from_string {
                if !io_data.from_string(node.binding, node.string_value) {
                    report_error(model, node, "User-defined from_string() proc for type '%' failed with string_value '%'", as_type(node.binding.type), node.string_value);
                    return false;
                }
            } else {
                if !set_value_from_string(node.binding, node.string_value) {
                    log("failed to set value of % node '%' from string value: %", node.kind, node.name, node.string_value);
                    return false;
                }
            }
            return true;
        }
    }
    
    if is_aggregate(node) {
        /*
            For now, regardless of the node type, if the node's binding is to a non-aggregate type then we act as if all child nodes chare this node's data binding.
            Maybe this is not the best long-term approach and we should alter the logic here.
            Also, note that strings are currently considered an aggregate type, so this will not result in repeatedly assigning to the same string value (which would likely cause memory leaks).
            
            The main reason for having this logic in place is for binding XML attribute values to their parent tags, and for potentially allowing multi-valued JSON fields as a language extensnion (for the sake of ergonomic enum flags in GON).
        */
        if has_valid_binding(node) 
        && !is_aggregate(node.binding.type) {
            for node.children  if !set_value_from_string(node.binding, it.string_value)  return false;
        } else {
            for node.children  if !process_node_binding(model, it)  return false;
        }
    }
    
    return true;
}

add_data_binding_to_node :: (model: *Data_Model, node: *Data_Model.Node, binding: Any) -> bool  {
    if has_valid_binding(node)  return true;
    
    if node.binding.type != null {
        report_error(model, node, "Attempt to add data binding to node which already has an existing binding.");
        return false;
    }
    
    node.binding = binding;
    io_data := get_io_data(model, node.binding.type);
    if io_data && io_data.on_bind {
        io_data.on_bind(model, node);
        io_data = get_io_data(model, node.binding.type);
    }
    
    // TODO: think about whether we want to reimplement pointer dereferencing stuff
    //       this is maybe something people could do with IO Data bind proc, but maybe that's too type-specific actually
    
    // TODO: Need to seriously consider whether or not the making of bindings should be separate from the evaluation.
    //       Since I removed field references, there's no longer really a need for this to be two separate steps, 
    //       but I may still add those back in in a more limited form, so... i dunno yet.
    
    // make indirect bindings onto child nodes
    if node.kind == {
      case .TAG;
        #through;
        
      case .OBJECT;
        if binding.type.type == {
          case .STRUCT;
            structure := Any_Structure.from(binding);
            for node.children {
                found, member, info := get_member(structure, it.name, recursive = true);
                if !found || info.flags & .CONSTANT  continue;
                
                // TODO: figure out how to solve the duplicate bindings issue posed by 'using'
                //       I don't want to introduce tons of additional checks if possible!
                
                if !add_data_binding_to_node(model, it, member)  return false;
            }
            
          case .ARRAY;
            array := Any_Array.from(node.binding);
            
            count, data := get_count_and_data(array);
            element_io_data := get_io_data(model, array.element_type);
            
            // TODO: add generalized means for getting an array index from the given field name
            
            // NOTE: We apply an offset to the index used for child bindings when we are 
            //       dealing with a resizable array which already contains some elements.
            index_offset := 0;
            
            if array.array_type == {
              case .RESIZABLE;
                resize(array, node.children.count + count, true);
                index_offset = count;
                
              case .FIXED; #through;
              case .VIEW;
                if data {
                    if node.children.count > count {
                        report_error(model, node, "Cannot bind object node to array. Object contains % elements, but array only contains space for % elements.", node.children.count, count);
                        return false;
                    }
                } else if array.array_type == .VIEW {
                    assert(count == 0);
                    resize(array, node.children.count, true);
                }
            }
            for node.children {
                if !add_data_binding_to_node(model, it, array[index_offset + it_index])  return false;
            }
            
          case;
            // NOTE: we have to check this because of the fallthrough from the TAG case.
            if node.kind == .OBJECT {
                report_error(model, node, "Cannot bind object node to data of type %.", as_type(node.binding.type));
                return false;
            }
        }
        
        
      case .ARRAY;
        if binding.type.type == {
          case .STRUCT;
            structure := Any_Structure.from(binding);
            
            // NOTE: We don't avoid #place members here, since that will be removed from the language soon anyhow.
            child := node.children.first;
            for structure {  defer child = child.next;
                if child == null {
                    report_error(model, node, "Ran out of nodes while creating bindings for members of struct type '%'.", as_type(xx structure.type));
                }
                if !add_data_binding_to_node(model, child, it)  return false;
            }
            if child != null {
                report_error(model, node, "Too many nodes provided in array with binding to struct type '%'.", as_type(xx structure.type));
            }
            
          case .ARRAY;
            array := Any_Array.from(node.binding);
            count, data := get_count_and_data(array);
            index_offset: int; // for dynamic array case, where we want to leave the existing items untouched
            
            if array.array_type == {
              case .RESIZABLE;
                resize(array, count + node.children.count, true);
                index_offset = count;
                
              case .VIEW;
                if data == null {
                    assert(count == 0);
                    resize(array, node.children.count, true);
                    count = node.children.count; // doing this because we read count in the .FIXED case below
                }
                #through;
                
              case .FIXED;
                if node.children.count > count {
                    report_error(model, node, "Cannot bind array node to array. Array node contains % elements, but array only contains space for % elements.", node.children.count, count);
                    return false;
                }
            }
            
            count, data = get_count_and_data(array);
            for node.children {
                if !add_data_binding_to_node(model, it, array[index_offset + it_index])  return false;
            }
            
          case;
            report_error(model, node, "Cannot bind array node to data of type %.", as_type(node.binding.type));
            return false;
        }
        
      case .FIELD;
        if node.binding.type.type == {
          case .INTEGER;    // no op
          case .BOOL;       // no op
          case .FLOAT;      // no op
          case .STRING;     // no op
          case .ENUM;       // no op
            
          case .ARRAY;
            array_info := node.binding.type.(*Type_Info_Array);
            if array_info.element_type.type == .INTEGER 
            && array_info.element_type.runtime_size == 1 {
                report_error(model, node, "Cannot bind field node to array type. (A special exception is made for arrays of u8, so that they can be treated like strings.)");
                return false;
            }
            
          case .STRUCT;
            if !(io_data && io_data.from_string) {
                report_error(model, node, "Cannot bind field node to struct type unless from_string() is defined in the type's IO_Data.");
                return false;
            }
            
          case;
            report_error(model, node, "Cannot bind field node to type: %", as_type(node.binding.type));
            return false;
        }
        
      case;
        report_error(model, node, "Invalid node kind in %: %", #procedure_name(), node.kind);
        return false;
    }
    
    return true;
}


get_allocator :: (model: *Data_Model) -> Allocator {
    return .{ flat_pool_allocator_proc, *model.memory_pool };
}

// TODO: Need to allow user to replace this, should probably also be able to override on a per-language basis...
set_value_from_string :: (value: Any, text: string, should_copy_strings := true) -> bool {
    if text.count <= 0  return true;
    
    // special handling for strings, so that we process escape sequences properly
    if value.type.type == .STRING {
        string_value_pointer := value.value_pointer.(*string);
        if !should_copy_strings {
            string_value_pointer.* = text;
        } else {
            str, ok := unescape_string(text);
            if !ok  return false;
            string_value_pointer.* = str;
        }
        return true;
    } 
    
    return Reflection.set_value_from_string(value, text);
}

ensure_root_node_exists :: (model: *Data_Model) {
    if model.root == null {
        model.root = New(Data_Model.Node,, get_allocator(model));
        model.root.* = .{
            name = "",
            kind = .OBJECT,
        };
    }
}

