/*
    NOTE: This is not a conformat XML implementation by any means, this is just being done as a proof-of-concept for the time being so that the overall structure of the module can be developed.
    
    
*/

xml_get_language :: (config := XML_Config.{}) -> Language {
    ctx := New(XML_Context);
    ctx.config = config;
    
    return .{
        name              = "XML",
        id                = XML_LANGUAGE_ID,
        language_context  = ctx,
        parse             = xml_parse,
        // serialize_node    = XML_serialize_node,
        deinit            = xml_deinit_language,
        default_node_insertion_behaviour = .{ mode = .RETURN_EXISTING },
    };
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

xml_deinit_language :: (model: *Data_Model) {
    ctx := model.language.language_context.(*XML_Context);
    free(ctx);
}

xml_parse :: (model: *Data_Model, file: string, file_path_for_logging := "", into: *Data_Model.Node = null) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    init_lexer(*lexer, file, file_path_for_logging);
    
    while lexer.file {
        if into == null {
            // TODO: parse other top-level elements in document
        }
        if !xml_try_parse_tag(model, into)  return false;
        if !xml_skip_whitespace(*lexer)  { log("whitespace error at %", #location()); return false; }
    }
    
    return true;
}

xml_try_parse_tag :: (model: *Data_Model, parent_tag: *Data_Model.Node) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    if lexer.file[0] == "<" {
        tag_location := lexer.location;
        if !advance(*lexer) {
            report_error(model, lexer.location, "unexpected EOF while parsing start tag in XML document");  
            return false;
        }
        
        ok, tag_name := xml_try_parse_name(*lexer);
        if !ok || !tag_name {
            report_error(model, tag_location, "expected a name");
            return false;
        }
        
        tag_node: *Data_Model.Node;
        if parent_tag == null {
            // Then this must be the root node. If we already have a root node on the data model then someone messed up!
            if model.root != null {
                report_error(model, tag_location, "cannot have multiple top-level tags in xml!");
                return false;
            }
            ensure_root_node_exists(model);
            tag_node = model.root;
        } else {
            tag_node=, is_duplicate := maybe_insert_child_node(model, ifx parent_tag else model.root, tag_name, .TAG);
            if is_duplicate {
                report_error(model, tag_location, "duplicate tags are not allowed!");
                return false;
            }
        }
        tag_node.location = tag_location;
        
        
        while parse_attributes := true {
            if !xml_skip_whitespace(*lexer)  return false;
            
            if begins_with(lexer.file, "/>") {
                advance(lexer.file, 2);
                return true;
            }
            
            if lexer.file[0] == ">" {
                if !advance(*lexer) {
                    report_error(model, lexer.location, "unexpected EOF while parsing tag contents in XML document");  
                    return false;
                }
                break parse_attributes;
            }
            
            if !xml_try_parse_attribute(model, tag_node)  return false;
        }
        
        tag_value_begin := lexer.file.data;
        
        character_data_location := lexer.location;
        character_data_substring := string.{ 0, lexer.file.data };
        
        while true {
            commit_character_data :: () #expand {
                character_data_substring = trim(character_data_substring, XML_WHITESPACE_CHARACTERS);
                if character_data_substring {
                    character_data_node := insert_child_node(model, tag_node, "", .CHARACTER_DATA);
                    character_data_node.location     = character_data_location;
                    character_data_node.string_value = character_data_substring;
                }
                character_data_substring = "";
            }
            
            if lexer.file[0] == "<" {
                commit_character_data();
                
                // Check for closing tag
                if lexer.file.count > 1 && lexer.file[1] == "/" {
                    tag_value_end := lexer.file.data;
                    
                    if !advance(*lexer, 2) {
                        report_error(model, lexer.location, "unexpected EOF while parsing end tag in XML document");  
                        return false;
                    }
                    if !begins_with(lexer.file, tag_name) {
                        report_error(model, lexer.location, "mismatched end tag in XML document");
                        return false;
                    }
                    if !advance(*lexer, tag_name.count) {
                        report_error(model, lexer.location, "unexpected EOF while parsing end tag in XML document");  
                        return false;
                    }
                    if !xml_skip_whitespace(*lexer)  return false;
                    if lexer.file[0] != ">" {
                        report_error(model, lexer.location, "expected `>` or `/>` to close end tag");
                        return false;
                    }
                    advance(*lexer);
                    
                    tag_node.string_value = string.{ tag_value_end - tag_value_begin, tag_value_begin };
                    return true;
                }
                
                if !xml_try_parse_tag(model, tag_node)  return false;
            }
            
            // begin a new character data substring if we are not currently constructing one
            character_data_substring.data = ifx character_data_substring.data else lexer.file.data;
            
            if lexer.file[0] == "&" {
                report_error(model, lexer.location, "TODO: character and entity references are not yet supported");
                return false;
            }
            
            codepoint, codepoint_length, utf8_decode_result := character_utf8_to_utf32(lexer.file.data, lexer.file.count);
            if utf8_decode_result != .CONVERSION_OK { 
                report_error(model, lexer.location, "utf8 decode error while parsing XML document");
                return false;
            }
            
            if !xml_is_valid_character(codepoint) {
                report_error(model, lexer.location, "invalid character encountered");
                return false;
            }
            
            if !advance(*lexer, codepoint_length) {
                report_error(model, lexer.location, "unexpected EOF in XML document while parsing character data");
                return false;
            }
            
            character_data_substring.count += codepoint_length;
        }
    }
    
    return true;
}

