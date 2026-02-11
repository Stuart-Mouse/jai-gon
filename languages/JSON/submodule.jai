
JSON_get_language :: (config := JSON_Config.{}) -> Language {
    ctx := New(JSON_Context);
    ctx.config = config;
    
    return .{
        name              = "JSON",
        id                = JSON_LANGUAGE_ID,
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
    using config: JSON_Config;
    
    lexer:  JSON_Lexer;
}

JSON_Config :: struct {
    using lexer_config: JSON_Lexer_Config;
    
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
    
    // TODO: maybe handle indentation differently, pass as parameter to serialize proc or something...
    indentation_string := "    ";
}

// TODO: I do not like that we are currently copying all this config into the lexer on init.
//       But at the moment, basically all the config is for the lexer, and I don't currently have a good way of making the config available to both the language context and the lexer itself other than to pass the entire context to lexer procs, or to have the lexer point to the context, which is dumb...
//       The best solution will probably just be to pass the whole context to the lexer procs, even though that's kind of gross.
//       Or maybe we can do something with context to make this nicer all around, because now I am also thinking about what if we want the scanner to have access to the language config and whatnot. But maybe that's a bridge too far anyhow... I dunno. I am tired.
JSON_Lexer_Config :: struct {
    skip_whitespace                 := default_skip_whitespace;
    try_lex_number                  := JSON_try_lex_number;
    try_lex_identifier              := default_try_lex_identifier;
    is_legal_identifier             := default_is_legal_identifier;
    permitted_quotation_characters  := "\"";
    whitespace_characters           := Scanner.DEFAULT_WHITESPACE_CHARACTERS;
}

#scope_module

JSON_LANGUAGE_ID :: "JSON";

JSON_parse :: (model: *Data_Model, file: string, file_path_for_logging := "", into: *Data_Model.Node = null) -> bool {
    using json_context := model.language.language_context.(*JSON_Context);
    
    init_lexer(*lexer, lexer_config, file, file_path_for_logging);
    
    ensure_root_node_exists(model);
    
    log_unexepected_token :: (token: JSON_Token) #expand {
        if token.kind == .ERROR {
            report_error(model, token.location, token.text);
        } else {
            report_error(model, token.location, "Unexpected % token: '%'.", token.kind, token.text);
        }
    }
    
    next_token: JSON_Token;
    
    root := ifx into else model.root;
    parent := root;
    while parse_loop := (parent != null) {
        name_token, value_token: JSON_Token;
        node_kind: Data_Model.Node.Kind;
        
        // check for end of object / array, or comma
        next_token = peek_token(*lexer);
        if next_token.kind == {
          case .EOF;
            if parent != root {
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
          case .NULL;
            node_kind = .FIELD;
            // Not setting value for now. Need to determine how to handle this properly.
            
          case .IDENTIFIER;
            if !(json_flags & .PERMIT_IDENTIFIERS_AS_VALUES) {
                log_unexepected_token(next_token);
                return false;
            }
            #through;
            
          case .TRUE;   #through;
          case .FALSE;  #through;
          case .NUMBER; #through;
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


#load "serialize.jai";
#load "lexer.jai";

