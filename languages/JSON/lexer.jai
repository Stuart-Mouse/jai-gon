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
    init_scanner(lexer, file, file_path_for_logging);
    get_token(lexer);
}

get_token :: (using lexer: *JSON_Lexer) -> JSON_Token {
    if next_token.kind == .ERROR {
        return next_token;
    }
    
    current_token := next_token;
    next_token = lex_next_token(lexer);
    return current_token;
}

peek_token :: (lexer: *JSON_Lexer) -> JSON_Token {
    return lexer.next_token;
}

lex_next_token :: (lexer: *JSON_Lexer) -> JSON_Token {
    if !lexer.skip_whitespace(lexer, lexer.whitespace_characters)  return .{ .ERROR, "Unexpected EOF.", lexer.location };
    if is_eof(lexer)  return .{ kind = .EOF };
    
    token_location := lexer.location;
    return_error :: (message: string = "") #expand { `return .{ .ERROR, message, token_location }; }
    
    // single character tokens
    if get_next_byte(lexer) == {
      case "|";  advance(lexer);  return .{ .VALUE_SEPARATOR, "|", token_location };
      case ":";  advance(lexer);  return .{ .COLON,           ":", token_location };
      case ",";  advance(lexer);  return .{ .COMMA,           ",", token_location };
      case "{";  advance(lexer);  return .{ .OBJECT_BEGIN,    "{", token_location };
      case "}";  advance(lexer);  return .{ .OBJECT_END,      "}", token_location };
      case "[";  advance(lexer);  return .{ .ARRAY_BEGIN,     "[", token_location };
      case "]";  advance(lexer);  return .{ .ARRAY_END,       "]", token_location };
    }
    
    // identifier-like tokens 
    if begins_with(lexer, "true" ) { advance(lexer, 4); return .{ .TRUE,  "true",  token_location }; }
    if begins_with(lexer, "false") { advance(lexer, 5); return .{ .FALSE, "false", token_location }; }
    if begins_with(lexer, "null" ) { advance(lexer, 4); return .{ .NULL,  "null",  token_location }; }
    
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
    if get_next_byte(lexer) == "\"" { 
        quote_char := get_next_byte(lexer);
        
        if !advance(lexer)  return_error("Unexpected EOF while parsing string.");
        start := lexer.cursor;
        
        while get_next_byte(lexer) != quote_char {
            if get_next_byte(lexer) == "\\" {
                if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                
                if is_any(get_next_byte(lexer), "\"\\/bfnrt") {
                    if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                } else if get_next_byte(lexer) == "u" {
                    if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                    for 0..3 {
                        if !is_digit(get_next_byte(lexer))  return_error("Unexpected character while parsing escape sequence.");
                        if !advance(lexer)     return_error("Unexpected EOF while parsing escape sequence.");
                    }
                } else {
                    return_error("Unexpected character while parsing escape sequence.");
                }
            } else {
                rune := get_next_rune(lexer);
                if !rune && has_error(lexer) {
                    return_error(get_error_string(lexer));
                }
                if rune < 0x20 || rune > 0x10FFFF {
                    return_error("Invalid character while parsing string.");
                }
                if !advance(lexer)  return_error("Unexpected EOF while parsing string.");
            }
        }
        
        text := make_string_from_range(start, lexer.cursor);
        advance(lexer);
        return .{ .STRING, text, token_location };
    }
    
    return_error("Unexpected character encountered.");
}

json_try_lex_number :: (using scanner: *Scanner) -> bool, string {
    if is_eof(scanner)  return true, "";
    
    start := scanner.cursor;
    
    if get_next_byte(scanner) == "-" {
        if !advance(scanner)  return false, "Unexpected EOF while parsing number.";
    }
    
    first_digit := get_next_byte(scanner);
    if !is_digit(first_digit) {
        if scanner.cursor == start  return true, ""; // If we did not actually advance yet, then there is no error.
        return false, "Unexpected character while parsing number, expected a digit.";
    }
    
    if advance(scanner) {
        if first_digit != "0" {
            while is_digit(get_next_byte(scanner)) && advance(scanner)  {};
        }
        
        if get_next_byte(scanner) == "." {
            if !advance(scanner)  return false, "Unexpected EOF while parsing number.";
            
            if !is_digit(get_next_byte(scanner))  return false, "Unexpected character while parsing number, expected a digit.";
            while is_digit(get_next_byte(scanner)) && advance(scanner)  {};
        }
        
        if !is_eof(scanner) && (get_next_byte(scanner) == "e" || get_next_byte(scanner) == "E") {
            if !advance(scanner)  return false, "Unexpected EOF while parsing number.";
            
            if (get_next_byte(scanner) == "+" || get_next_byte(scanner) == "-") {
                if !advance(scanner)  return false, "Unexpected EOF while parsing number.";
            }
            
            if !is_digit(get_next_byte(scanner))  return false, "Unexpected character while parsing number, expected a digit.";
            while is_digit(get_next_byte(scanner)) && advance(scanner)  {};
        }
    }
    
    return true, make_string_from_range(start, scanner.cursor);
}