xml_try_parse_attribute :: (model: *Data_Model, parent_tag: *Data_Model.Node) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    attribute_location := lexer.location;
    
    ok, attribute_name := xml_try_parse_name(*lexer);
    if !ok || !attribute_name {
        report_error(model, attribute_location, "expected an attribute name");
        return false;
    }
    
    if !xml_skip_whitespace(*lexer)  return false;
    
    if lexer.file[0] != "=" {
        report_error(model, lexer.location, "expected an `=` after attribute name");
        return false;
    }
    if !advance(*lexer) {
        report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute");
        return false;
    }
    
    if !xml_skip_whitespace(*lexer)  return false;
    
    quote_character := lexer.file[0];
    if !is_any(quote_character, "'\"") {
        report_error(model, lexer.location, "expected a single or double quotation mark character to begin attribute value");
    }
    if !advance(*lexer) {
        report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute");
        return false;
    }
    
    attribute_value := string.{ 0, lexer.file.data };
    while lexer.file[0] != quote_character {
        codepoint, codepoint_length, utf8_decode_result := character_utf8_to_utf32(lexer.file.data, lexer.file.count);
        if utf8_decode_result != .CONVERSION_OK { 
            report_error(model, lexer.location, "utf8 decode error while parsing XML document");
            return false;
        }
        
        if !xml_is_valid_character(codepoint) {
            report_error(model, lexer.location, "invalid character encountered");
            return false;
        }
        
        if !advance(*lexer, codepoint_length) {
            report_error(model, lexer.location, "unexpected EOF in XML document while parsing string data");
            return false;
        }
    }
    attribute_value.count = lexer.file.data - attribute_value.data;
    
    if !advance(*lexer) {
        report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute");
        return false;
    }
    
    attribute_node := insert_child_node(model, parent_tag, "", .ATTRIBUTE);
    attribute_node.location     = attribute_location;
    attribute_node.string_value = attribute_value;
    
    return true;
}    
                

/*
    NOTE:
    For the XML Lexer I am not bothering to actaully tokenize, since XML is kind of weird about whitespace and for the most part it doesn't really make sense to tokenize the input rather than just parse it byte-by-byte.
    Maybe I will change my mind later, but for now this seems to be the most simple approach.
*/

XML_Lexer :: struct {
    using #as scanner: Scanner;
    
    // using config: XML_Lexer_Config;
}

XML_WHITESPACE_CHARACTERS :: " \t\r\n";

init_lexer :: (lexer: *XML_Lexer, file: string, file_path_for_logging := "") {
    lexer.file     = file;
    lexer.location = .{ file_path_for_logging, 1, 1 };
}

