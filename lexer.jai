
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
    
    STRING;
    EXPRESSION;
    
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

init_tokenizer :: (t: *Lexer, file: string = "", script: *LS.Script = null) {
    t.file   = file;
    t.script = script;
    t.cursor_location = .{ line = 1, char = 1 };
    get_token(t);
}

// TODO: stop using lexer to parse path strings
// because of how we are calling into the lead sheets lexer, we can't get back a simple .STRING token normally
// so for now I'm just hacking it to take a hint that we can actually handle an expression
// OR what we could (and probably should do), we could write a little function to hand off the file between a gon and LS lexer
// that way they can just be separate and we just trade back and forth the source location and file string
// but this is actually not nice either...

get_token_or_return :: (using t: *Lexer, code: Code, can_be_expression := false) -> Token #expand {
    token := get_token(t);
    if token.type == .ERROR  `return #insert code;
    return token;
}

get_token :: inline (using t: *Lexer, can_be_expression := false) -> Token {
    if next_token.type == .ERROR {
        log("TOKENIZER ERROR: % (line %, char %)\n", next_token.text, next_token.src_loc.line, next_token.src_loc.char);
        return next_token;
    }
    
    current_token := next_token;
    next_token = lex_next_token(t);
    
    // if we aren't expecting to handle an expression, then try and just get a simple identifier/string
    if current_token.type == .EXPRESSION && !can_be_expression {
        if current_token.expr.node_type == {
          case LS.Node_Literal;
            literal := current_token.expr.(*LS.Node_Literal);
            if literal.literal_type == .STRING {
                current_token.type = .STRING;
                current_token.text = literal.text;
                return current_token;
            }
          case LS.Node_Identifier;
            current_token.type = .STRING;
            current_token.text = current_token.expr.(*LS.Node_Identifier).name;
            return current_token;
        }
        
        current_token.type = .ERROR;
        current_token.text = "Parsed something that looked like an expression when a simple string was expected.";
        return current_token;
    }
    
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

// some helper procs
is_numeric :: inline (char: u8) -> bool {
    return char >= #char "0" && char <= #char "9";
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
      case #char "{";  advance(t);  return .{ type = .OBJECT_BEGIN, text = "{", src_loc = src_loc };
      case #char "}";  advance(t);  return .{ type = .OBJECT_END,   text = "}", src_loc = src_loc };
      case #char "[";  advance(t);  return .{ type = .ARRAY_BEGIN,  text = "[", src_loc = src_loc };
      case #char "]";  advance(t);  return .{ type = .ARRAY_END,    text = "]", src_loc = src_loc };
      case #char ":";  advance(t);  return .{ type = .COLON,        text = ":", src_loc = src_loc };
      case #char ",";  advance(t);  return .{ type = .COMMA,        text = ",", src_loc = src_loc };
    }
    
    // TODO: path tokens here are problematic. we will need this to be enabled only by some flag in the tokenizer
    // tokens only used in path strings, maybe we have a param to skip these when not parsing for a path
    if file[0] == #char "/" {
        advance(t);
        return .{ type = .PATH_SPLIT, text = "", src_loc = src_loc };
    }
    // not very correct, but whatever for now
    if begins_with(file, "..") {
        advance(t, 2);
        return .{ type = .PATH_PARENT, text = "", src_loc = src_loc };
    }
    
    // else defer to lead sheets to parse an expression
    // we pass this expression node back up in the GON token
    if !script {
        // TODO: this is bad, but we need this as a backup since we can't always init lexer with a script
        //       specifically, when its being used to parse path strings
        //       in reality we should not be using the lexer for path strings at all but until I can fix that...
        
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
            return .{ type = .STRING, text = string_value, src_loc = src_loc };
        }
        // unquoted string
        if is_alpha(file[0]) || is_numeric(file[0]) || file[0] == #char "-" || file[0] == #char "_" || file[0] == #char "." {
            string_value := string.{ 0, file.data };
            while is_alpha(file[0]) || is_numeric(file[0]) || file[0] == #char "-" || file[0] == #char "_" || file[0] == #char "." {
                string_value.count += 1;
                if !advance(t)  break;
            }
            return .{ type = .STRING, text = string_value, src_loc = src_loc };
        }
    } else {
        node, cursor := LS.parse_expression(script, file, expect_eof = false);
        if node != null {
            assert(cursor != null);
            advance(t, cursor - file.data);
            return .{ type = .EXPRESSION, expr = node, src_loc = src_loc };
        }
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
