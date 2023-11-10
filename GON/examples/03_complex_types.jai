#import "Basic";
#import "Reflection";
#import "File";
GON :: #import "GON";

/*
  In this example, we'll use a simple implementation of a linked list to show how one can use the parser to load more complex data types, which require some special loading code.

  Our linked list implementation uses a polymorphic struct with a type parameter so that each node of our linked list implementation can work for any type.

  If you're familiar with how a linked list works, you know that there's some housekeeping that needs to be done any time we insert or remove an element from the list, and it's a bit more involved that appending an item to the end of an array.
  We need to perform some memory allocation for the node, and update the next and previous nodes in the list (as well as the list's first and last node pointers).
  Obviously, we don't want to do all of this work manually in our callback, especially since we have to do a lot more work to determine dynamically what the type is for our node's value.
  Forunately, if our data structure is organized in a simple enough way, there are some simple methods we can use to write our GON callback without the need for complex type casting nonsense.

  In this example, we'll only be tackling a simple usage of a polymorphic struct, but the same principles apply when working with more complex polymorphic structs.
*/

// This structure is actually the exact same in structure for all polymorphs (since pointers are all of the same size), but the polymorphs will be used for typechecking and in procedures that create nodes for the list.
LinkedList :: struct($T: Type) {
  first : *LinkedListNode(T);
  last  : *LinkedListNode(T);
  count : int;
}

LinkedListNode :: struct($T: Type) {
  list  : *LinkedList(T);
  next  : *LinkedListNode(T);
  prev  : *LinkedListNode(T);

  /*
    Value is of type T, meaning polymorphs of LinkedListNode may be of different sizes!
    For this reason, the value is stored last in our struct. 
    This ensures that the offset of all of the members of the struct are constant.
    This is something we need to consider when writing not just the implementation of LinkedList, but the callback code for our parser as well.
  */
  value : T; 
}

/*
  This is a simple helper procedure that gives us the Type_Info_Struct_Member of the requested polymorphic struct parameter, 
    which we use in the procedure below to get the value of the Type parameter to the linked list.

  Getting the value of this Type parameter is essential to writing our parser callback, 
    since we need to tell the parser the type of value that we are binding each linked list node's value to.
*/
get_specified_parameter :: inline (ti: *Type_Info_Struct, name: string) -> *Type_Info_Struct_Member {
  for * param: ti.specified_parameters
    if param.name == name 
      return param;
  return null;
}

/*
  Gets a specified parameter of a polymorphic struct by name, type checks the parameter, and then returns the value.
  
  This procedure uses a value bake on the type parameter so that it can return the desired type directly. 
  This is not strictly necessary, but since we will know the type of the parameter we want to check the value of, it provides some convenience.
  (It might as well be a macro, but using a value bake the compiler may potentially deduplicate calls  where the value of T is the same.)
*/
get_specified_parameter_value :: inline (ti: *Type_Info_Struct, name: string, $T: Type) -> T {
  specified_param := get_specified_parameter(ti, name);
  assert(specified_param != null);
  assert(specified_param.type == type_info(T));
  return <<cast(*T)*ti.constant_storage[specified_param.offset_into_constant_storage];
}