xml_starts_name :: (char: u32) -> bool {
    return char == #char ":" 
        || char == #char "_"
        || (char >= #char "A" && char <= #char "Z") 
        || (char >= #char "a" && char <= #char "z")
        || (char >= 0xC0    && char <= 0xD6)
        || (char >= 0xD8    && char <= 0xF6)
        || (char >= 0xF8    && char <= 0x2FF)
        || (char >= 0x370   && char <= 0x37D)
        || (char >= 0x37F   && char <= 0x1FFF)
        || (char >= 0x200C  && char <= 0x200D)
        || (char >= 0x2070  && char <= 0x218F)
        || (char >= 0x2C00  && char <= 0x2FEF)
        || (char >= 0x3001  && char <= 0xD7FF)
        || (char >= 0xF900  && char <= 0xFDCF)
        || (char >= 0xFDF0  && char <= 0xFFFD)
        || (char >= 0x10000 && char <= 0xEFFFF);
}

xml_continues_name :: (char: u32) -> bool {
    return xml_starts_name(char)
        || char == #char "-" 
        || char == #char "." 
        || char == 0xB7 
        || (char >= #char "0" && char <= #char "9")
        || (char >= 0x0300 && char <= 0x036F) 
        || (char >= 0x203F && char <= 0x2040);
}

xml_try_parse_name :: (lexer: *XML_Lexer) -> ok: bool, name: string {    
    assert(lexer.file.count > 0); // assuming this is always the case because of where we actually call this procedure
    
    name := string.{ 0, lexer.file.data };
    
    codepoint, codepoint_length, utf8_decode_result := character_utf8_to_utf32(lexer.file.data, lexer.file.count);
    if utf8_decode_result != .CONVERSION_OK  return false, "utf8 decode error while parsing name";
    
    if !xml_starts_name(codepoint)  return true, "";
    
    if !advance(lexer, codepoint_length)  return false, "unexpected EOF while parsing name";
    
    while true {
        codepoint, codepoint_length, utf8_decode_result = character_utf8_to_utf32(lexer.file.data, lexer.file.count);
        if utf8_decode_result != .CONVERSION_OK  return false, "utf8 decode error while parsing name";
        
        if xml_continues_name(codepoint) {
            if !advance(lexer, codepoint_length)  return false, "unexpected EOF while parsing name";
            continue;
        }
        break;
    }
    
    name.count = lexer.file.data - name.data;
    return true, name;
}

xml_try_parse_nametoken :: (lexer: *XML_Lexer) -> ok: bool, name: string {    
    assert(lexer.file.count > 0); // assuming this is always the case because of where we actually call this procedure
    
    name := string.{ 0, lexer.file.data };
    
    codepoint, codepoint_length, utf8_decode_result := character_utf8_to_utf32(file.data, file.count);
    if utf8_decode_result != .CONVERSION_OK  return false, "utf8 decode error while parsing nametoken";
    
    if !xml_continues_name(codepoint)  return true, "";
    
    if !advance(lexer, codepoint_length)  return false, "unexpected EOF while parsing nametoken";
    
    while true {
        codepoint, codepoint_length, utf8_decode_result = character_utf8_to_utf32(file.data, file.count);
        if utf8_decode_result != .CONVERSION_OK  return false, "utf8 decode error while parsing nametoken";
        
        if xml_continues_name(it) {
            if !advance(lexer, codepoint_length)  return false, "unexpected EOF while parsing nametoken";
            continue;
        }
        break;
    }
    
    name.count = lexer.file.data - name.data;
    return true, name;
}

xml_is_valid_character :: (char: u32) -> bool {
    return char == 0x9
        || char == 0xA
        || char == 0xD
        || (char >= 0x00020 && char <= 0x00D7ff)
        || (char >= 0x0E000 && char <= 0x00FFFD)
        || (char >= 0x10000 && char <= 0x10FFFF);
}

// is_reserved_character :: (char: u32) -> bool {
//     return char == #char "<"
//         || char == #char ">";
// }

// // TODO: probably just inline this in parse_tag and check for start delimiters of the various constructs in there.
// xml_try_parse_character_data :: (lexer: *XML_Lexer) -> ok: bool, character_data: string {
//     character_data_substring := string.{ 0, lexer.file.data };
//     while lexer.file {
//         if lexer.file[0] == "&" {
//             return false, "TODO: parse character and entity references";
//         }
        
//         codepoint, codepoint_length, utf8_decode_result := character_utf8_to_utf32(lexer.file.data, lexer.file.count);
//         if utf8_decode_result != .CONVERSION_OK { 
//             return false, "utf8 decode error while parsing XML document"; 
//         }
        
//         if xml_is_valid_character(codepoint) && !is_reserved_character(codepoint) {
//             if !advance(lexer, codepoint_length)  return false, "unexpected EOF in XML document while parsing character data";
//             character_data_substring.count += codepoint_length;
//             continue;
//         }
        
//         return true, character_data_substring;
//     }
//     return true, "";
// }

xml_skip_whitespace :: inline (lexer: *XML_Lexer) -> ok: bool {
    return default_skip_whitespace(lexer, XML_WHITESPACE_CHARACTERS);
}

