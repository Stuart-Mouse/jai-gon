/*
    JSON language submodule
    
    Once again, special thanks to Tyler Glaiel, the creator of GON. 
    This language submodule is really more tailored to GON than it is to JSON, 
    but the JSON stuff is still all the default for those who want to (or need to) use JSON.
*/

JSON_get_language :: () -> Language {
    ctx := New(JSON_Context);
    ctx.json_flags = JSON_Context.Flags.NONE;
    
    return .{
        name              = "JSON",
        language_context  = ctx,
        parse             = JSON_parse,
        serialize_node    = JSON_serialize_node,
        deinit            = JSON_deinit_language,
    };
}

JSON_deinit_language :: (model: *Data_Model) {
    ctx := model.language.language_context.(*JSON_Context);
    free(ctx);
}


JSON_Context :: struct {
    lexer:  JSON_Lexer;
    
    permitted_quotation_characters := "\"";
    
    json_flags: Flags;
    Flags :: enum_flags {
        NONE :: 0;
        
        PERMIT_TRAILING_COMMA_IN_OBJECT :: 1;
        PERMIT_IDENTIFIERS_AS_KEYS;
        PERMIT_IDENTIFIERS_AS_VALUES;
        PERMIT_NUMBERS_AS_KEYS;
        // PERMIT_MULTI_VALUED_FIELDS;
        
        DONT_REQUIRE_COMMAS;
        DONT_REQUIRE_COLONS;
        
        DEFAULT_GON_FLAGS :: PERMIT_TRAILING_COMMA_IN_OBJECT | PERMIT_IDENTIFIERS_AS_KEYS | PERMIT_IDENTIFIERS_AS_VALUES | PERMIT_NUMBERS_AS_KEYS | DONT_REQUIRE_COMMAS | DONT_REQUIRE_COLONS;
    }
};

#scope_module

JSON_parse :: (model: *Data_Model, file: string, file_path_for_logging := "") -> bool {
    using gon_context := model.language.language_context.(*JSON_Context);
    
    init_lexer(*lexer, file, file_path_for_logging);
    
    ensure_root_node_exists(model);
    
    log_unexepected_token :: (token: JSON_Token) {
        if token.kind == .ERROR {
            log("%:%,%: JSON lexer error: %.", token.location.fully_pathed_filename, token.location.line_number, token.location.character_number, token.text);
        } else {
            log("%:%,%: JSON parser error: Unexpected % token: '%'.", token.location.fully_pathed_filename, token.location.line_number, token.location.character_number, token.kind, token.text);
        }
    }
    
    next_token: JSON_Token;
    
    parent := model.root;
    while parse_loop := (parent != null) {
        name_token, value_token: JSON_Token;
        node_kind: Data_Model.Node.Kind;
        
        // check for end of object / array, or comma
        next_token = peek_token(*lexer);
        if next_token.kind == {
          case .EOF;
            if parent != model.root {
                log_unexepected_token(next_token);
                return false;
            }
            break parse_loop;
            
          case .OBJECT_END;
            get_token(*lexer);
            parent = parent.parent;
            continue;
            
          case .ARRAY_END;
            if parent.kind != .ARRAY {
                log_unexepected_token(next_token);
                return false;
            }
            get_token(*lexer);
            parent = parent.parent;
            continue;
            
          case .COMMA;
            get_token(*lexer);
            
          case;
            if parent.children.count != 0 && (!json_flags & .DONT_REQUIRE_COMMAS) {
                log_unexepected_token(next_token);
                return false;
            }
        }
        
        // read field name
        if parent.kind == .OBJECT {
            next_token = get_token(*lexer);
            if next_token.kind == {
              case .IDENTIFIER; 
                if !(json_flags & .PERMIT_IDENTIFIERS_AS_KEYS) {
                    log_unexepected_token(next_token);
                }
                
              case .NUMBER;
                if !(json_flags & .PERMIT_NUMBERS_AS_KEYS) {
                    log_unexepected_token(next_token);
                }
                
              case .STRING;
                // no op
                
              case;
                log_unexepected_token(next_token);
                return false;
            }
            
            // base case for .IDENTIFIER, .NUMBER, .STRING
            name_token = next_token;
            
            next_token = peek_token(*lexer);
            if next_token.kind == .COLON {
                get_token(*lexer);
            } else if (!json_flags & .DONT_REQUIRE_COLONS) {
                log_unexepected_token(next_token);
                return false;
            }
        }
        
        next_token = get_token(*lexer);
        if next_token.kind == .ERROR {
            log_unexepected_token(next_token);
            return false;
        }
        
        // read field value
        if next_token.kind == {
          case .IDENTIFIER;
            if !(json_flags & .PERMIT_IDENTIFIERS_AS_VALUES) {
                log_unexepected_token(next_token);
                return false;
            }
            #through;
            
          case .NUMBER;
            #through;
            
          case .STRING;
            node_kind = .FIELD;
            value_token = next_token;
            
          case .OBJECT_BEGIN;
            node_kind = .OBJECT;
            
          case .ARRAY_BEGIN;
            node_kind = .ARRAY;
            
          case;
            log_unexepected_token(next_token);
            return false;
        }
        
        assert(node_kind != .UNINITIALIZED);
        
        node := insert_child_node(model, parent, name_token.text, node_kind);
        node.location = ifx name_token.location.line_number then name_token.location else value_token.location;
        
        if node.kind == {
          case .OBJECT; #through;
          case .ARRAY;
            parent = node;
            
          case .FIELD;
            // next_token = peek_token(*lexer);
            // if json_flags & .PERMIT_MULTI_VALUED_FIELDS && next_token.kind == .VALUE_SEPARATOR {
            //     get_token(*lexer);
            //     parent = node;
                
            //     node = insert_child_node(model, parent, "", .FIELD);
            //     node.location = ifx name_token.location.line_number then name_token.location else value_token.location;
            // } else {
                node.string_value = value_token.text;
            // }
        }
    }
    
    return true;
}

#scope_module

#load "serialize.jai";
#load "lexer.jai";

