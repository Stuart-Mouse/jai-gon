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
    
    while !is_eof(*lexer) {
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
    
    if next_byte(*lexer) == "<" {
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
            existing_node := get_child_node_by_name(parent_tag, tag_name);
            if existing_node && existing_node.kind == .TAG {
                report_error(model, tag_location, "duplicate tag '%' encountered", tag_name);
                return false;
            }
            tag_node = insert_child_node(model, ifx parent_tag else model.root, tag_name, .TAG);
        }
        tag_node.location = tag_location;
        
        
        while parse_attributes := true {
            if !xml_skip_whitespace(*lexer)  return false;
            
            if begins_with(*lexer, "/>") {
                advance(*lexer, 2);
                return true;
            }
            
            if next_byte(*lexer) == ">" {
                if !advance(*lexer) {
                    report_error(model, lexer.location, "unexpected EOF while parsing tag contents in XML document");  
                    return false;
                }
                break parse_attributes;
            }
            
            if !xml_try_parse_attribute(model, tag_node)  return false;
        }
        
        tag_value_begin := lexer.cursor;
        
        
        character_data_start := get_marker(lexer);
        
        while true {
            if next_byte(*lexer) == "<" {
                // commit pending character data section
                character_data_substring := substring_from_marker(*lexer, character_data_start);
                character_data_substring = trim(character_data_substring, XML_WHITESPACE_CHARACTERS); // TODO: maybe use a flag to not do this!
                if character_data_substring {
                    character_data_node := insert_child_node(model, tag_node, "", .CHARACTER_DATA);
                    character_data_node.location     = character_data_start.location;
                    character_data_node.string_value = character_data_substring;
                }
                character_data_start = .{};
                
                // Check for closing tag
                if bytes_remaining(*lexer) > 1 && (lexer.cursor + 1).* == "/" {
                    tag_value_end := lexer.cursor;
                    
                    if !advance(*lexer, 2) {
                        report_error(model, lexer.location, "unexpected EOF while parsing end tag in XML document");  
                        return false;
                    }
                    if !begins_with(*lexer, tag_name) {
                        report_error(model, lexer.location, "mismatched end tag in XML document");
                        return false;
                    }
                    if !advance(*lexer, tag_name.count) {
                        report_error(model, lexer.location, "unexpected EOF while parsing end tag in XML document");  
                        return false;
                    }
                    if !xml_skip_whitespace(*lexer)  return false;
                    if next_byte(*lexer) != ">" {
                        report_error(model, lexer.location, "expected `>` or `/>` to close end tag");
                        return false;
                    }
                    advance(*lexer);
                    
                    tag_node.string_value = make_string_from_range(tag_value_begin, tag_value_end);
                    return true;
                }
                
                if !xml_try_parse_tag(model, tag_node)  return false;
            }
            
            // begin a new character data substring if we are not currently constructing one
            if character_data_start.cursor == null {
                character_data_start = get_marker(lexer);
            }
            
            ok, parsed_reference := xml_try_parse_reference(model);
            if !ok  return false;
            if parsed_reference  continue;
            
            rune := next_rune(*lexer);
            if !rune && has_error(*lexer) { 
                report_error(model, lexer.location, get_error_string(*lexer));
                return false;
            }
            if !xml_is_valid_character(rune) {
                report_error(model, lexer.location, "invalid character encountered");
                return false;
            }
            if !advance(*lexer) {
                report_error(model, lexer.location, "unexpected EOF in XML document while parsing character data");
                return false;
            }
        }
    }
    
    return true;
}

// TODO: return normalized attribute value here if it is possible to do so in single pass
xml_try_parse_attribute :: (model: *Data_Model, parent_tag: *Data_Model.Node) -> bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    attribute_location := lexer.location;
    
    ok, attribute_name := xml_try_parse_name(*lexer);
    if !ok || !attribute_name {
        report_error(model, attribute_location, "expected an attribute name");
        return false;
    }
    
    if !xml_skip_whitespace(*lexer)  return false;
    
    if next_byte(*lexer) != "=" {
        report_error(model, lexer.location, "expected an `=` after attribute name");
        return false;
    }
    if !advance(*lexer) {
        report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute");
        return false;
    }
    
    if !xml_skip_whitespace(*lexer)  return false;
    
    quote_character := next_byte(*lexer);
    if !is_any(quote_character, "'\"") {
        report_error(model, lexer.location, "expected a single or double quotation mark character to begin attribute value");
    }
    if !advance(*lexer) {
        report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute");
        return false;
    }
    
    attribute_value_start := lexer.cursor;
    while next_byte(*lexer) != quote_character {
        ok, parsed_reference := xml_try_parse_reference(model);
        if !ok  return false;
        if parsed_reference  continue;
        
        rune := next_rune(*lexer);
        if !rune && has_error(*lexer) { 
            report_error(model, lexer.location, get_error_string(*lexer));
            return false;
        }
        if !xml_is_valid_character(rune) {
            report_error(model, lexer.location, "invalid character encountered");
            return false;
        }
        if !advance(*lexer) {
            report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute value");
            return false;
        }
    }
    attribute_value := make_string_from_range(attribute_value_start, lexer.cursor);
    
    if !advance(*lexer) {
        report_error(model, lexer.location, "unexpected EOF in XML document while parsing attribute");
        return false;
    }
    
    existing_node := get_child_node_by_name(parent_tag, attribute_name);
    if existing_node && existing_node.kind == .ATTRIBUTE {
        report_error(model, attribute_location, "duplicate attribute '%' encountered", attribute_name);
        return false;
    }
    
    attribute_node := insert_child_node(model, parent_tag, attribute_name, .ATTRIBUTE);
    attribute_node.location     = attribute_location;
    attribute_node.string_value = attribute_value;
    
    return true;
}

