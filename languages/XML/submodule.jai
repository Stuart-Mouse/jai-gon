/*
    NOTE: This is not a conformat XML implementation by any means, this is just being done as a proof-of-concept for the time being so that the overall structure of the module can be developed.
    
    
*/


XML_get_language :: (config := XML_Config.{}) -> Language {
    ctx := New(XML_Context);
    ctx.config = config;
    
    return .{
        name              = "XML",
        id                = XML_LANGUAGE_ID,
        language_context  = ctx,
        parse             = XML_parse,
        serialize_node    = XML_serialize_node,
        deinit            = XML_deinit_language,
    };
}

XML_deinit_language :: (model: *Data_Model) {
    ctx := model.language.language_context.(*XML_Context);
    free(ctx);
}

XML_Context :: struct {
    using config: XML_Config;
    
    lexer:  XML_Lexer;
}

XML_Config :: struct {
    xml_flags: Flags;
    Flags :: enum_flags {
        NONE :: 0;
    }
    
    // TODO: maybe handle indentation differently, pass as parameter to serialize proc or something...
    indentation_string := "    ";
}

#scope_module

XML_LANGUAGE_ID :: "XML";

XML_parse :: (model: *Data_Model, file: string, file_path_for_logging := "", into: *Data_Model.Node = null) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    init_lexer(*lexer, lexer_config, file, file_path_for_logging);
    
    while main_loop := true {
        
        next_token := peek_token(*lexer);
        if next_token.kind == .TAG_BEGIN {
            get_token(*lexer);
            
            next_token = get_token(*lexer);
            if next_token.kind != .NAME {
                log("expected a name");
                return false;
            }
            if next_token.preceding_whitespace {
                log("cannot have whitespace between < and tag name");
                return false;
            }
            
            while true {
                ok, parsed := try_parse_attribute(model);
                if !ok      return false;
                if !parsed  break;
            }
            
            next_token = get_token(*lexer);
            if next_token.kind == .CLOSING_TAG_END {
                // This is a self-closing tag.
                continue main_loop;
            }
            
            if next_token.kind != .TAG_END {
                log("expected `>` or `/>` to close tag");
                return false;
            }
            
            // parse content of tag
            
            /*
                we can alternate between parsing string data and child tags
                this poses a problem for adapting directly to our data model, because our data model really expects for the 'value' of a node to be a single string,
                    not another array of heterogenous data (strings and/or other tags)
                perhaps what we can do is just to say that the 'value' of an xml element is the substring of the entire tag contents taken as a whole
                then in the child nodes, we can specially flag those child nodes which are pure character data as being such
                tags will be flagged to indicate whether they contain character data, subtags, or both.
                for the purposes of use in data files, I wager that most people will want to restrict the parser to permit only one or the other kind of data within a givne tag
            */ 
            
        }
    }
    
    return true;
}

/*

try_parse_tag
    <name (attributes)*> content </name>

try_parse_attribute
    name = "value"

*/
