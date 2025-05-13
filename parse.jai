
// used to build a DOM from a text file and evaluate data bindings on that DOM
Parser :: struct {
    using #as script: Script;
    
    // #place script.ast_root;
    dom_root: *Node_Field;
    
    #place current_scope;
        current_parent: *Node_Field;
};

init_parser :: (parser: *Parser, file: string, file_path := "") {
    init_script(*parser.script);
    
    parser.script.my_parse_leaf   = gon_parse_leaf;
    parser.script.my_parse_binary = gon_parse_binary;
    
    parser.script.typecheck_callback = typechecking_callback;
    parser.script.evaluate_callback  = evaluation_callback;
    register_common_types(*parser.script);
    
    init_lexer(*parser.lexer, file, location = .{ file_path, 1, 1 });
}

deinit_parser :: (parser: *Parser) {
    free_script(*parser.script);
}

// creates a dom parser with the given parameters, intializes it, and constructs the dom from the given file
// after calling this, you can just add your data bindings and then process them
parse_file_to_dom :: (file: string, filepath := "") -> (Parser, bool) {
    parser: Parser;
    init_parser(*parser, file, filepath);
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
    fields := get_fields(parser.dom_root);
    for fields {
        if !typecheck_node(parser, it)  return false;
    }
    for fields {
        evaluate_node(parser, it);
        if !!parser.error  return false;
    }
    return true;
}

