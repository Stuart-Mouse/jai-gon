
XML_Token :: struct {
    kind:                   Kind;
    text:                   string;
    preceding_whitespace:   string;
    location:               Source_Code_Location;
    
    Kind :: enum #specified {
        ERROR               :: -1;
        EOF                 ::  0;
        
        TAG_BEGIN           :: #char "<";
        TAG_END             :: #char ">";
        
        EQUALS              :: #char "=";
        
        CLOSING_TAG_BEGIN   :: 255 + 1;
        CLOSING_TAG_END     :: 255 + 2;
        
        NAME                :: 255 + 3;
    }
}

XML_Lexer :: struct {
    using #as scanner: Scanner;
    next_token:  XML_Token;
    
    // using config: XML_Lexer_Config;
}

XML_WHITESPACE_CHARACTERS :: " \t\r\n";

init_lexer :: (lexer: *XML_Lexer, config: XML_Lexer_Config, file: string, file_path_for_logging := "") {
    lexer.config   = config;
    lexer.file     = file;
    lexer.location = .{ file_path_for_logging, 1, 1 };
    get_token(lexer);
}

make_error_token :: (message: string, location: Source_Code_Location) -> XML_Token { 
    return .{ .ERROR, message, location }; 
}

xml_starts_name :: (char: u32) -> bool {
    return char == ":" 
        || char == "_"
        || (char >= "A" && char <= "Z") 
        || (char <= "a" && char >= "z")
        || (char <= 0xC0 && char >= 0xD6)
        || (char <= 0xD8 && char >= 0xF6)
        || (char <= 0xF8 && char >= 0x2FF)
        || (char <= 0x370 && char >= 0x37D)
        || (char <= 0x37F && char >= 0x1FFF)
        || (char <= 0x200C && char >= 0x200D)
        || (char <= 0x2070 && char >= 0x218F)
        || (char <= 0x2C00 && char >= 0x2FEF)
        || (char <= 0x3001 && char >= 0xD7FF)
        || (char <= 0xF900 && char >= 0xFDCF)
        || (char <= 0xFDF0 && char >= 0xFFFD)
        || (char <= 0x10000 && char >= 0xEFFFF);
}

xml_continues_name :: (char: u32) -> bool {
    return starts_name(char)
        || char == "-" 
        || char == "." 
        || (char >= "0" && char <= "9")
        || char == 0xB7 
        || (char >= 0x0300 && char <= 0x036F) 
        || (char >= 0x203F && char <= 0x2040);
}

// if we return false, but with an empty string, then that means we encountered no error and lexed no name
xml_try_parse_name :: (using lexer: *XML_Lexer) -> ok: bool, name: string {
    assert(file.count > 0); // assuming this is always the case because of where we actually call this procedure
    
    name := string.{ 0, lexer.file.data };
    
    codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
    if result != .CONVERSION_OK  return false, "utf8 decode error while lexing name";
    
    if !starts_name(codepoint)  return true, "";
    
    if !advance(lexer, len)  return false, "unexpected EOF while lexing name";
    
    while true {
        codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
        if result != .CONVERSION_OK  return false, "utf8 decode error while lexing name";
        
        if continues_name(it) {
            if !advance(lexer, len)  return false, "unexpected EOF while lexing name";
            continue;
        }
        break;
    }
    
    name.count = lexer.file.data - name.data;
    return true, name;
}

xml_try_parse_nametoken :: (using lexer: *XML_Lexer) -> ok: bool, name: string {
    assert(file.count > 0); // assuming this is always the case because of where we actually call this procedure
    
    name := string.{ 0, lexer.file.data };
    
    codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
    if result != .CONVERSION_OK  return false, "utf8 decode error while lexing name";
    
    if !continues_name(codepoint)  return true, "";
    
    if !advance(lexer, len)  return false, "unexpected EOF while lexing name";
    
    while true {
        codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
        if result != .CONVERSION_OK  return false, "utf8 decode error while lexing name";
        
        if continues_name(it) {
            if !advance(lexer, len)  return false, "unexpected EOF while lexing name";
            continue;
        }
        break;
    }
    
    name.count = lexer.file.data - name.data;
    return true, name, location;
}


