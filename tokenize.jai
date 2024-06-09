
whitespace_chars :: " ,\t\r\n\0";
reserved_chars   :: "~!@#$%^&*{}[]\"";
whitespace_and_reserved_chars :: " ,\t\r\n#{}[]\"\0";

Token :: struct {
    type : Token_Type;
    text : string;
}

Token_Type :: enum u8 {
    INVALID;
    STRING;
    OBJECT_BEGIN;
    OBJECT_END;
    ARRAY_BEGIN;
    ARRAY_END;
    REF_INDEX;
    REF_POINTER;
    REF_VALUE;
    PATH_SPLIT;
    PATH_HERE;
    PATH_PARENT;
    EOF;
}

Tokenizer :: struct {
    file       : string;
    next_token : Token;
}


consume_token :: (using t: *Tokenizer) -> bool {
    if next_token.type == .EOF  return true;
    ok: bool;
    next_token, ok = lex_next_token(*file);
    return ok;
}

get_token :: (using t: *Tokenizer) -> (Token, bool) {
    current_token := next_token;
    return current_token, consume_token(t);
}

peek_token :: (using t: *Tokenizer) -> Token {
    return next_token;
}

// mutates the passed string, advancing it to the position after the returned token
lex_next_token :: (file: *string) -> (Token, bool) {
    if file.count <= 0                      return .{ .EOF, "" }, true;
    if !skip_whitespace_and_comments(file)  return .{ .EOF, "" }, true;
    
    // single character tokens
    if file.*[0] == {
        case #char "{";
            advance(file);
            return .{.OBJECT_BEGIN, ""}, true;
        case #char "}";
            advance(file);
            return .{.OBJECT_END,   ""}, true;
        case #char "[";
            advance(file);
            return .{.ARRAY_BEGIN,  ""}, true;
        case #char "]";
            advance(file);
            return .{.ARRAY_END,    ""}, true;
        case #char "&";
            advance(file);
            return .{.REF_INDEX,    ""}, true;
        case #char "*";
            advance(file);
            return .{.REF_POINTER,  ""}, true;
        case #char "$";
            advance(file);
            return .{.REF_VALUE,    ""}, true;
    }
    
    // some helper procs
    is_numeric :: inline (char: u8) -> bool {
        return char >= #char "0" && char <=#char "9";
    }
    
    is_alpha :: inline (char: u8) -> bool {
        return (char >= #char "a" && char <=#char "z" ) || (char >= #char "A" && char <= #char "Z");
    }
    
    // tokens only used in path strings, maybe we have a param to skip these when not parsing for a path
    if file.*[0] == #char "/" {
        advance(file);
        return .{ .PATH_SPLIT, "" }, true;
    }
    
    // not very correct, but whatever for now
    if file.*[0] == #char "." {
        if advance(file) && file.*[0] == #char "." {
            advance(file);
            return .{.PATH_PARENT, ""}, true;
        }
    }
    
    // string
    if file.*[0] == #char "\"" || file.*[0] == #char "'" || file.*[0] == #char "`"{ 
        quote_char := file.*[0];
        
        if !advance(file)  return .{ .EOF, "" }, false;
        string_value: string = ---;
        string_value.data  = file.data;
        string_value.count = 0;
        
        while file.*[0] != quote_char {
            // TODO: handle escape sequences more properly
            adv := 1 + cast(int) (file.*[0] == #char "\\"); 
            string_value.count += adv;
            if !advance(file, adv)  
                return .{ .EOF, "" }, false;
        }
        advance(file);
        
        return .{ .STRING, string_value }, true;
    }
    
    // unquoted string
    if is_alpha(file.*[0]) || is_numeric(file.*[0]) || file.*[0] == #char "-" || file.*[0] == #char "_" || file.*[0] == #char "." {
        string_value: string = ---;
        string_value.data = file.data;
        string_value.count = 0;
        
        while is_alpha(file.*[0]) || is_numeric(file.*[0]) || file.*[0] == #char "-" || file.*[0] == #char "_" || file.*[0] == #char "." {
            string_value.count += 1;
            if !advance(file)  break;
        }
        
        return .{ .STRING, string_value }, true;
    }
    
    // next_whitespace_char := (file*, whitespace_chars);
    invalid_token_str := file.*;
    log("Invalid token '%' encountered.\n", invalid_token_str);
    return .{ .INVALID, "" }, false;
}

// bascially wraps our slice operation so that we can handle an error in the case that we run out of characters
advance :: inline (file: *string, amount := 1) -> bool {
    _amount := min(amount, file.count);
    file.data  += _amount;
    file.count -= _amount;
    return file.count > 0;
}

is_whitespace :: inline (char: u8) -> bool {
    return char == #char " "  || 
           char == #char ","  || 
           char == #char "\t" || 
           char == #char "\r" || 
           char == #char "\n" ;
}

// returns false when hitting EOF
skip_whitespace_and_comments :: (file: *string) -> bool {
    while true {
        while is_whitespace(file.*[0]) {
            if !advance(file)  return false;
        }
        if file.*[0] == #char "#" {
            while file.*[0] != #char "\n" {
                if !advance(file)  return false;
            }
            continue;
        }
        return true;
    }
}