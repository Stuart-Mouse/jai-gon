LinkedList :: struct($T: Type) {
    first : *LinkedListNode(T);
    last  : *LinkedListNode(T);
    count : int;
}

LinkedListNode :: struct($T: Type) {
    list  : *LinkedList(T);
    next  : *LinkedListNode(T);
    prev  : *LinkedListNode(T);
    value : T; 
}


remove_node_nonpoly :: (node: *LinkedListNode(void)) -> bool {
    if !node || !node.list {
        print("Error: Invalid node.");
        return false;
    }
    list := node.list;

    if node == list.first {
        if node == list.last {
            list.first = null;
            list.last    = null;
        }
        else {
            node.next.prev = null;
            list.first = node.next;
        }
    }
    else if node == list.last {
        node.prev.next = null;
        list.last = node.prev;
    }
    else    {
        node.next.prev = node.prev;
        node.prev.next = node.next;
    }
    
    list.count -= 1;
    return true;
}

remove_node :: inline (node: *LinkedListNode($T)) {
    if !remove_node_nonpoly(xx node) return;
    free(node);
}


add_after_nonpoly :: (after: *LinkedListNode(void), value_size: int) -> *LinkedListNode(void) #must {
    if !after || !after.list {
        print("Error, cannot insert node into list that does not exist.");
        return null; 
    }
    list := after.list;

    node := cast(*LinkedListNode(void))alloc(size_of(LinkedListNode(void)) + value_size);
    node.list = list;
    node.prev = after;
    node.next = after.next;
    node.prev.next = node;
    if node.next then node.next.prev = node;
    list.count += 1;

    if after == list.last then list.last = node;
    return node;
}

add_after :: inline (after: *LinkedListNode($T)) -> *LinkedListNode(T) #must {
    node := cast(*LinkedListNode(T)) add_after_nonpoly(xx after, size_of(T));
    node.value = T.{};
    return node;
}

add_after :: inline (after: *LinkedListNode($T), value: T) -> *LinkedListNode(T) {
    node := cast(*LinkedListNode(T)) add_after_nonpoly(xx after, size_of(T));
    node.value = value;
    return node;
}

add_before_nonpoly :: (before: *LinkedListNode(void), value_size: int) -> *LinkedListNode(void) #must {
    if !before || !before.list {
        print("Error, cannot insert node into list that does not exist.");
        return null;
    }
    list := before.list;

    node := cast(*LinkedListNode(void))alloc(size_of(LinkedListNode(void)) + value_size);
    node.list = list;
    node.prev = before.prev;
    if node.prev then node.prev.next = node;
    node.next = before;
    node.next.prev = node;
    list.count += 1;

    if before == list.first then list.first = node;
    return node;
}

add_before :: inline (before: *LinkedListNode($T)) -> *LinkedListNode(T) #must {
    node := cast(*LinkedListNode(T)) add_before_nonpoly(xx before, size_of(T));
    node.value = T.{};
    return node;
}

add_before :: inline (before: *LinkedListNode($T), value: T) -> *LinkedListNode(T) {
    node := cast(*LinkedListNode(T)) add_before_nonpoly(xx before, size_of(T));
    node.value = value;
    return node;
}

add_first_nonpoly :: (list: *LinkedList(void), value_size: int) -> *LinkedListNode(void) #must {
    if !list {
        print("Error, cannot insert node into list that does not exist.");
        return null;
    }
    node := cast(*LinkedListNode(void))alloc(size_of(LinkedListNode(void)) + value_size);
    node.list = list;
    node.next = list.first;
    if list.first then list.first.prev = node;
    else list.last = node;
    list.first = node;
    list.count += 1;
    return node;
}

add_first :: inline (list: *LinkedList($T)) -> *LinkedListNode(T) #must {
    node := cast(*LinkedListNode(T)) add_first_nonpoly(xx list, size_of(T));
    node.value = T.{};
    return node;
}

add_first :: inline (list: *LinkedList($T), value: T) -> *LinkedListNode(T) {
    node := cast(*LinkedListNode(T)) add_first_nonpoly(xx list, size_of(T));
    node.value = value;
    return node;
}

add_last_nonpoly :: (list: *LinkedList(void), value_size: int) -> *LinkedListNode(void) #must {
    if !list {
        print("Error, cannot insert node into list that does not exist.");
        return null;
    }
    node := cast(*LinkedListNode(void))alloc(size_of(LinkedListNode(void)) + value_size);
    node.list = list;
    node.prev = list.last;
    if list.last then list.last.next = node;
    else list.first = node;
    list.last = node;
    list.count += 1;
    return node;
}

add_last :: inline (list: *LinkedList($T), value: T) -> *LinkedListNode(T) {
    node := cast(*LinkedListNode(T)) add_last_nonpoly(xx list, size_of(T));
    node.value = value;
    return node;
}

add_last :: inline (list: *LinkedList($T)) -> *LinkedListNode(T) #must {
    node := cast(*LinkedListNode(T)) add_last_nonpoly(xx list, size_of(T));
    node.value = T.{};
    return node;
}

clear :: (list: *LinkedList($T)) {
    node := list.first;
    while node {
        next_node := node;
        free(node.value);
        free(node);
        node = next_node;
    }
    list.first = null;
    list.last  = null;
    list.count = 0;
}

print_list :: (list: *LinkedList($T)) {
    node := list.first;
    print("[");
    while node {
        print("%", node.value);
        if node.next print(", ");
        node = node.next;
    }
    print("]");
}