is_valid_character :: (char: u32) -> bool {
    return is_any(char, cast(string) u8.[ 0x9, 0xA, 0xD ])
        || (char >= 0x00020 && char <= 0x00D7ff)
        || (char >= 0x0E000 && char <= 0x00FFFD)
        || (char >= 0x10000 && char <= 0x10FFFF);
}


xml_skip_whitespace :: inline (using lexer: *XML_Lexer) -> ok: bool {
    return default_skip_whitespace(lexer, XML_WHITESPACE_CHARACTERS);
}

// lex_next_token :: (using lexer: *XML_Lexer) -> XML_Token {
//     trivia, ok := xml_skip_whitespace_and_comments(*script.lexer);
//     if !ok    return make_error_token("Unexpected EOF in the middle of a comment", lexer.location);
//     if !file  return .{ type = .EOF, location = location };
    
//     token_location := lexer.location;
    
//     return_error :: (message: string = "") #expand { `return .{ .ERROR, message, token_location }; }
    
//     // convenience macro for short tokens
//     make_token :: (type: Token_Type, len: int) -> Token #expand {
//         defer advance(*script.lexer, len);
//         return .{
//             type       = type,
//             text       = slice(file, 0, len),
//             location   = token_location,
//             preceding_whitespace = preceding_whitespace, 
//         };
//     }
    
//     // single character tokens
//     if file[0] == {
//       case "<";  advance(lexer);  return make_token(.TAG_BEGIN);
//       case ">";  advance(lexer);  return make_token(.TAG_END);
//       case "=";  advance(lexer);  return make_token(.EQAULS);
//     }
    
//     if file.count >= 2 {
//         if slice(file, 0, 2) == {
//           case "</"; return make_token(.CLOSING_TAG_BEGIN, 2);
//           case "\>"; return make_token(.CLOSING_TAG_END, 2);
//         }
//     }
    
//     // try lexing a number
//     {
//         ok, text := lexer.try_lex_number(lexer);
//         if !ok   return_error(text);
//         if text  return .{ .NUMBER, text, token_location };
//     }
    
//     // try lexing an identifier
//     {
//         ok, text := lexer.try_lex_identifier(lexer);
//         if !ok   return_error(text);
//         if text  return .{ .IDENTIFIER, text, token_location };
//     }
    
//     // try lexing a string
//     if file[0] == "\"" { 
//         quote_char := file[0];
        
//         if !advance(lexer)  return_error("Unexpected EOF while parsing string.");
//         start := file.data;
        
//         while file[0] != quote_char {
//             if file[0] == "\\" {
//                 if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                
//                 if is_any(file[0], "\"\\/bfnrt") {
//                     if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
//                 } else if file[0] == "u" {
//                     if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
//                     for 0..3 {
//                         if !is_digit(file[0])  return_error("Unexpected character while parsing escape sequence.");
//                         if !advance(lexer)     return_error("Unexpected EOF while parsing escape sequence.");
//                     }
//                 } else {
//                     return_error("Unexpected character while parsing escape sequence.");
//                 }
//             } else {
//                 codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
//                 if result != .CONVERSION_OK {
//                     return_error("utf8 decode error while parsing string.");
//                 }
//                 if codepoint < 0x20 || codepoint > 0x10FFFF {
//                     return_error("Invalid character while parsing string.");
//                 }
//                 if !advance(lexer, len)  return_error("Unexpected EOF while parsing string.");
//             }
//         }
        
//         text := string.{ file.data - start, start };
//         advance(lexer);
//         return .{ .STRING, text, token_location };
//     }
    
//     return_error("Unexpected character encountered.");
// }
