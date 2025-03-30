/*
    NOTE:
    
    Due to the need to reference the LS script and the lack of need for any sort of look-ahead on the lexer, 
    the lexer has just been removed and what was left of it (just file and cursor_location) have been moved into the parser itself.
    
    Lexing here is a bit weird because GON is dead simple, but we complicate it by introducing Lead Sheets expressions, which are just considered a token in GON.
    Before we even lex the next token, we know whether we expect a field name or value (identifier or expression),
        so instead of going to Lead Sheets to parse identifiers, we just do that here.
    We could just catch the parsed expression before returning it and verify that it's just a simple identifier, 
        but why even go to the extra trouble y'know? Except that now we've duplicated the identifier parsing logic.
    But, then there's also the additional wrinkle that we want to allow basically any string to be an identifier in GON.
    This is already sort of supported by Lead Sheets with backticked strings, but it's nicer if we can just use standard quotation marks around string-y field names.
    Also, we occasionally use integers as field names in GON, for indexed arrays (which are formatted as GON objects with the child fields having integers for names). 
        But this cannot be checked until later, so...
    
    Basically all this to say that GON lexing is weird with lead sheets right now and the rules about GON field names are weird too.
*/

whitespace_chars :: " \t\r\n\0";
reserved_chars   :: "~!@#$%^&:*{}[]()\"";
whitespace_and_reserved_chars :: #run join(whitespace_chars, reserved_chars);

Token :: struct {
    type:       Token_Type;
    union {
        text:   string;
        expr:   *LS.Node;
    }
    location:    Source_Location;
}

Token_Type :: enum u8 {
    EOF             :: 0;
    ERROR           :: 1;
    
    OBJECT_BEGIN;
    OBJECT_END;
    ARRAY_BEGIN;
    ARRAY_END;
    
    STRING;         // TODO: maybe this should be IDENTIFIER instead?
    EXPRESSION;
    
    COMMA;
    COLON;
}

Source_Location :: struct {
    line, char: int;
}

// some helper procs
is_numeric :: inline (char: u8) -> bool {
    return char >= #char "0" && char <= #char "9";
}

// mutates the passed string, advancing it to the position after the returned token
lex_next_token :: (using parser: *Parser, expect_expression := false) -> Token {
    ok := skip_whitespace_and_comments(parser);
    
    location := cursor_location;
    make_error_token :: (error_string: string = "") -> Token #expand { 
        return .{ type = .ERROR, location = location, text = error_string }; 
    }
    
    if !ok    return make_error_token("Error: unexpected EOF in the middle of a comment!");
    if !file  return .{ type = .EOF, location = cursor_location };
    
    // single character tokens, structural
    if file[0] == {
      case #char "{";  advance(parser);  return .{ type = .OBJECT_BEGIN, text = "{", location = location };
      case #char "}";  advance(parser);  return .{ type = .OBJECT_END,   text = "}", location = location };
      case #char "[";  advance(parser);  return .{ type = .ARRAY_BEGIN,  text = "[", location = location };
      case #char "]";  advance(parser);  return .{ type = .ARRAY_END,    text = "]", location = location };
      case #char ":";  advance(parser);  return .{ type = .COLON,        text = ":", location = location };
      case #char ",";  advance(parser);  return .{ type = .COMMA,        text = ",", location = location };
    }
    
    if expect_expression {
        node, cursor := LS.parse_expression(*script, file, expect_eof = false);
        if node != null {
            assert(cursor != null);
            advance(parser, cursor - file.data);
            return .{ type = .EXPRESSION, expr = node, location = location };
        }
    } else {
        // parse a field name
        
        // with quotes
        if file[0] == #char "\"" || file[0] == #char "'" || file[0] == #char "`" { 
            quote_char := file[0];
            if !advance(parser)  return make_error_token("Unexpected EOF while parsing string.");
            string_value := string.{ 0, file.data };
            while file[0] != quote_char {
                // TODO: handle escape sequences more properly
                advance_count := 1 + (file[0] == #char "\\").(int); 
                string_value.count += advance_count;
                if !advance(parser, advance_count)  return make_error_token("Unexpected EOF while parsing string.");
            }
            advance(parser);
            return .{ type = .STRING, text = string_value, location = location };
        }
        
        // without quotes
        if is_alpha(file[0]) || is_numeric(file[0]) || file[0] == #char "-" || file[0] == #char "_" || file[0] == #char "." {
            string_value := string.{ 0, file.data };
            while is_alpha(file[0]) || is_numeric(file[0]) || file[0] == #char "-" || file[0] == #char "_" || file[0] == #char "." {
                string_value.count += 1;
                if !advance(parser)  break;
            }
            return .{ type = .STRING, text = string_value, location = location };
        }
    }
    
    return make_error_token("Unexpected character encountered.");
}


// cycles between skipping whitespace and comments until next character is neither
skip_whitespace_and_comments :: (using parser: *Parser) -> bool {
    if file.count == 0  return true;
    while loop := true {
        while is_whitespace(file[0]) {
            if !advance(parser)  break;
        }
        if begins_with(file, "//") {
            advance(parser, 2);
            while file[0] != #char "\n" {
                if !advance(parser)  return true;
            }
            advance(parser);
        }
        else if begins_with(file, "/*") {
            advance(parser, 2);
            while !begins_with(file, "*/") {
                if !advance(parser)  return false;
            }
            advance(parser, 2);
        }
        else break;
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

advance :: inline (using parser: *Parser, amount := 1) -> bool {
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
