#scope_module

// ========== General ==========

memzero :: (t: *$T) { memset(t, 0, size_of(T)); };

all_bytes_are_zero :: (any: Any) -> bool {
    return all_bytes_are_zero(any.value_pointer, any.type.runtime_size);
}

// TODO: could be much more efficient
all_bytes_are_zero :: (data: *void, count: int) -> bool {
    ptr := data.(*u8);
    end := ptr + count;
    while ptr < end {
        if ptr.*  return false;
        ptr += 1;
    }
    return true;
}

// ========== Scanner ==========

/*
    The scanner is provided as a basic primitive for the other languages to implement a lexer on top of. 
    Of course not all languages have to use this scanner, it's just included here so I don't have to duplicate tons of similar logic for the lexers I implement.
*/

Scanner :: struct {
    file: string;
    using location: Source_Code_Location;
}

init_scanner :: (scanner: *Scanner, file: string, file_path: string) {
    scanner.file     = file;
    scanner.location = .{ file_path, 1, 1 };
}

make_scanner :: (file: string, file_path: string) -> Scanner {
    scanner: Scanner;
    init_scanner(scanner, file, file_path);
    return scanner;
}

// advances UP TO the amount specified, returns false on EOF
advance :: inline (using scanner: *Scanner, amount := 1) -> bool {
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


default_begins_identifier :: (char: u8) -> bool { return is_alpha(char) || char == "_"; }
default_continues_identifier :: is_alnum;

default_try_lex_identifier :: (using scanner: *Scanner) -> bool, string {
    if default_begins_identifier(file[0]) {
        str: string = .{ 1, *file[0] };
        while default_continues_identifier(file[0]) && advance(scanner) {}
        str.count = file.data - str.data;
        return true, str;
    }
    return true, "";
}

default_is_legal_identifier :: (str: string) -> bool {
    if !str return false;
    if !default_begins_identifier(str[0])  return false;
    for str  if !default_continues_identifier(it)  return false;
    return true;
}

skip_whitespace_and_hashtag_comments :: (using scanner: *Scanner) -> bool {
    if file.count == 0 return false;
    while true {
        while is_any(file[0], whitespace_chars) {
            if !advance(scanner) return false;
        }
        if file[0] == "#" {
            while file[0] != "\n" {
                if !advance(scanner) return false;
            }
        }
        else return true;
    }
    return true;
}

skip_whitespace_and_c_style_comments :: (using scanner: *Scanner) -> bool {
    if file.count == 0  return true;
    
    while loop := file.count > 0 {
        while is_any(file[0], whitespace_chars) {
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


/*
    NOTE:
        permits a leading '-' or '+' for sign
        currently does not report any kind of unexpected EOF or unexpected character error if a number suddenyl ends after some base specifier digit or a decimal point
            this appears to be how Jai lexes things, so I've copied that behaviour for consistency
            (although, jai does seem to make an exception for 0h hex floats, which will report an error if not followed by some hex digits. This is presumably because these numbers cannot be of an arbitrary length (must be 4, 8, or 16 digits) and so are parsed more rigorously)
        permits underscores anywhere in a number (except as first character, obviously), including directly after the decimal point
        
    TODO:
        handle underscores
            only in int? or float also? copy what jai permits
        maybe remove handling for sign, let caller handle if they wish
        probably just return empty string on error and no second bool return
            see what jai does when we have some weird thing like number ending with dot and no following digits
        
*/
default_try_lex_number :: (using scanner: *Scanner) -> string {
    if file && (is_digit(file[0]) || (file.count > 1 && (file[0] == "+" || file[0] == "-" || file[0] == ".") && is_digit(file[1]))) {
        text := string.{ 0, file.data };
        
        if file[0] == "0" && advance(scanner) {
            if file[0] == {
              case "b"; 
                if advance(scanner) {
                    while (file[0] == "0" || file[0] == "1" || file[0] == "_") && advance(scanner) {}
                }
                text.count = file.data - text.data;
                return text;                
                
              case "h"; #through;
              case "x"; 
                if advance(scanner) {
                    while (is_hex_digit(file[0]) || file[0] == "_") && advance(scanner) {}
                }
                text.count = file.data - text.data;
                return text;
            }
        }
        
        while (is_digit(file[0]) || file[0] == "_") && advance(scanner) {};
        
        if file.count > 1 && file[0] == "." && (is_digit(file[1]) || file[1] == "_") {
            if advance(scanner) {
                while (is_digit(file[0]) || file[0] == "_") && advance(scanner) {};
            }
        }
        
        text.count = file.data - text.data;
        return text;
    }
    return "";
}


// ========== Escape Sequences ==========

parse_escape_sequence :: (str: string, quote_char: u8 = "\"") -> (success: bool, result: string, input_sequence_length: int) #expand {
    success, result_buffer, result_length, input_sequence_length := parse_escape_sequence_to_buffer(str, quote_char);
    return success, string.{ result_length, result_buffer.data }, input_sequence_length;
}

parse_escape_sequence_to_buffer :: (str: string, quote_character: u8 = "\"") -> (success: bool, result_buffer: [8] u8, result_length: int, input_sequence_length: int) {
    result_buffer: [8] u8;
    
    if str.count < 2 || str[0] != "\\" {
        return false, result_buffer, 0, 0;
    }
    
    if str[1] == quote_character {
        result_buffer[0] = quote_character;
        return true, result_buffer, 1, 2;
    }
    
    if str[1] == {
      case "e";   
        result_buffer[0] = #char "\e";
        return true, result_buffer, 1, 2;
      case "n";   
        result_buffer[0] = #char "\n";
        return true, result_buffer, 1, 2;
      case "r";   
        result_buffer[0] = #char "\r";
        return true, result_buffer, 1, 2;
      case "t";   
        result_buffer[0] = #char "\t";
        return true, result_buffer, 1, 2;
      case "0";   
        result_buffer[0] = #char "\0";
        return true, result_buffer, 1, 2;
      case "\\";  
        result_buffer[0] = #char "\\";
        return true, result_buffer, 1, 2;
        
      case "x";
        if str.count < 4 {
            log("Error: unexpected EOF in hexadecimal escape sequence: '%'", str);
            return false, result_buffer, 0, 0;
        }
        to_convert := slice(str, 2, 2);
        ok, written := ascii_hex_to_bytes(result_buffer, to_convert);
        if !(ok && written == 2) {
            log("Error: Failed to convert ascii hex sequence to bytes: '%'", to_convert);
            return false, result_buffer, 0, 0;
        }
        return true, result_buffer, 2, 6;
        
      case "d";
        if str.count < 5 {
            log("Error: unexpected EOF in decimal escape sequence: '%'", str);
            return false, result_buffer, 0, 0;
        }
        value, ok, remainder := string_to_u64(slice(str, 2, 3));
        if !ok || remainder {
            log("Error: invalid decimal escape sequence: '%'", str);
            return false, result_buffer, 0, 0;
        }
        if value > 255 {
            log("Error: value of decimal escape sequence cannot be greater than 255: '%'", str);
            return false, result_buffer, 0, 0;
        }
        result_buffer[0] = value.(u8);
        return true, result_buffer, 1, 5;
        
      case "u";
        if str.count < 6 {
            log("Error: unexpected EOF in 16-bit unicode escape sequence: '%'", str);
            return false, result_buffer, 0, 0;
        }
        to_convert := slice(str, 2, 4);
        ok, written := ascii_hex_to_bytes(result_buffer, to_convert);
        if !(ok && written == 2) {
            log("Error: Failed to convert ascii hex sequence to bytes: '%'", to_convert);
            return false, result_buffer, 0, 0;
        }
        return true, result_buffer, 2, 6;
        
      case "U";
        if str.count < 10 {
            log("Error: unexpected EOF in 32-bit unicode escape sequence: '%'", str);
            return false, result_buffer, 0, 0;
        }
        to_convert := slice(str, 2, 8);
        ok, written := ascii_hex_to_bytes(result_buffer, to_convert);
        if !(ok && written == 4) {
            log("Error: Failed to convert ascii hex sequence to bytes: '%'", to_convert);
            return false, result_buffer, 0, 0;
        }
        return true, result_buffer, 4, 6;
    }
    
    log("Error: invalid escape sequence beginning with: '%'", slice(str, 0, 2));
    return false, result_buffer, 0, 0;
}

parse_escape_sequence :: (scanner: *Scanner) -> value: string, success: bool {
    ok, value, len := parse_escape_sequence(scanner.file);
    if ok  advance(scanner, len);
    return value, ok;
}

unescape_string :: (builder: *String_Builder, text: string, quote_char: u8 = "\"") -> bool {
    _text := text;
    while _text {
        if _text[0] == "\\" {
            ok, str, len := parse_escape_sequence(_text, quote_char);
            if !ok  return false;
            append(builder, str);
            advance(*_text, len);
        } else {
            append(builder, _text[0]);
            advance(*_text, 1);
        }
    }
    return true;
}

unescape_string :: (text: string) -> string, bool {
    builder: String_Builder;
    ok := unescape_string(*builder, text);
    if !ok {
        free_buffers(*builder);
        return "", false;
    }
    return builder_to_string(*builder), true;
}

escape_string :: (builder: *String_Builder, text: string, quote_char: u8 = "\"") -> bool {
    if !text  return true;
    
    // for text {
    for :utf8_iter text {
        if it == {
          case #char "\e";  append(builder, "\\e");  continue;
          case #char "\n";  append(builder, "\\n");  continue;
          case #char "\r";  append(builder, "\\r");  continue;
          case #char "\t";  append(builder, "\\t");  continue;
          case #char "\0";  append(builder, "\\0");  continue;
          case #char "\\";  append(builder, "\\\\"); continue;
        }
        
        if it == quote_char {
            buf := u8.[ "\\", quote_char ];
            append(builder, xx buf);
            continue;
        }
        
        // if outside of printable ascii range, append as hex escape sequence
        if it < 0x20 || it == 0x7f {
            append(builder, "\\x");
            append(builder, byte_to_ascii_hex(it.(u8)).(string));
            continue;
        }
        
        // TODO: append only "printable" utf8 characters as-is, without escaping
        //       may have to consult what Go considers to be the printable subset of utf8
        // TODO: also figure out how to properly convert utf32 value back into \u or \U codepoint if not printable
        //       I think this will require reversing the byte order before doing bytes_to_asii_hex
        buffer: [8] u8;
        str := string.{ 0, buffer.data };
        character_utf32_to_utf8(it, *str);
        append(builder, str);
    }
    
    return true;
}

escape_string :: (text: string) -> string, bool {
    builder: String_Builder;
    ok := escape_string(*builder, text);
    if !ok {
        free_buffers(*builder);
        return "", false;
    }
    return builder_to_string(*builder), true;
}


// ========== Number Parsing ==========

/*
    string_to_u64 and parse_number are primarily written for use with Convert.jai, 
    but I don't really want to put them in that module right now since they're just a little too general.
    At the very least, they probably won't stay in this file forever...
    
    Instead of using a polymorphic procedure like string_to_int, we parse to u64 as our fundamental integer type 
    and then do whatever we need to do to downcast in the calling procedure. I think this approach makes 
    more sense in this module since the dst type for the integer is probably not statically known anyhow.
        
    Note that we do not have any special procedures in this module for string_to_float, 
    since there's no point in not just using what's provided in string_to_float.jai.
    
    See parse_number below this to see how this procedure is used in context, and how we then downcast to the other integer types.
*/

string_to_u64 :: (text: string, base: u64 = 10) -> result: u64, success: bool, remainder: string {
    assert(base == 16 || base <= 10);
    if !text  return 0, false, "";
    
    s := text;
    sum: u64 = 0;
    cursor := 0;
    
    if base == 16 {
        while cursor < s.count {
            defer cursor += 1;
            c := s[cursor];
            if c == "_"  continue;

            digit: u8 = ---;
            if is_digit(c) {
                digit = c - "0";
            } else if (c >= "a") && (c <= "f") {
                digit = c - "a" + 10;
            } else if (c >= "A") && (c <= "F") {
                digit = c - "A" + 10;
            } else {
                break;
            }
            
            sum *= base;
            sum += digit.(u64);
        }
    } else {
        while cursor < s.count {
            defer cursor += 1;
            c := s[cursor];
            if c == "_"  continue;

            if !is_digit(c) break;
            
            digit := c - "0";
            if digit >= base break;
            
            prev := sum;
            
            #no_aoc {
                sum *= base; 
                sum += digit.(u64);
            }
            
            if sum < prev {
                log("Error: arithmetic overflow in string_to_u64!");
                return 0, false, "";
            }
        }
    }
    
    success := (cursor != 0);
    advance(*s, cursor);
    
    return sum, success, s;
}


/*
    The result of parse_number will always be either float64, u64, or s64
        float64 is used if the input string contains a dot
        s64 will be used as the default integer type
        u64 will be used only if the u64 value parsed by string_to_u64 would not fit inside of an s64
    
    Note to self: 
        Convert.jai has its own more constrained version (string_to_int) and a more general use case set_value_from_string procedure.
        I see this procedure as being most useful for parsers like GON or Lead Sheets, where you really need the Any_Number as an intermediate value for an expented period of time.
    
    TODO: support octal numbers
    TODO: support hexadecimal floats
*/
parse_number :: (s: string) -> result: Any_Number, success: bool, remainder: string {    
    if !s {
        log("Error: empty string in parse_number!");
        return .{}, false, "";
    }
    
    // if we've got a decimal point in there, we will prefer float64
    // else we parse and store it as an integer below
    if contains(s, ".") {
        val, ok, remainder := string_to_float64(s);
        if !ok  log("Error: failed to parse float from '%'.", s);
        return Any_Number.from(val), ok, remainder;
    }
    
    str := s;
    
    negate := false;
    if str && str[0] == "-" {
        negate = true;
        advance(*str, 1);
    }
    
    base: u64 = 10;
    if str[0] == "0" && str.count >= 2 {
        if str[1] == {
          case "b"; 
            advance(*str, 2);
            base = 2;
            
          case "x"; 
            advance(*str, 2);
            base = 16;
            
          // case "h";
          //   advance(*str, 2);
          //   base = 16;
          //   is_hex_float = true;
          //   // verify that input string is exactly 4, 8, or 16 characters
        }
    }
    
    u64_value, ok, remainder := string_to_u64(str, base);
    if !ok {
        log("Error: failed to parse integer from '%'.", s);
        return .{}, false, remainder;
    }
    
    if negate {
        if u64_value > S64_MAX.(u64) + 1 {
            log("Error: cannot negate parsed u64 value, as it would be out of range for s64.");
            return .{}, false, remainder;
        }
        s64_value := -(u64_value-1).(s64) - 1;
        return Any_Number.from(s64_value), true, remainder;
    } else {
        // use s64 unless u64 value would be out of range
        ret := Any_Number.from(u64_value);
        if u64_value <= S64_MAX.(u64) then ret.__type = s64;
        return ret, true, remainder;
    }
}


// ========== ASCII Hexadecimal to Binary Conversions ==========

is_hex_digit :: (c: u8) -> bool {
    return c >= "0" && c <= "9"
        || c >= "a" && c <= "f"
        || c >= "A" && c <= "F";
}

// success indicator is intentionally the second return here, since in very many cases people will want to ignore it
ascii_hex_char_to_byte :: (c: u8) -> u8, bool {
    if c >= "0" && c <= "9" then return  c - "0", true;
    if c >= "A" && c <= "F" then return (c - "A") + 10, true;
    if c >= "a" && c <= "f" then return (c - "a") + 10, true;
    return 0, false;
}

ascii_hex_to_bytes :: (dst: [] u8, src: string, big_endian := false) -> success: bool, bytes_written: int {
    assert(src.count & 1 == 0, "src string passed to ascii_hex_to_bytes must have an even number of characters!");
    
    if dst.count < src.count  return false, 0;
    
    src_ptr := src.data;
    
    output_size := src.count / 2;
    
    dst_ptr, end_ptr:   *u8;
    dst_ptr_increment:  int;
    
    if big_endian {
        dst_ptr = dst.data;
        end_ptr = dst.data + output_size;
        dst_ptr_increment = 1;
    } else {
        dst_ptr = dst.data + output_size - 1;
        end_ptr = dst.data - 1;
        dst_ptr_increment = -1;
    }
    
    while dst_ptr != end_ptr {
        upper_nibble, ok := ascii_hex_char_to_byte((src_ptr).*);
        if !ok  return false, 0;
        
        lower_nibble:, ok = ascii_hex_char_to_byte((src_ptr+1).*);
        if !ok  return false, 0;
        
        dst_ptr.* = (upper_nibble << 4) | (lower_nibble);
        
        src_ptr += 2;
        dst_ptr += dst_ptr_increment;
    }
    
    return true, output_size;
}

ASCII_HEX_NIBBLES :: "0123456789ABCDEF";

byte_to_ascii_hex :: inline (byte: u8) -> [2] u8 {
    return .[
        ASCII_HEX_NIBBLES[0x0F & (byte >> 4)],
        ASCII_HEX_NIBBLES[0x0F &  byte      ],
    ];
}

// dst buffer must be at least large enough for the src data
bytes_to_ascii_hex :: (dst: [] u8, src: string) -> (bytes_written: int) {   
    output_size := src.count * 2;
    if output_size > dst.count  return -1;
    
    src_char, dst_char: *u8;
    while dst_i < dst.data + output_size {
        dst[dst_i    ] = nibble_to_ascii_hex[0x0F & (src[src_i] >> 4)];
        dst[dst_i + 1] = nibble_to_ascii_hex[0x0F &  src[src_i]      ];
        
        src_char += 1;
        dst_char += 2;
    }
    return output_size;
}