/*
    Construction of the dom is done iteratively instead of recursively, since we can trivially track the current parent node and retrieve it's parent node when we would otherwise return.
    Although, if we ever remove the pointer to parent from DOM nodes, we may go ahead and just make this recursive.
*/
construct_dom_from_gon_file :: (using parser: *Parser) -> bool {
    push_allocator(get_pool_allocator(*script.pool));
    
    current_parent = null;
    dom_root       = alloc_node(*script, Node_Field);
    current_parent = dom_root;
    dom_root.value = alloc_node(*script, Node_Object);
    current_parent = dom_root;
    
    while parse_loop := (current_parent != null) {
        name_token: Token;
        
        next_token := peek_token(*lexer);
        if next_token.type == .EOF {
            if current_parent != dom_root {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            break parse_loop;
        }
        
        if next_token.type == {
          case .IDENTIFIER; #through;
          case .STRING;
            if is_object(current_parent) {
                name_token = get_token(*lexer);
                next_token = get_token(*lexer);
                if next_token.type != .COLON {
                    log("GON parse error: Expected colon after field name '%', got % \"%\" @ (%:%)", name_token.text, next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                    return false;
                }
            }
            
          case .CLOSE_BRACE;
            if !is_object(current_parent) {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            get_token(*lexer);
            expect_token_type(*lexer, .COMMA);
            current_parent = current_parent.parent;
            continue;
            
          case .CLOSE_BRACKET;
            if !is_array(current_parent) {
                log("GON parse error: Unexpected % token \"%\" at (%:%).", next_token.type, next_token.text, next_token.location.line_number, next_token.location.character_number);
                return false;
            }
            get_token(*lexer);
            expect_token_type(*lexer, .COMMA);
            current_parent = current_parent.parent;
            continue;
        }
        
        // need a better check, will be trivial after refactoring parsing later...
        if is_object(current_parent) && !name_token.type {
            set_parse_error(parser, "Expected a field name, but saw this instead: %", next_token.text);
            return false;
        }
        
        node := alloc_node(*script, Node_Field);
        node.parent = current_parent;
        
        next_token = peek_token(*lexer);
        if next_token.type == {
          case .OPEN_BRACE;
            node.value = alloc_node(*script, Node_Object);
            node.value.(*Node_Object).parent = node;
            node.location = get_token(*lexer).location;
            
          case .OPEN_BRACKET;
            node.value = alloc_node(*script, Node_Array);
            node.value.(*Node_Object).parent = node;
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
        
        if !is_array(current_parent) {
            node.name     = name_token.text;
            node.location = name_token.location;
        } else {
            node.location = node.value.location;
        }
        
        append_child_node(current_parent, node);
        if node.value.node_type == {
          case Node_Object; #through;
          case Node_Array;  
            current_parent = node;
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
                        elem_any := array_add_any_at_index(node.binding, elem_index);
                        add_data_binding_to_node(it, elem_any);
                    }
                } else {
                    count_before := raw_array.count;
                    array_reserve_nonpoly(xx raw_array, count_before + node_object.fields.count, ti_array.element_type.runtime_size);
                    raw_array.count += node_object.fields.count;
                    for node_object.fields {
                        elem_any := Any.{ ti_array.element_type, raw_array.data + ((count_before + it_index) * ti_array.element_type.runtime_size) };
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

// NOTE: Since fields all store their own bindings, we have no need to use the standard hint_storage mechanism for fields and objects.
evaluation_callback :: (
    script:         *Script, 
    node:           *Node,
    hint_storage:   *void    = null,
    explicit_call := false
) -> Any {
    if node.node_type == {
      case Node_Reference;
        reference := node.(*Node_Reference).*;
        
        result: Any;
        if reference.reference_type == {
          case .VALUE; 
            evaluate_node(xx script, reference.resolved_field);
            if !!script.error  return Null_Any;
            result = reference.resolved_field.binding;
            
          case .INDEX; 
            result = to_any(*reference.resolved_field_index);
        }
        if hint_storage != null {
            memcpy(hint_storage, result.value_pointer, result.type.runtime_size);
        }
        return result;
        
        
      case Node_Field;
        assert(hint_storage == null);
        field := node.(*Node_Field);
        
        if field.field_flags & .EVALUATED  return field.binding;
        defer field.field_flags |= .EVALUATED;
        
        if field.binding.type == null {
            log("binding was null for node at %!", node.location);
            return Void_Any;
        }
        
        evaluate_node(script, field.value, field.binding.value_pointer);
        if !!script.error  return Null_Any;
        if field.binding.type.type == .STRING {
            field.binding.value_pointer.(*string).* = copy_string(field.binding.value_pointer.(*string).*);
        }
        return Void_Any;
        
        
      case Node_Array; #through;
      case Node_Object;
        assert(node.scope.node_type == Node_Field, "%, %", node.scope.node_type, node.scope == script.ast_root);
        object := node.(*Node_Object);
        for object.fields {
            evaluate_node(script, it);
            if !!script.error  return Null_Any;
        }
        return object.parent.binding;
    }
    
    return Null_Any;
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
        
        if field.binding.type == null {
            field.value_type = type_info(void);
            return field.value_type;
        }
        
        // We set the PENDING_DEPENDENCY flag on this node only for the duration of this call
        //      so that we know if we visit it again, we have gone in a loop.
        // TODO: would be better if we explicitly track the dependency chain so that we can print a better error here
        if field.field_flags & .PENDING_TYPECHECK {
            set_general_error(script, "Cyclic dependency on node '%'.", format_node_path(field,, temp), loc = node.location);
            return null;
        }
        field.field_flags |= .PENDING_TYPECHECK;
        defer field.field_flags &= ~.PENDING_TYPECHECK;
        
        defer_restore(*current_scope);
        current_scope = field;
        
        value_type := typecheck_node(script, field.value, hint_type = field.binding.type);
        if !value_type  return null;
        if field.binding.type != value_type {
            set_general_error(script, "Mismatched types on field binding and value expression." /*as_type(field.binding.type), as_type(value_type),*/, loc = node.location);
            return null;
        }
        
        field.value_type = field.binding.type;
        return field.value_type;
        
        
      case Node_Object;
        object := node.(*Node_Object);
        if hint_type == null {
            set_typecheck_error(script, "Missing type hint on Node_Object.", node = node, type = .MISSING_TYPE_HINT, loc = node.location);
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
            set_typecheck_error(script, "Missing type hint on Node_Array.", node = node, type = .MISSING_TYPE_HINT, loc = node.location);
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
            set_typecheck_error(script, "Unable to resolve referenced node path '%'.", reference.field_path, node = node, loc = node.location);
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
        if !typecheck_node(script, reference.resolved_field)  return null;
        
        if reference.reference_type == {
          case .VALUE; reference.value_type = reference.resolved_field.binding.type;
          case .INDEX; 
            reference.value_type = type_info(int);
            if hint_type {
                reference.value_type = hint_type;
                reference.resolved_field_index = coerce_small_any(hint_type, reference.resolved_field_index);
            }
        }
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
    token := get_token(*lexer);
    
    is_operator, operator_type, precedence := token_is_operator(token, expect_unary = true);
    if is_operator && operator_type == .UNARY {
        // special cases, bit of a parsing hack for the field reference operators
        // maybe later we will add the ability to have comptime operators more generally
        if token.text == {
          case "$";
            string_token := get_token(*lexer);
            if string_token.type != .STRING {
                set_parse_error(script, "Expected a path string after node reference operator.", loc = string_token.location);
                return null;
            }
            return make_reference(script, .VALUE, string_token.text);
            
          case "&";
            string_token := get_token(*lexer);
            if string_token.type != .STRING {
                set_parse_error(script, "Expected a path string after node reference operator.", loc = string_token.location);
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
        else set_parse_error(script, "Unexpected % token '%' after unary dot.", token_after_dot.type, token_after_dot.text, loc = token_after_dot.location);

        
      case .OPEN_PAREN;
        open_paren_location := token.location;
        
        expression := my_parse_expression(script, 0);
        if expression == null  return null;
        expression.flags |= .PARENTHESIZED;
        
        close_paren_token := get_token(*lexer);
        if close_paren_token.type != .CLOSE_PAREN {
            set_parse_error(script, "Expected a closing paren for open paren at %.", open_paren_location, loc = close_paren_token.location);
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
            set_parse_error(script, "Unable to resolve directive '%'\n", directive.name, loc = directive.location);
            return null;
        }
        
        open_paren_token := get_token(*lexer);
        if open_paren_token.type != .OPEN_PAREN {
            set_parse_error(script, "Expected an open paren after directive name!\n", loc = open_paren_token.location);
            return null;
        }
        
        if !expect_token_type(*lexer, .CLOSE_PAREN) {
            expressions, ok := parse_comma_separated_expressions(script,, temp);
            if !ok  return null;
            directive.arguments = array_copy(expressions,, get_pool_allocator(*script.pool));
            
            close_paren_token := get_token(*lexer);
            if close_paren_token.type != .CLOSE_PAREN {
                set_parse_error(script, "Expected a closing paren after arguments of directive. Instead we saw %\n", close_paren_token.text, loc = close_paren_token.location);
                return null;
            }
        }
        
        if !evaluate_directive(script, directive, .PARSE) {
            set_parse_error(script, "Failed while trying to execute a directive during parsing.", loc = token.location);
            return null;
        }
        return directive;
        
        
      case .IDENTIFIER;
        return make_identifier(script, token);
    }
    
    return null;
}

gon_parse_binary :: (using script: *Script, left: *Node, min_prec: int) -> *Node {
    token := peek_token(*lexer);
    
    // In addition to normal binary operators, we have a few binary-operator-like constructs that have essentially infinite operator precedence.
    // These are open parenthesis for procedure calls, dot for struct member access and cast, and open bracket for array indexing.
    if token.type == {
      case .OPEN_PAREN;
        get_token(*lexer);
        arg_exprs, ok := parse_procedure_arguments(script);
        if !ok  return null;
        return make_procedure_call(script, token, left, arg_exprs);
        
        
      case .DOT;
        dot_token := get_token(*lexer);
        
        token_after_dot := get_token(*lexer);
        if token_after_dot.type == {
          case .OPEN_PAREN;
            type_expr := my_parse_expression(script, 0);
            close_paren := get_token(*lexer);
            if close_paren.type != .CLOSE_PAREN {
                set_parse_error(script, "Unexpected token '%' in cast type expression. Expected a closing paren.", close_paren.type, loc = close_paren.location);
                return null;
            }
            return make_cast(script, dot_token, left, type_expr);
            
          case .IDENTIFIER;
            identifier := make_identifier(script, token_after_dot);
            return make_dot(script, dot_token, left, identifier);
        }
        
        set_parse_error(script, "Unexpected % token '%' after dot.", token.type, token.text, loc = token.location);
        return null;
        
        
      case .OPEN_BRACKET;
        open_bracket_token := get_token(*lexer);
        
        indexing_expr := my_parse_expression(script, 0);
        if indexing_expr == null  return null;
        if !expect_token_type(*lexer, .CLOSE_BRACKET)  return null;
        
        return make_subscript(script, open_bracket_token, left, indexing_expr);
    }
    
    // We only consume the binary operator here if it is of a higher precedence than the previous binary operator.
    // If we hit a binary operator but its precedence is too low, we return left back to caller.
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
