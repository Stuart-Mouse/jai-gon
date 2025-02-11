
whitespace_chars :: " \t\r\n\0";
reserved_chars   :: "~!@#$%^&:*{}[]()\"";
whitespace_and_reserved_chars :: #run join(whitespace_chars, reserved_chars);

Token :: struct {
    type:       Token_Type;
    union {
        text:   string;
        expr:   *LS.Node;
    }
    src_loc:    Source_Location;
}

Token_Type :: enum u8 {
    EOF             :: 0;
    ERROR           :: 1;
    
    OBJECT_BEGIN;
    OBJECT_END;
    ARRAY_BEGIN;
    ARRAY_END;
    
    VALUE_EXPR;
    
    COMMA;
    COLON;
    
    PATH_SPLIT;
    PATH_HERE;
    PATH_PARENT;
}

Source_Location :: struct {
    line, char: int;
}

Lexer :: struct {
    file:               string;
    next_token:         Token;
    cursor_location:    Source_Location;
    
    script:             *LS.Script;
}

init_tokenizer :: (using t: *Lexer) {
    cursor_location = .{ line = 1, char = 1 };
    get_token(t);
}

get_token_or_return :: (using t: *Lexer, code: Code) -> Token #expand {
    token := get_token(t);
    if token.type == .ERROR  `return #insert code;
    return token;
}

get_token :: inline (using t: *Lexer) -> Token {
    if next_token.type == .ERROR {
        log("TOKENIZER ERROR: % (line %, char %)\n", next_token.text, next_token.src_loc.line, next_token.src_loc.char);
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

// mutates the passed string, advancing it to the position after the returned token
lex_next_token :: (using t: *Lexer) -> Token {
    if !skip_whitespace_and_comments(t)  return .{ type = .EOF };
    
    src_loc := cursor_location;
    make_error_token :: (error_string: string = "") -> Token #expand { 
        return .{ type = .ERROR, src_loc = src_loc, text = error_string }; 
    }
    
    // single character tokens, structural
    if file[0] == {
      case #char "{";  advance(t);  return .{ .OBJECT_BEGIN, "{", src_loc };
      case #char "}";  advance(t);  return .{ .OBJECT_END,   "}", src_loc };
      case #char "[";  advance(t);  return .{ .ARRAY_BEGIN,  "[", src_loc };
      case #char "]";  advance(t);  return .{ .ARRAY_END,    "]", src_loc };
      case #char ":";  advance(t);  return .{ .COLON,        ":", src_loc };
      case #char ",";  advance(t);  return .{ .COMMA,        ",", src_loc };
    }
    
    // TODO: path tokens here are problematic. we will need this to be enabled only by some flag in the tokenizer
    // tokens only used in path strings, maybe we have a param to skip these when not parsing for a path
    if file[0] == #char "/" {
        advance(t);
        return .{ .PATH_SPLIT, "", src_loc };
    }
    // not very correct, but whatever for now
    if begins_with(file, "..") {
        advance(t, 2);
        return .{ .PATH_PARENT, "", src_loc };
    }
    
    // TODO: add back in identifier and string cases?
    //       or should we just pull those out in below?
    
    
    // else defer to lead sheets to parse an expression
    // we pass this expression node back up in the GON token
    node, ok := LS.parse_expression(script, file, expect_eof = false);
    if ok {
        if node == null  return make_error_token("Node returned by LS.parse_expression was null.");
        return .{ .VALUE_EXPR, node };
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
      || char == #char "\t"
      || char == #char "\r"
      || char == #char "\n";
}


#scope_module

advance :: inline (using t: *Lexer, amount := 1) -> bool {
    _amount := min(amount, file.count);
    
    for 0.._amount-1 {
        if file[it] == #char "\n" {
            cursor_location.line += 1;
            cursor_location.char  = 1;
        } else {
            cursor_location.char += 1;
        }
    }
    
    file.data  += _amount;
    file.count -= _amount;
    
    return file.count > 0; // return false when we hit EOF
}
