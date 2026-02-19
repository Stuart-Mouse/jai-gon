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
        default_node_insertion_behaviour = Data_Model.Node.RETURN_EXISTING;
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
    
    while {
        // TODO: should probably not parse other top-level structures if 'into' is non-null.
        
        if try_parse_tag(model, into) {
            
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

try_parse_tag :: (model: *Data_Model, parent_tag: *Data_Model.Node) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    if next_token.kind == .TAG_BEGIN {
        get_token(*lexer);
        
        ok, name := xml_try_parse_name(*lexer);
        if !ok || !name {
            log("expected a name");
            return false;
        }
        
        tag_node: *Data_Model
        if parent_tag == null {
            // Then this must be the root node. If we already have a root node on the data model then someone messed up!
            if model.root != null {
                log("cannot have multiple top-level tags in xml!");
                return false;
            }
            ensure_root_node_exists(model);
            tag_node = model.root;
        } else
            tag_node, is_duplicate = maybe_insert_child_node(model, ifx parent_tag else model.root, name);
            if is_duplicate {
                log("duplicate tags are not allowed!");
                return false;
            }
        }
        tag_node.location = location;
        
        while true {
            ok, parsed := xml_try_parse_attribute(model);
            if !ok      return false;
            if !parsed  break;
        }
        
        next_token = get_token(*lexer);
        if next_token.kind == .CLOSING_TAG_END {
            // This is a self-closing tag.
            return true;
        }
        
        if next_token.kind != .TAG_END {
            log("expected `>` or `/>` to close tag");
            return false;
        }
        
        /*
            we can alternate between parsing string data and child tags
            this poses a problem for adapting directly to our data model, because our data model really expects for the 'value' of a node to be a single string,
                not another array of heterogenous data (strings and/or other tags)
            perhaps what we can do is just to say that the 'value' of an xml element is the substring of the entire tag contents taken as a whole
            then in the child nodes, we can specially flag those child nodes which are pure character data as being such
            tags will be flagged to indicate whether they contain character data, subtags, or both.
            for the purposes of use in data files, I wager that most people will want to restrict the parser to permit only one or the other kind of data within a givne tag
        */ 
        
        character_data_location  := lexer.location;
        character_data_substring := string.{ 0, lexer.file.data };
        while true {
            // try to parse character data segments, if we encounter a tag, then recurse
            
            codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
            if result != .CONVERSION_OK  return false, "utf8 decode error while parsing XML document";
            
            if is_valid_character(codepoint) {
                if character_data_substring.count == 0 {
                    character_data_location
                } else {
                    character_data_substring.count += 1;
                }
                advance(file);
                continue;
            }
            
            if codepoint == "&" {
                // parse character and entity references
                log("TODO: parse character and entity references");
                return false;
            }
            
            if codepoint == "<" {
                if !try_parse_tag(model, tag_node)  return false;
                character_data_substring = .{ 0, lexer.file.data };
            }
        }
    }
    
    return true;
}