/*
  All add and remove operations for our linked list implementation make use of a non-polymorphic procedure that works 
    agnostic of the type stored within our linked list's nodes.
  After all, when we allocate a node, we only need to know the size of the type, 
    but the rest of the logic is identical for connecting nodes regardless of value type.
  The size of the type and the initialization of the value of each node is done in an inlined function which is polymorphic on the value type.
  Having these non-polymorphic functions for adding/removing nodes not only reduces the final size of our binary, 
    it gives us an easy generic functions we can call from our parser callback (where we won't be able to call the polymorphic verions of such a function).
*/
remove_node_nonpoly :: (node: *LinkedListNode(void)) -> bool {
  if !node || !node.list {
    print("Error: Invalid node.");
    return false;
  }
  list := node.list;

  if node == list.first {
    if node == list.last {
      list.first = null;
      list.last  = null;
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
  else  {
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

/*
  Note that these nonpoly procedures all take a polymorph of LinkedList or LinkedListNide with void as the type parameter.
  This will still allow us to access the non-polymorphic fields of the list and nodes (the pointers to neighboring nodes, first and last).
  Technically, we could use any type here since we know that we won't be accessing the value field in our code,
    but void seems a reasonable way to signal intent and ensure that the value is not accessed if someone else comes along later and tries to make changes.
*/
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


main :: () {
  /*
    Create a linked list with the desired element type.
    In this example we will use float, but one could use any data type at all.
  */
  list : LinkedList(float);

  // Our standard code to load from a file.
  gon_file, success := read_entire_file("test.gon");
  if !success {
    print("Error loading file\n");
    return;
  }

  parse_context : GON.ParseContext = .{
    file = gon_file,
    /*
      Just like with our simple data structres, we want to create a data binding to our linked list.
      This will enable the parser to locate this field for us, just as it normally does for simple structs.
      However, we won't want it to bind the struct's members to fields in the same way as a normal struct, 
        so we'll write some callback code to intercept this binding and perform some run loading code instead.
    */
    data_bindings = .[
      .{
        field_address = .["numbers"],
        data_binding  = list
      },
    ],

    event_handler = .{
      /*
        This is where put our code user code for intercepting the child GON fields of a parent GON field which is bound to a linked list.
        While we are inside a GON object or array with a data binding, the parser will usually attempt to make indirect data bindings to the GON fields within.
        So, if the current parent is bound to a LinkedList, then the parser will attempt to create bindings to the fields of the LinkedList struct.
        Obviously, this is not the desired behaviour. So, using a callback, we can run custom code whenever this event would usually occur.
        This is the "parent_data_bind" event in our event_handler. This is called for every field inside a parent object with a data binding.
      */
      parent_data_bind = (using parse_context: *GON.ParseContext, field: *GON.GonField) -> GON.GonReturnCode {
        // Firstly, get the parent field
        parent : *GON.GonField = field.parent;

        // Next, check that the parent's data binding is to a struct (if so, it could be a LinkedList).
        // We don't need to check that the parent object or its data binding are non-null, 
        //   since both of those are preconditions for this event handler precedure being called.  
        if parent.data_binding.type.type == .STRUCT {

          // Get the type info for this struct so that we can check for more details.
          ti_struct := cast(*Type_Info_Struct) parent.data_binding.type;

          // Check that the polymorphic base type of our struct is a linked list.
          if ti_struct.polymorph_source_struct == type_info(LinkedList(void)).polymorph_source_struct {
            /*
              Create an Any for our data binding.
              We will use this to manually create a data binding for the elements of our linked list.
            */
            binding : Any = ---;
            
            /*
              Using our helper function from above, we get the value of the Type parameter to our linked list.
              The xx,no_check cast is used to cast a Type to a *Type_Info (which is the type of Any.type). 
              These are really the same thing under the hood, but the are considered distinct types and so require a cast.
            */
            binding.type = xx,no_check get_specified_parameter_value(ti_struct, "T", Type);

            // Cast our linked list to the void type polymorph used by our nonpoly procedures.
            list := cast(*LinkedList(void)) parent.data_binding.value_pointer;
            node : *LinkedListNode(void);

            /*
              Here we use our non-polymorphic procedure for adding a node to a linked list directly, 
                passing in the runtime size (in bytes) of the type we are binding to (in this case, float).
              If we only had the polymorphic implementation of our add and remove functions, this wouldn't be possible.
              Since we are calling add_last, nodes will simply be added sequentially.
              I'll leave it as an exercise for the reader to implement some logic to load numbers in some other order.
            */
            node = add_last_nonpoly(list, binding.type.runtime_size);

            /*
              Before binding the value of the node, ensure that the node we just added is valid.
              When we return ERROR from this callback, the parser will either quit parsing entirely or 
                skip over the field, depending on the user's error handling policy.
            */
            if !node return .ERROR;

            // Set the value pointer for our binding with the address of the node's value.
            binding.value_pointer = *node.value;

            // Use the internal GON parser function for setting a field binding.
            GON.set_field_data_binding(parse_context, field, *binding);

            // Lastly we need to return SKIP_BINDING to ensure that the usual code for setting indirect bindings is bypassed.
            return .SKIP_BINDING;
          }
        }

        // For a fields that are not linked lists, return SUCCESS so that usual code for setting indirect bindings will continue.
        return .SUCCESS;
      },
    },
  };

  success = GON.parse_file(*parse_context);

  print("list: ");
  print_list(*list);
}

/*
  Hopefully (despite the large comments bloating the code) you can see that there is a really quite a small amount 
    of code that one needs to write in order to integrate a custom data type like a linked list with the GON parser.
  However, it is quite essential that one has access to (and knowledge of) the particulars of the implementation of the data structure.
  Otherwise, it would be much more difficult to perform the the type-agnostic operations that we need to perform.
  I would encourage anyone to have this level of familiarity with their data structures because it enables you to do many more cool things!
  Fortunately Jai itself seems to encourage this quite well in distributing highly readable source for all of the major libraries 
    (which were an invaluable reference for me while building this parser).
*/
