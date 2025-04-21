
// used to build a DOM from a text file and evaluate data bindings on that DOM
Parser :: struct {
    using #as script: Script;
    dom_root: *Node_Field;
};

init_parser :: (parser: *Parser, file: string, use_pool := false) {
    init_script(*parser.script);
    
    parser.script.my_parse_leaf   = gon_parse_leaf;
    parser.script.my_parse_binary = gon_parse_binary;
    
    parser.script.typecheck_callback = typechecking_callback;
    parser.script.evaluate_callback  = evaluation_callback;
    register_common_types(*parser.script);
    
    init_lexer(*parser.lexer, file);
}

deinit_parser :: (parser: *Parser) {
    free_script(*parser.script);
}

// creates a dom parser with the given parameters, intializes it, and constructs the dom from the given file
// after calling this, you can just add your data bindings and then process them
parse_file_to_dom :: (file: string) -> (Parser, bool) {
    parser: Parser;
    init_parser(*parser, file);
    if !construct_dom_from_gon_file(*parser)  return .{}, false;
    return parser, true;
}

add_data_binding_to_dom :: (parser: *Parser, binding: Any, path: string) -> bool {
    node := find_node_by_path(parser.dom_root, path);
    return add_data_binding_to_node(node, binding);
}

add_data_bindings_to_dom :: (parser: *Parser, bindings: [] struct { binding: Any; path: string; }) -> bool {
    for bindings
        if !add_data_binding_to_dom(parser, it.binding, it.path)  
            then return false;
    return true;
}

process_data_bindings :: (parser: *Parser) -> bool {
    return process_node_binding(parser, parser.dom_root);
}

process_node_binding :: (parser: *Parser, node: *Node_Field) -> resolved: bool {
    // We set BINDING_RESOLVED on exit in any case, since we only process each node once, 
    //      and it either succeeds or everything fails.
    if .BINDING_RESOLVED & node.field_flags  return true;
    defer node.field_flags |= .BINDING_RESOLVED; 
    
    if is_aggregate(node) {
        for get_fields(node)
            if !process_node_binding(parser, it)
                return false;
    } 
    else if node.binding.value_pointer != null {
        if !typecheck_node(parser, node) {
            log(format_error(parser.error));
            return false;
        }
        
        value, ok := evaluate_node(parser, node.value);
        if !ok {
            log("Error: failed to evaluate expression '%'!", sprint_node(parser, node.value,, temp));
            return false;
        }
        memcpy_any(node.binding, value);
    }
    
    return true;
}

