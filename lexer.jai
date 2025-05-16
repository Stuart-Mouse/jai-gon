
whitespace_chars :: " \t\r\n\0";
reserved_chars   :: "~!@#$%^&:*{}[]()\"";
whitespace_and_reserved_chars :: #run join(whitespace_chars, reserved_chars);

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
    file:               string;
    next_token:         Token;
    cursor_location:    Source_Code_Location;
}

init_lexer :: (using t: *Lexer, filepath := "") {
    cursor_location = .{ line_number = 1, character_number = 1, fully_pathed_filename = filepath };
    get_token(t);
}

get_token_or_return :: (using t: *Lexer, code: Code) -> Token #expand {
    token := get_token(t);
    if token.type == .ERROR  `return #insert code;
    return token;
}

get_token :: inline (using t: *Lexer) -> Token {
    if next_token.type == .ERROR {
        log("%:%,%: GON Lexer Error - %", next_token.location.fully_pathed_filename, next_token.location.line_number, next_token.location.character_number, next_token.text);
        return next_token;
    }
    
    current_token := next_token;
    next_token = lex_next_token(t);
    return current_token;
}

peek_token :: inline (using t: *Lexer) -> Token {
    return next_token;
}

// consumes token if it was expected type, else it was just peeked
expect_token_type :: (using t: *Lexer, type: Token_Type) -> bool {
    token := peek_token(t);
    if token.type == type {
        get_token(t);
        return true;
    }
    return false;
}

is_numeric :: inline (char: u8) -> bool {
    return char >= #char "0" && char <= #char "9";
}

make_error_token :: (message: string = "", location: Source_Code_Location) -> Token { 
    return .{ .ERROR, message, location }; 
}

// mutates the passed string, advancing it to the position after the returned token
lex_next_token :: (using lexer: *Lexer) -> Token {
    if !skip_whitespace_and_comments(lexer)  return .{ type = .EOF };
    location := cursor_location;
    
    // single character tokens
    if file[0] == {
      case #char "{";  advance(lexer);  return .{ .OBJECT_BEGIN, "{", location };
      case #char "}";  advance(lexer);  return .{ .OBJECT_END,   "}", location };
      case #char "[";  advance(lexer);  return .{ .ARRAY_BEGIN,  "[", location };
      case #char "]";  advance(lexer);  return .{ .ARRAY_END,    "]", location };
    }
    
    str, ok := try_lex_number(lexer);
    if !ok  return make_error_token("Unexpected token while parsing number.", location);
    if str  return .{ .NUMBER, str, location };
    
    str = try_lex_identifier(lexer);
    if str  return .{ .IDENTIFIER, str, location };
    
    // parse string
    if file[0] == #char "\"" || file[0] == #char "'" || file[0] == #char "`" { 
        quote_char := file[0];
        
        if !advance(lexer)  return make_error_token("Unexpected EOF while parsing string", location);
        str := string.{ 0, file.data };
        
        while file[0] != quote_char {
            // TODO: handle escape sequences more properly
            adv := 1 + (file[0] == #char "\\").(int); 
            str.count += adv;
            if !advance(lexer, adv)  
                return make_error_token("Unexpected EOF while parsing string", location);
        }
        advance(lexer);
        
        return .{ .STRING, str, location };
    }
    
    return make_error_token("Unexpected character encountered", location);
}

try_lex_number :: (using lexer: *Lexer) -> (string, bool) {
    if is_digit(file[0]) || (file.count > 1 && file[0] == #char "-" && is_digit(file[1])) {
        str: string = .{ 1, file.data };
        advance(lexer);
        
        after_dot    := false;
        accept_alpha := false;
        if file && is_any(file[0], "bhx") {
            str.count += 1;
            if !advance(lexer)  
                return "", false;
            after_dot = true;   // so that we don't accept a dot in a integer literal
            accept_alpha = true;
        }
        
        while file {
            // we can only allow one decimal point in a number, and it cannot be followed consecutively by a second decimal point
            if !(is_digit(file[0]) || (accept_alpha && is_alpha(file[0]))) {
                if file[0] != #char "." || after_dot       break;
                if file.count > 1 && file[1] == #char "."  break;
                after_dot = true;
            }
            str.count += 1;
            advance(lexer);
        }
        
        return str, true;
    }
    return "", true;
}


begins_identifier :: (char: u8) -> bool { return is_alpha(char) || char == #char "_"; }
continues_identifier :: is_alnum;

// returns true if we even start to parse an identifier, not only on success
try_lex_identifier :: (using lexer: *Lexer) -> string {
    if begins_identifier(file[0]) {
        str: string = .{ 1, *file[0] };
        advance(lexer);
        
        while file && continues_identifier(file[0]) {
            str.count += 1;
            advance(lexer);
        }
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


// cycles between skipping whitespace and comments until next character is neither
skip_whitespace_and_comments :: (using t: *Lexer) -> bool {
    if file.count == 0 return false;
    while true {
        while is_whitespace(file[0]) {
            if !advance(t) return false;
        }
        if file[0] == #char "#" {
            while file[0] != #char "\n" {
                if !advance(t) return false;
            }
        }
        else return true;
    }
    return true;
}

is_whitespace :: inline (char: u8) -> bool {
  return char == #char " "
      || char == #char ","
      || char == #char "\t"
      || char == #char "\r"
      || char == #char "\n";
}


#scope_module

advance :: inline (using t: *Lexer, amount := 1) -> bool {
    _amount := min(amount, file.count);
    
    for 0.._amount-1 {
        if file[it] == #char "\n" {
            cursor_location.line_number += 1;
            cursor_location.character_number = 1;
        } else {
            cursor_location.character_number += 1;
        }
    }
    
    file.data  += _amount;
    file.count -= _amount;
    
    return file.count > 0; // return false when we hit EOF
}