// return normalized value if it is possible to parse XML in single pass
xml_try_parse_reference :: (model: *Data_Model) -> ok: bool, was_parsed: bool {
    using xml_context := model.language.language_context.(*XML_Context);
    
    reference_location := lexer.location;
    
    // character reference
    if begins_with(*lexer, "&#") {
        if !advance(*lexer, 2) {
            report_error(model, reference_location, "unexpected EOF in XML document while while parsing reference");
            return false, false;
        }
        if !advance(*lexer) {
            report_error(model, reference_location, "unexpected EOF in XML document while while parsing character reference");
            return false, false;
        }
        if next_byte(*lexer) == "x" {
            if !advance(*lexer) {
                report_error(model, reference_location, "unexpected EOF in XML document while while parsing character reference");
                return false, false;
            }
        }
        while next_byte(*lexer) != ";" {
            if !is_digit(next_byte(*lexer)) {
                report_error(model, reference_location, "unexpected character encountered in XML document while while parsing character reference");
                return false, false;
            }
            if !advance(*lexer) {
                report_error(model, reference_location, "unexpected EOF in XML document while while parsing character reference");
                return false, false;
            }
        }
        advance(*lexer);
        return true, true;
    }
    
    // (parameter) entity reference
    if next_byte(*lexer) == "&" || next_byte(*lexer) == "%" {
        if !advance(*lexer) {
            report_error(model, reference_location, "unexpected EOF in XML document while while parsing character reference");
            return false, false;
        }
        ok, name := xml_try_parse_name(*lexer);
        if !ok {
            report_error(model, reference_location, name);
            return false, false;
        }
        if !name {
            report_error(model, reference_location, "unable to parse reference");
            return false, false;
        }
        if next_byte(*lexer) != ";" {
            report_error(model, reference_location, "expected a semicolon to terminate reference");
            return false, false;
        }
        return true, true;
    }
    
    return true, false;
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
    init_scanner(lexer, file, file_path_for_logging);
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
    if is_eof(lexer)  return true, "";
    
    name_start := lexer.cursor;
    
    rune := next_rune(lexer);
    if !rune && has_error(lexer) { 
        return false, get_error_string(lexer);
    }
    
    if !xml_starts_name(rune)  return true, "";
    
    if !advance(lexer)  return false, "unexpected EOF while parsing name";
    
    while true {
        rune := next_rune(lexer);
        if !rune && has_error(lexer) { 
            return false, get_error_string(lexer);
        }
        if xml_continues_name(rune) {
            if !advance(lexer)  return false, "unexpected EOF while parsing name";
            continue;
        }
        break;
    }
    
    return true, make_string_from_range(name_start, lexer.cursor);
}

xml_try_parse_nametoken :: (lexer: *XML_Lexer) -> ok: bool, name: string {    
    if is_eof(lexer)  return true, "";
    
    name_start := lexer.cursor;
    
    rune := next_rune(lexer);
    if !rune && has_error(lexer) { 
        return false, get_error_string(lexer);
    }
    
    if !xml_continues_name(rune)  return true, "";
    
    if !advance(lexer)  return false, "unexpected EOF while parsing name";
    
    while true {
        rune := next_rune(lexer);
        if !rune && has_error(lexer) { 
            return false, get_error_string(lexer);
        }
        if xml_continues_name(rune) {
            if !advance(lexer)  return false, "unexpected EOF while parsing name";
            continue;
        }
        break;
    }
    
    return true, make_string_from_range(name_start, lexer.cursor);
}

xml_is_valid_character :: (char: u32) -> bool {
    return char == 0x9
        || char == 0xA
        || char == 0xD
        || (char >= 0x00020 && char <= 0x00D7ff)
        || (char >= 0x0E000 && char <= 0x00FFFD)
        || (char >= 0x10000 && char <= 0x10FFFF);
}

xml_skip_whitespace :: inline (lexer: *XML_Lexer) -> ok: bool {
    return default_skip_whitespace(lexer, XML_WHITESPACE_CHARACTERS);
}

