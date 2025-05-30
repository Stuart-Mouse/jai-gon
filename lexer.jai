/*
    Lexer is entirely #scope_module right now due to the fact that it's probabyl higher up on the list of things that are subject to change.
    I want to give another go at storing some more token type info for the name/value of nodes, and just see how that plays out now that things are more organized.
*/

#scope_module

whitespace_chars :: " \t\r\n\0,:";

Token :: struct {
    type:       Token_Type;
    text:       string;
    location:   Source_Code_Location;
}

Token_Type :: enum #specified {
    ERROR :: -1;
    EOF   ::  0;
    
    OBJECT_BEGIN :: #char "{";
    OBJECT_END   :: #char "}";
    ARRAY_BEGIN  :: #char "[";
    ARRAY_END    :: #char "]";
    
    IDENTIFIER :: 255 + 1;
    STRING     :: 255 + 2;
    NUMBER     :: 255 + 3;
}

Lexer :: struct {
    using #as scanner:  Scanner;
    next_token:  Token;
}

init_lexer :: (lexer: *Lexer, file: string, file_path := "") {
    init_scanner(lexer, file, file_path);
    get_token(lexer);
}

get_token_or_return :: (using lexer: *Lexer, code: Code) -> Token #expand {
    token := get_token(lexer);
    if token.type == .ERROR  `return #insert code;
    return token;
}

get_token :: inline (using lexer: *Lexer) -> Token {
    if next_token.type == .ERROR {
        return next_token;
    }
    
    current_token := next_token;
    next_token = lex_next_token(lexer);
    return current_token;
}

peek_token :: inline (using t: *Lexer) -> Token {
    return next_token;
}

// only consumes token if it was the expected type
expect_token_type :: (using lexer: *Lexer, type: Token_Type) -> bool {
    token := peek_token(lexer);
    if token.type == type {
        get_token(lexer);
        return true;
    }
    return false;
}

make_error_token :: (message: string = "", location: Source_Code_Location) -> Token { 
    return .{ .ERROR, message, location }; 
}

// mutates the passed string, advancing it to the position after the returned token
lex_next_token :: (using lexer: *Lexer) -> Token {
    if !skip_whitespace_and_comments(lexer)  return .{ type = .EOF };
    token_location := lexer.location;
    
    // single character tokens
    if file[0] == {
      case "{";  advance(lexer);  return .{ .OBJECT_BEGIN, "{", token_location };
      case "}";  advance(lexer);  return .{ .OBJECT_END,   "}", token_location };
      case "[";  advance(lexer);  return .{ .ARRAY_BEGIN,  "[", token_location };
      case "]";  advance(lexer);  return .{ .ARRAY_END,    "]", token_location };
    }
    
    token_text := try_lex_number(lexer);
    if token_text  return .{ .NUMBER, token_text, token_location };
    
    token_text = try_lex_identifier(lexer);
    if token_text  return .{ .IDENTIFIER, token_text, token_location };
    
    // parse string
    // NOTE: only supporting regular (double) quotes at the moment due to the fact that we don't preserve info about what type of quotes parsed in file.
    if file[0] == "\"" { 
        quote_char := file[0];
        
        if !advance(lexer)  return make_error_token("Unexpected EOF while parsing string", token_location);
        token_text := string.{ 0, file.data };
        
        while file[0] != quote_char {
            if file[0] == "\\" {
                _, ok := parse_escape_sequence(lexer);
                if !ok  return make_error_token("Invalid escape sequence encountered while parsing string", token_location);
            } else {
                if !advance(lexer)  return make_error_token("Unexpected EOF while parsing string", token_location);
            }
        }
        
        token_text.count = lexer.file.data - token_text.data;
        advance(lexer);
        return .{ .STRING, token_text, token_location };
    }
    
    return make_error_token("Unexpected character encountered", token_location);
}

begins_identifier :: (char: u8) -> bool { return is_alpha(char) || char == "_"; }
continues_identifier :: is_alnum;

try_lex_identifier :: (using lexer: *Lexer) -> string {
    if begins_identifier(file[0]) {
        str: string = .{ 1, *file[0] };
        while continues_identifier(file[0]) && advance(lexer) {}
        str.count = file.data - str.data;
        return str;
    }
    return "";
}

is_legal_identifier :: (str: string) -> bool {
    if !str return false;
    if !begins_identifier(str[0])  return false;
    for str  if !continues_identifier(it)  return false;
    return true;
}

// TODO: provide an alternate version that user can enable to get c-style comments instead of, or in addition to # comments
skip_whitespace_and_comments :: (using lexer: *Lexer) -> bool {
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
