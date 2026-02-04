#scope_module

JSON_Token :: struct {
    kind:       Kind;
    text:       string;
    location:   Source_Code_Location;
    
    Kind :: enum #specified {
        ERROR           :: -1;
        EOF             ::  0;
        
        VALUE_SEPARATOR :: #char "|";
        COLON           :: #char ":";
        COMMA           :: #char ",";
        
        OBJECT_BEGIN    :: #char "{";
        OBJECT_END      :: #char "}";
        ARRAY_BEGIN     :: #char "[";
        ARRAY_END       :: #char "]";
        
        IDENTIFIER      :: 255 + 1;
        STRING          :: 255 + 2;
        NUMBER          :: 255 + 3;
        NULL            :: 255 + 4;
        TRUE            :: 255 + 5;
        FALSE           :: 255 + 6;
    }
}

JSON_Lexer :: struct {
    using #as scanner: Scanner;
    next_token:  JSON_Token;
    
    using config: JSON_Lexer_Config;
}

init_lexer :: (lexer: *JSON_Lexer, config: JSON_Lexer_Config, file: string, file_path_for_logging := "") {
    lexer.config   = config;
    lexer.file     = file;
    lexer.location = .{ file_path_for_logging, 1, 1 };
    get_token(lexer);
}

get_token :: inline (using lexer: *JSON_Lexer) -> JSON_Token {
    if next_token.kind == .ERROR {
        return next_token;
    }
    
    current_token := next_token;
    next_token = lex_next_token(lexer);
    return current_token;
}

peek_token :: inline (using t: *JSON_Lexer) -> JSON_Token {
    return next_token;
}

make_error_token :: (message: string = "", location: Source_Code_Location) -> JSON_Token { 
    return .{ .ERROR, message, location }; 
}

lex_next_token :: (using lexer: *JSON_Lexer) -> JSON_Token {
    if !lexer.skip_whitespace(lexer)  return .{ kind = .EOF };
    token_location := lexer.location;
    
    return_error :: (message: string = "") #expand { `return .{ .ERROR, message, token_location }; }
    
    // single character tokens
    if file[0] == {
      case "|";  advance(lexer);  return .{ .VALUE_SEPARATOR, "|", token_location };
      case ":";  advance(lexer);  return .{ .COLON,           ":", token_location };
      case ",";  advance(lexer);  return .{ .COMMA,           ",", token_location };
      case "{";  advance(lexer);  return .{ .OBJECT_BEGIN,    "{", token_location };
      case "}";  advance(lexer);  return .{ .OBJECT_END,      "}", token_location };
      case "[";  advance(lexer);  return .{ .ARRAY_BEGIN,     "[", token_location };
      case "]";  advance(lexer);  return .{ .ARRAY_END,       "]", token_location };
    }
    
    // identifier-like tokens 
    if begins_with(file, "true" ) { advance(lexer, 4); return .{ .TRUE,  "true",  token_location }; }
    if begins_with(file, "false") { advance(lexer, 5); return .{ .FALSE, "false", token_location }; }
    if begins_with(file, "null" ) { advance(lexer, 4); return .{ .NULL,  "null",  token_location }; }
    
    // try lexing a number
    {
        ok, text := lexer.try_lex_number(lexer);
        if !ok   return_error(text);
        if text  return .{ .NUMBER, text, token_location };
    }
    
    // try lexing an identifier
    {
        ok, text := lexer.try_lex_identifier(lexer);
        if !ok   return_error(text);
        if text  return .{ .IDENTIFIER, text, token_location };
    }
    
    // try lexing a string
    if file[0] == "\"" { 
        quote_char := file[0];
        
        if !advance(lexer)  return_error("Unexpected EOF while parsing string.");
        start := file.data;
        
        while file[0] != quote_char {
            if file[0] == "\\" {
                if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                
                if is_any(file[0], "\"\\/bfnrt") {
                    if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                } else if file[0] == "u" {
                    if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                    for 0..3 {
                        if !is_digit(file[0])  return_error("Unexpected character while parsing escape sequence.");
                        if !advance(lexer)     return_error("Unexpected EOF while parsing escape sequence.");
                    }
                } else {
                    return_error("Unexpected character while parsing escape sequence.");
                }
            } else {
                codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
                if result != .CONVERSION_OK {
                    return_error("utf8 decode error while parsing string.");
                }
                if codepoint < 0x20 || codepoint > 0x10FFFF {
                    return_error("Invalid character while parsing string.");
                }
                if !advance(lexer, len)  return_error("Unexpected EOF while parsing string.");
            }
        }
        
        text := string.{ file.data - start, start };
        advance(lexer);
        return .{ .STRING, text, token_location };
    }
    
    return_error("Unexpected character encountered.");
}

JSON_skip_whitespace :: (using lexer: *JSON_Lexer) -> bool {
    while is_any(file[0], lexer.whitespace_characters) {
        if !advance(lexer) return false;
    }
    return true;
}

JSON_try_lex_number :: (using lexer: *JSON_Lexer) -> bool, string {
    if !file  return true, "";
    
    start := file.data;
    
    if file[0] == "-" {
        if !advance(lexer)  return false, "Unexpected EOF while parsing number.";
    }
    
    first_digit := file[0];
    if !is_digit(first_digit) {
        if file.data == start  return true, "";
        return false, "Unexpected character while parsing number, expected a digit.";
    }
    
    if advance(lexer) {
        if first_digit != "0" {
            while is_digit(file[0]) && advance(lexer)  {};
        }
        
        if file[0] == "." {
            if !advance(lexer)  return false, "Unexpected EOF while parsing number.";
            
            if !is_digit(file[0])  return false, "Unexpected character while parsing number, expected a digit.";
            while is_digit(file[0]) && advance(lexer)  {};
        }
        
        if file && (file[0] == "e" || file[0] == "E") {
            if !advance(lexer)  return false, "Unexpected EOF while parsing number.";
            
            if (file[0] == "+" || file[0] == "-") {
                if !advance(lexer)  return false, "Unexpected EOF while parsing number.";
            }
            
            if !is_digit(file[0])  return false, "Unexpected character while parsing number, expected a digit.";
            while is_digit(file[0]) && advance(lexer)  {};
        }
    }
    
    return true, .{ file.data - start, start };
}