/*
    Construction of the dom is done iteratively instead of recursively, since we can trivially track the current parent node and retrieve it's parent node when we would otherwise return.
    Although, if we ever remove the pointer to parent from DOM nodes, we may go ahead and just make this recursive.
    
    TODO: don't require comma after objects or arrays
          maybe we can just consume the comma in the lexer as an expression-ending delimiter and then 
          we can remove the need to even check for it here.
          Maybe we can even just make the comma be whitespace to GON again?
*/
construct_dom_from_gon_file :: (using parser: *Parser) -> bool {
    push_allocator(get_pool_allocator(*script.pool));
    
    dom_root       = alloc_node(*script, Node_Field);
    dom_root.value = alloc_node(*script, Node_Object);
    parent := dom_root;
    
    // temporary buffer to put child nodes in
    // will be copied into pool when we step out of object or array
    // children: [..] *Node_Field;
    // array_reset(*children);
    
    while parse_loop := (parent != null) {
        name_token: Token;
        
        next_token := peek_token(*lexer);
        if next_token.type == .EOF {
            if parent != dom_root {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            break parse_loop;
        }
        
        if next_token.type == {
          case .IDENTIFIER; #through;
          case .STRING;
            if !is_object(parent) {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            name_token = get_token(*lexer);
            
            next_token = get_token(*lexer);
            if next_token.type != .COLON {
                log("GON parse error: Expected colon after field name '%', got % \"%\" @ (%:%)", name_token.text, next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            
          case .CLOSE_BRACE;
            if !is_object(parent) {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            get_token(*lexer);
            expect_token_type(*lexer, .COMMA);
            // parent.value.(*Node_Object).fields = array_copy(children,, script.allocator);
            // array_reset_keeping_memory(*children);
            parent = parent.parent;
            // script.current_scope = parent;
            continue;
            
          case .CLOSE_BRACKET;
            if !is_array(parent) {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            get_token(*lexer);
            expect_token_type(*lexer, .COMMA);
            // parent.value.(*Node_Array).fields = array_copy(children,, script.allocator);
            // array_reset_keeping_memory(*children);
            parent = parent.parent;
            // script.current_scope = parent;
            continue;
        }
        
        node := alloc_node(*script, Node_Field);
        node.parent = parent;
        
        next_token = peek_token(*lexer);
        if next_token.type == {
          case .OPEN_BRACE;
            node.value = alloc_node(*script, Node_Object);
            node.location = get_token(*lexer).location;
            
          case .OPEN_BRACKET;
            node.value = alloc_node(*script, Node_Array);
            node.location = get_token(*lexer).location;
            
          case;
            node.value = my_parse_expression(*script, 0);
            if !node.value {
                log(format_error(script.error));
            }
            next_token := peek_token(*lexer);
            if next_token.type == {
              case .CLOSE_BRACE;
              case .CLOSE_BRACKET;
              case .EOF;
              case .COMMA; get_token(*lexer);
              case;
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
            }
        }
        
        if node.value == null {
            log("GON parse error: failed to parse expression.");
            log(format_error(script.error));
            return false;
        }
        
        if !is_array(parent) {
            node.name     = name_token.text;
            node.location = name_token.location;
            log("%: %\n", node.location, node.name);
            log(node.name);
        } else {
            node.location = node.value.location;
            log("%\n", node.location);
        }
        
        append_child_node(parent, node);
        // array_add(*children, node);
        if node.value.node_type == {
          case Node_Object; #through;
          case Node_Array;  
            parent = node;
            // script.current_scope = parent;
        }
    }
    
    return true;
}

add_data_binding_to_node :: (node: *Node_Field, binding: Any) -> bool  {
    if node == null || binding.value_pointer == null  return true;
    
    if node.binding.value_pointer != null {
        log("Error, node already has a data binding set...");
        return false;
    }
    
    node.binding = binding;
    name_member: *Type_Info_Struct_Member;
    name_member_any: Any;
    
    io_data := get_io_data(node.binding.type);
    if io_data {
        // because we may rebind the node, we need to assign the name_member_any
        // if this Any is still set after making bindings to child nodes, then we will assign to it
        if io_data.name_member {
            name_member = io_data.name_member;
            name_member_any = Any.{ name_member.type, node.binding.value_pointer + name_member.offset_in_bytes };
        }
        
        if io_data.parse.bind_proc {
            node.binding = io_data.parse.bind_proc(node.binding);
            if node.binding.value_pointer == null {
                log("Error, bind_proc() returned null.");
                return false;
            }
            // get new io data for new binding
            io_data = get_io_data(node.binding.type);
        }
    }
    
    defer if name_member {
        return remap_data(name_member_any, node.name);
    }
    
    // TODO: think about whether we want to reimplement this functionality
    // node.binding = deref_any_pointer(node.binding);
    
    // make indirect bindings onto child nodes
    if node.value.node_type == {
      case Node_Object;
        node_object := node.value.(*Node_Object);
        if node.binding.type.type == {
          case .STRUCT;
            for node_object.fields {
                member := get_field(xx node.binding.type, it.name);
                if !member || (member.flags & .CONSTANT)  continue;
                
                // we don't want to set it if the name member has a binding to a child node
                if member == name_member then name_member = null;
                
                member_any := Any.{
                    value_pointer = node.binding.value_pointer + member.offset_in_bytes,
                    type          = member.type,
                };
                add_data_binding_to_node(it, member_any);
            }
            
            // we don't want to set the name member if the parent exists and is an indexed array, because then the gon name is being used for the index
            if node.parent && (node.parent.field_flags & .ARRAY_INDEXED) then name_member = null;
            
            
          case .ARRAY;
            ti_array := node.binding.type.(*Type_Info_Array);
            
            io_data := get_io_data(ti_array);
            if io_data && (.ARRAY_INDEXED & io_data.parse.flags)
                then node.field_flags |= .ARRAY_INDEXED;
                
            // TODO: I have no idea what the below logic was originally intended to do...
            // else if ti_array.element_type.type == .STRUCT 
            //     then node.flags |= .ARRAY_AS_OBJECT;
            
            if ti_array.array_type == .RESIZABLE {
                raw_array := node.binding.value_pointer.(*Resizable_Array);

                if .ARRAY_INDEXED & node.field_flags {
                    for node_object.fields {
                        elem_index := -1;
                        if io_data.enum_index_type 
                            then elem_index = enum_name_to_value(xx io_data.enum_index_type, it.name);
                            else elem_index = to_integer(it.name);
                        elem_any   := array_add_any_at_index(node.binding, elem_index);
                        add_data_binding_to_node(it, elem_any);
                    }
                } else {
                    count_before := raw_array.count;
                    array_reserve_nonpoly(xx raw_array, count_before + node_object.fields.count, ti_array.element_type.runtime_size);
                    raw_array.count += node_object.fields.count;
                    for node_object.fields {
                        elem_any := Any.{
                            value_pointer = raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size), 
                            type          = ti_array.element_type
                        };
                        add_data_binding_to_node(it, elem_any);
                    }
                }
            } else { // .FIXED and .VIEW
                io_data := get_io_data(node.binding.type);

                elem_count, data := get_array_count_and_data(node.binding.value_pointer, ti_array);
                
                if .ARRAY_INDEXED & node.field_flags {
                    for node_object.fields {
                        elem_index := -1;
                        if io_data.enum_index_type 
                            then elem_index = enum_name_to_value(xx io_data.enum_index_type, it.name);
                            else elem_index = to_integer(it.name);
                        
                        if elem_index < 0 || elem_index >= elem_count {
                            log("Error: array index is out of bounds.");
                            return false;
                        }
                        
                        elem_any := Any.{ ti_array.element_type, data + (ti_array.element_type.runtime_size * elem_index) };
                        add_data_binding_to_node(it, elem_any);
                    }
                } else {
                    if node_object.fields.count > elem_count {
                        log("Error: too many elements in array.");
                        return false;
                    }
                    
                    if ti_array.element_type.type == .STRUCT {
                        node.field_flags |= .ARRAY_AS_OBJECT;
                        // TODO: also check the io data to see if name member is defined
                    } else {
                        log("Data binding error: object-type array must contain a struct with a defined name member.");
                        return false;
                    }
                    
                    for node_object.fields {
                        elem_any := Any.{ ti_array.element_type, data + (ti_array.element_type.runtime_size * it_index) };
                        add_data_binding_to_node(it, elem_any);
                    }
                }
            }
            
            /* 
                TODO: 
                GON objects can only validly be bound to arrays when the element type is a struct,
                or if it is an indexed array (where the name of each field is the index to which the value will be stored).
                So, we should perform a check to ensure that these conditions are met, else return an error.
                The user will have to state explicitly that they want to parse a given array binding as an indexed array, otherwise there is some ambiguity as to how to handle ths situation.
            */
            
          case;
            log("Invalid data binding, mismatched gon(OBJECT)/internal(%) type on node %.", (cast(*Type)*node.binding.type).*, format_node_path(node,, temp));
            return false;
        }
        
        
      case Node_Array;
        node_array := node.value.(*Node_Array);
        if node.binding.type.type == {
          case .STRUCT;
            ti_struct := node.binding.type.(*Type_Info_Struct);

            if node_array.fields.count > ti_struct.members.count {
                log("Data binding error: array-type struct contains too many elements.");
                return false;
            }
            for node_array.fields {
                // TODO: check for overlapping and constant struct members
                member := ti_struct.members[it_index];
                member_any := Any.{
                    value_pointer = node.binding.value_pointer + member.offset_in_bytes,
                    type          = member.type,
                };
                add_data_binding_to_node(it, member_any);
            }
                
          case .ARRAY;
            ti_array := node.binding.type.(*Type_Info_Array);
            
            data:  *void;
            count: int;
            count_before: int; // for dynamic array case, where we want to leave the existing items untouched
            
            if ti_array.array_type == {
              case .RESIZABLE;
                raw_array := node.binding.value_pointer.(*Resizable_Array);
                /*
                    IMPORTANT NOTE: 
                    
                    It is critical that the proper amount of space is pre-allocated for the dynamic array 
                    and that we don't have to realloc when we make data bindings for elements below.
                    Because if we realloc then that invalidates the pointers in the data bindings that we created
                    for all previous elements, since those are now pointing to the old locations of each element.
                    This may prove to be more fragile aspects of the DOM parser in contrast to the SAX implementation.
                    Because this definitely seems like something that a user could break through a problematic callback procedure.
                    
                    We could potentially fix this by changing how we store data bindings.
                    For array elements, instead of storing a pointer to data, store a pointer to a the base pointer and also element offset.
                    We could have a node flag to indicate that we should use this scheme instead of the usual one.
                    We won't do this unless we need to though. For now, the current method is fine.
                */
                count_before = raw_array.count;
                array_reserve_nonpoly(xx raw_array, count_before + node_array.fields.count, ti_array.element_type.runtime_size);
                raw_array.count += node_array.fields.count;
                
                data  = raw_array.data;
                count = raw_array.count;
                
              case .VIEW;
                raw_array := node.binding.value_pointer.(*Array_View_64);
                
                // count_before = raw_array.count;
                // raw_array.count += node_array.fields.count;
                // raw_array.data   = realloc(raw_array.data, ti_array.element_type.runtime_size * raw_array.count, ti_array.element_type.runtime_size * count_before);
                
                raw_array.count = node_array.fields.count;
                raw_array.data  = alloc(ti_array.element_type.runtime_size * raw_array.count);
                
                data  = raw_array.data;
                count = raw_array.count;
                
              case .FIXED;
                data  = node.binding.value_pointer;
                count = ti_array.array_count;
                if node_array.fields.count > count {
                    log("Data binding error: bounds check failed on fixed-size array.");
                    return false;
                }
            }
            
            for node_array.fields {
                elem_any := Any.{
                    value_pointer = data + (ti_array.element_type.runtime_size * it_index),
                    type          = ti_array.element_type,
                };
                add_data_binding_to_node(it, elem_any);
            }
            
          case;
            log("Data binding error: mismatched gon(ARRAY)/internal(%) type on node %.", (*node.binding.type).(*Type).*, node.*);
            return false;
        }
    }
    
    return true;
}

evaluation_callback :: (
    script:         *Script, 
    node:           *Node,
    hint_storage:   *void    = null,
    explicit_call := false
) -> Any, bool {
    if node.node_type == {
      case Node_Reference;
        reference := node.(*Node_Reference).*;
        if reference.reference_type == {
          case .VALUE; 
            if !process_node_binding(xx script, reference.resolved_field) return Any.{}, false;
            return reference.resolved_field.binding, true;
            
          case .INDEX; 
            return to_any(*reference.resolved_field_index), true;
        }
    }
    return Any.{}, true;
}

typechecking_callback :: (
    using script:   *Script, // in theroy we could also cast this to our Parser...
    node:           *Node, 
    check_flags:    Typechecking_Flags = .NONE,
    hint_type:      *Type_Info         = null
) -> (
    value_type:     *Type_Info
) {
    if node.node_type == {
      case Node_Field;
        field := node.(*Node_Field);
        if field.binding.type == null  return null;
        
        defer_restore(*current_scope);
        current_scope = field;
        
        // We set the PENDING_DEPENDENCY flag on this node only for the duration of this call
        //      so that we know if we visit it again, we have gone in a loop.
        // TODO: would be better if we explicitly track the dependency chain so that we can print a better error here
        if field.field_flags & .PENDING_DEPENDENCY {
            set_general_error(script, "Cyclic dependency on node '%'.", format_node_path(field,, temp));
            return null;
        }
        field.field_flags |= .PENDING_DEPENDENCY;
        defer field.field_flags &= ~.PENDING_DEPENDENCY;
        
        value_type := typecheck_node(script, field.value, hint_type = field.binding.type);
        if field.binding.type != value_type {
            set_general_error(script, "Mismatched types on field binding and value expression.", /*as_type(field.binding.type), as_type(value_type),*/);
            return null;
        }
        field.value_type = field.binding.type;
        print("field.binding.type: %\n", field.binding.type);
        return field.value_type;
        
        
      case Node_Object;
        object := node.(*Node_Object);
        if hint_type == null {
            set_typecheck_error(script, "Missing type hint on Node_Object.", node = node, type = .MISSING_TYPE_HINT);
            return null;
        }
        object.value_type = hint_type;
        for object.fields {
            if !typecheck_node(script, it)  return null;
        }
        return object.value_type;
        
        
      case Node_Array;
        array := node.(*Node_Array);
        if hint_type == null {
            set_typecheck_error(script, "Missing type hint on Node_Array.", node = node, type = .MISSING_TYPE_HINT);
            return null;
        }
        array.value_type = hint_type;
        for array.fields {
            if !typecheck_node(script, it)  return null;
        }
        return array.value_type;
        
        
      case Node_Reference;
        reference := node.(*Node_Reference);
        field := script.current_scope.(*Node_Field);
        
        resolved_field, resolved_index := find_node_by_path(xx script, field.parent, reference.field_path);
        if resolved_field == null {
            set_typecheck_error(script, "Unable to resolve referenced node path '%'.", reference.field_path, node = node);
            return null; 
        }
        reference.resolved_field = resolved_field;
        reference.resolved_field_index = Small_Any.from(resolved_index);
        
        if reference.resolved_field.binding.value_pointer == null {
            // TODO: handle this case by creating temporary instance of hinted type?
            set_general_error(script, "Referenced node '%' had no data binding!.", reference.field_path, loc = reference.location);
            return null;
        }
        
        // jump to referenced node
        if !typecheck_node(script, reference.resolved_field) return null;
        
        if reference.reference_type == {
          case .VALUE; reference.value_type = reference.resolved_field.binding.type;
          case .INDEX; 
            reference.value_type = type_info(int);
            if hint_type {
                reference.value_type = hint_type;
                reference.resolved_field_index = coerce_small_any(hint_type, reference.resolved_field_index);
            }
        }
        print("reference.value_type: %\n", reference.value_type);
        return reference.value_type;
        
      case;
        // set no error and let normal typechecking handle all other node types
        return null;
    }
}


make_reference :: (script: *Script, type: Reference_Type, path: string) -> *Node_Reference {
    ref := alloc_node(script, Node_Reference);
    ref.reference_type = type;
    ref.field_path     = path;
    return ref;
}

// Custom versions of parse_leaf and parse_binary are implemented here to remove some of the LS features which we do not want to use in GON.

gon_parse_leaf :: (using script: *Script) -> *Node {
    token := get_token_or_return(*lexer, null);
    
    is_operator, operator_type, precedence := token_is_operator(token, expect_unary = true);
    if is_operator && operator_type == .UNARY {
        // special cases, bit of a parsing hack for the field reference operators
        // maybe later we will add the ability to have comptime operators more generally
        if token.text == {
          case "$";
            string_token := get_token(*lexer);
            if string_token.type != .STRING {
                set_parse_error(script, "%: expected a path string after node reference operator.", string_token.location);
                return null;
            }
            return make_reference(script, .VALUE, string_token.text);
            
          case "&";
            string_token := get_token(*lexer);
            if string_token.type != .STRING {
                set_parse_error(script, "%: expected a path string after node reference operator.", string_token.location);
                return null;
            }
            return make_reference(script, .INDEX, string_token.text);
        }
        
        left := my_parse_expression(script, precedence);
        if left == null  return null;
        return make_unary_operation(script, token, left);
    }
    
    if token.type == {
      case .DOT;
        token_after_dot := get_token(*lexer);
        if token_after_dot.type == .IDENTIFIER {
            identifier := make_identifier(script, token_after_dot);
            return make_dot(script, token, null, identifier);
        }
        else set_parse_error(script, "%: unexpected % token '%' after unary dot.", token_after_dot.location, token_after_dot.type, token_after_dot.text);

        
      case .OPEN_PAREN;
        open_paren_location := token.location;
        
        expression := my_parse_expression(script, 0);
        if expression == null  return null;
        expression.flags |= .PARENTHESIZED;
        
        close_paren_token := get_token(*lexer);
        if close_paren_token.type != .CLOSE_PAREN {
            set_parse_error(script, "%: expected a closing paren for open paren at %.", close_paren_token.location, open_paren_location);
            return null;
        }
        return expression;
        
        
      case .NUMBER;
        return make_number_literal(script, token);
        
        
      case .STRING;
        return make_string_literal(script, token);
        
    
      case .DIRECTIVE;
        directive := alloc_node(script, Node_Directive, loc = token.location, trivia = token.trivia);
        directive.name = token.text;
        
        directive.directive_index = -1;
        for script.directives {
            if it.name == directive.name {
                directive.directive_index = it_index;
            }
        }
        if directive.directive_index == -1 {
            set_parse_error(script, "%: Unable to resolve directive '%'\n", directive.location, directive.name);
            return null;
        }
        
        open_paren_token := get_token(*lexer);
        if open_paren_token.type != .OPEN_PAREN {
            set_parse_error(script, "%: Error, expected an open paren after directive name!\n", open_paren_token.location);
            return null;
        }
        
        if !expect_token_type(*lexer, .CLOSE_PAREN) {
            expressions, ok := parse_comma_separated_expressions(script,, temp);
            if !ok  return null;
            directive.arguments = array_copy(expressions,, get_pool_allocator(*script.pool));
            
            close_paren_token := get_token(*lexer);
            if close_paren_token.type != .CLOSE_PAREN {
                set_parse_error(script, "%: expected a closing paren after arguments of directive. Instead we saw %\n", close_paren_token.location, close_paren_token.text);
                return null;
            }
        }
        
        if !evaluate_directive(script, directive, .PARSE) {
            set_parse_error(script, "%: failed while trying to execute a directive during parsing.", token.location);
            return null;
        }
        return directive;
        
        
      case .IDENTIFIER;
        return make_identifier(script, token);
    }
    
    return null;
}

// If we hit a binary operator but its precedence is too low, we return left back to caller.
gon_parse_binary :: (using script: *Script, left: *Node, min_prec: int) -> *Node {
    token := peek_token(*lexer);
    
    // should this go here or up in main loop of parse_expression?
    // will require some refactoring to hoist up there
    if token.type == {
      case .OPEN_PAREN;
        get_token(*lexer);
        
        arg_exprs, ok := parse_procedure_arguments(script);
        return make_procedure_call(script, token, left, arg_exprs);
        
        
      case .DOT;
        dot_token := get_token(*lexer);
        
        token_after_dot := get_token(*lexer);
        if token_after_dot.type == {
          case .OPEN_PAREN;
            type_expr := my_parse_expression(script, 0);
            close_paren := get_token(*lexer);
            if close_paren.type != .CLOSE_PAREN {
                set_parse_error(script, "%: unexpected token '%' in cast type expression. Expected a closing paren.", close_paren.location, close_paren.type);
                return null;
            }
            return make_cast(script, dot_token, left, type_expr);
            
          case .IDENTIFIER;
            identifier := make_identifier(script, token_after_dot);
            return make_dot(script, dot_token, left, identifier);
        }
        
        set_parse_error(script, "%: unexpected % token '%' after dot.", token.location, token.type, token.text);
        return null;
        
        
      case .OPEN_BRACKET;
        open_bracket_token := get_token(*lexer);
        
        indexing_expr := my_parse_expression(script, 0);
        if indexing_expr == null  return null;
        if !expect_token_type(*lexer, .CLOSE_BRACKET)  return null;
        
        return make_subscript(script, open_bracket_token, left, indexing_expr);
    }
    
    is_operator, operator_type, precedence := token_is_operator(token);
    if is_operator && operator_type != .UNARY {
        if precedence <= min_prec  return left;
        operator_token := get_token(*lexer);
        
        right := my_parse_expression(script, precedence);
        if right == null  return null;
        
        operation := make_operation(script, operator_token, operator_type, left, right);
        if operator_type == .ASSIGNMENT then operation.flags |= .MUST_BE_STATEMENT_ROOT;
        
        return operation;
    }
    
    return left;
}
