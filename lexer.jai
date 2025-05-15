
whitespace_chars :: " \t\r\n\0";
reserved_chars   :: "~!@#$%^&:*{}[]()\"";
whitespace_and_reserved_chars :: #run join(whitespace_chars, reserved_chars);

Token :: struct {
    type:       Token_Type;
    text:       string;
    location:   Source_Code_Location;
}

Token_Type :: enum u8 {
    EOF;
    ERROR;
    
    STRING;
    
    OBJECT_BEGIN;
    OBJECT_END;
    ARRAY_BEGIN;
    ARRAY_END;
    
    // REF_INDEX;
    // REF_POINTER;
    // REF_VALUE;
}

Lexer :: struct {
    file:               string;
    next_token:         Token;
    cursor_location:    Source_Code_Location;
}

init_tokenizer :: (using t: *Lexer, filepath := "") {
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

// mutates the passed string, advancing it to the position after the returned token
lex_next_token :: (using t: *Lexer) -> Token {
    if !skip_whitespace_and_comments(t)  return .{ type = .EOF };
    
    location := cursor_location;
    make_error_token :: (error_string: string = "") -> Token #expand { 
        return .{ type = .ERROR, location = location, text = error_string }; 
    }
    
    // single character tokens
    if file[0] == {
      case #char "{";  advance(t);  return .{ .OBJECT_BEGIN, "{", location };
      case #char "}";  advance(t);  return .{ .OBJECT_END,   "}", location };
      case #char "[";  advance(t);  return .{ .ARRAY_BEGIN,  "[", location };
      case #char "]";  advance(t);  return .{ .ARRAY_END,    "]", location };
      // case #char "&";  advance(t);  return .{ .REF_INDEX,    "&", location };
      // case #char "*";  advance(t);  return .{ .REF_POINTER,  "*", location };
      // case #char "$";  advance(t);  return .{ .REF_VALUE,    "$", location };
    }
    
    // string
    if file[0] == #char "\"" || file[0] == #char "'" || file[0] == #char "`" { 
        quote_char := file[0];
        
        if !advance(t)  return make_error_token("Unexpected EOF while parsing string.");
        string_value := string.{ 0, file.data };
        
        while file[0] != quote_char {
            // TODO: handle escape sequences more properly
            adv := 1 + (file[0] == #char "\\").(int); 
            string_value.count += adv;
            if !advance(t, adv)  return make_error_token("Unexpected EOF while parsing string.");
        }
        advance(t);
        
        return .{ .STRING, string_value, location };
    }
    
    // unquoted string
    if is_alnum(file[0]) || file[0] == #char "-" || file[0] == #char "_" || file[0] == #char "." {
        string_value := string.{ 0, file.data };
        
        while is_alnum(file[0]) || file[0] == #char "-" || file[0] == #char "_" || file[0] == #char "." {
            string_value.count += 1;
            if !advance(t)  break;
        }
        
        return .{ .STRING, string_value, location };
    }
    
    return make_error_token("Unexpected character encountered.");
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
