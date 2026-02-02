#scope_module

#import "Unicode";

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
    file: string;
    next_token:  JSON_Token;
    using location: Source_Code_Location;
    
    skip_whitespace     := JSON_skip_whitespace;
    try_lex_number      := JSON_try_lex_number;
    try_lex_identifier  := default_try_lex_identifier;
    
    whitespace_characters := " \t\r\n";
}

init_lexer :: (lexer: *JSON_Lexer, file: string, file_path_for_logging := "") {
    lexer.file     = file;
    lexer.location = .{ file_path_for_logging, 1, 1 };
    get_token(lexer);
}

// advances UP TO the amount specified, returns false on EOF
advance :: inline (using lexer: *JSON_Lexer, amount := 1) -> bool {
    assert(amount >= 0);
    _amount := min(amount, file.count);
    
    for 0.._amount-1 {
        if file[it] == "\n" {
            location.line_number += 1;
            location.character_number = 1;
        } else {
            location.character_number += 1;
        }
    }
    
    file.data  += _amount;
    file.count -= _amount;
    
    return file.count > 0; // return false when we hit EOF
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




// TODO: move alternative lexer procs to some utils file

begins_identifier :: (char: u8) -> bool { return is_alpha(char) || char == "_"; }
continues_identifier :: is_alnum;

default_try_lex_identifier :: (using lexer: *JSON_Lexer) -> bool, string {
    if begins_identifier(file[0]) {
        str: string = .{ 1, *file[0] };
        while continues_identifier(file[0]) && advance(lexer) {}
        str.count = file.data - str.data;
        return true, str;
    }
    return true, "";
}

is_legal_identifier :: (str: string) -> bool {
    if !str return false;
    if !begins_identifier(str[0])  return false;
    for str  if !continues_identifier(it)  return false;
    return true;
}

skip_whitespace_and_hashtag_comments :: (using lexer: *JSON_Lexer) -> bool {
    if file.count == 0 return false;
    while true {
        while is_any(file[0], whitespace_chars) {
            if !advance(lexer) return false;
        }
        if file[0] == "#" {
            while file[0] != "\n" {
                if !advance(lexer) return false;
            }
        }
        else return true;
    }
    return true;
}

skip_whitespace_and_c_style_comments :: (using lexer: *JSON_Lexer) -> bool {
    if file.count == 0  return true;
    
    while loop := file.count > 0 {
        while is_whitespace(file[0]) {
            if !advance(lexer)  break;
        }
        if begins_with(file, "//") {
            advance(lexer, 2);
            while file[0] != #char "\n" {
                if !advance(lexer)  break loop;
            }
            advance(lexer);
        }
        else if begins_with(file, "/*") {
            advance(lexer, 2);
            while !begins_with(file, "*/") {
                if !advance(lexer) {
                    return false;
                }
            }
            advance(lexer, 2);
        }
        else break;
    }
    return true;
}



