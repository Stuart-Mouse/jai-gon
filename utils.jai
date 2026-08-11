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
    Some conventions to note:
    
    Procedures for skipping whitespace and comments will only return false if an unexpected EOF occurs while inside some kind of block comment.
    This means that the caller still needs to check for EOF after skipping whitespace to see if a safe EOF occurred.
*/

Scanner :: struct {
    /*
        if buffer is not null terminated, then buffer_end points to the last valid character of the buffer + 1
        if buffer is null-terminated, then buffer_end points to the null terminator
    */
    buffer_start, buffer_end: *u8;
    cursor: *u8;
    
    // this is cached so that we don't have to decode it every time get_next_rune() is called.
    next_rune:      u32;
    
    // meaning will depend on the text encoding
    // for UTF8, this is a Unicode_Result
    error_code:     u64;
    
    using location: Source_Code_Location;
    
    text_encoding:  Text_Encoding;
    flags:          Flags;
    
    Text_Encoding :: enum {
        ASCII;
        // LATIN_1;
        UTF8;
        // UTF16;
        // UTF32;
    }
    
    Flags :: enum_flags {
        NONE :: 0;
        NULL_TERMINATED :: 1;
    }
    
    DEFAULT_WHITESPACE_CHARACTERS :: " \t\r\n";
    
    Marker :: struct {
        cursor:     *u8;
        location:   Source_Code_Location;
    }
}

init_scanner :: (scanner: *Scanner, file: string, file_path_for_logging := "", text_encoding := Scanner.Text_Encoding.UTF8) {
    scanner.buffer_start = file.data;
    scanner.buffer_end   = file.data + file.count;
    scanner.location     = .{ file_path_for_logging, 1, 1 };
    
    reset_scanner(scanner);
}

reset_scanner :: (scanner: *Scanner) {
    set_cursor(scanner, scanner.buffer_start);
}

make_scanner :: (file: string, file_path_for_logging := "", text_encoding := Scanner.Text_Encoding.UTF8) -> Scanner {
    scanner: Scanner;
    init_scanner(scanner, text_encoding, file, file_path_for_logging);
    return scanner;
}

buffer_as_cstring :: inline (scanner: *Scanner) -> *u8 {
    assert(scanner.flags & .NULL_TERMINATED);
    return scanner.buffer_start;
}

remaining_as_cstring :: inline (scanner: *Scanner) -> *u8 {
    assert(scanner.flags & .NULL_TERMINATED);
    return scanner.cursor;
}

buffer_as_string :: inline (scanner: *Scanner) -> string {
    return string.{ scanner.buffer_end - scanner.buffer_start, scanner.buffer_start };
}

remaining_as_string :: inline (scanner: *Scanner) -> string {
    return string.{ scanner.buffer_end - scanner.cursor, scanner.cursor };
}

get_bytes_remaining :: inline (scanner: *Scanner) -> int {
    return scanner.buffer_end - scanner.cursor;
}

is_eof :: inline (scanner: *Scanner) -> bool {
    return scanner.cursor == scanner.buffer_end;
}

has_error :: inline (scanner: *Scanner) -> bool {
    return scanner.error_code != 0;
}

get_error_string :: (scanner: *Scanner) -> string {
    if !has_error(scanner)  return "";
    
    if #complete scanner.text_encoding == {
      case .ASCII;
        assert(false, "Scanner had an error code set, but text encoding is ASCII. This should not happen!");
        
      case .UTF8;
        return tprint("utf8 decode error: %", scanner.error_code.(Unicode_Result));
    }
    
    return "";
}

// advances UP TO the desired_amount specified, returns the length in bytes remaining
// advance :: (using scanner: *Scanner, desired_amount := 1) -> bytes_remaining: int {
//     assert(desired_amount >= 0);
//     amount := min(desired_amount, get_bytes_remaining(scanner));
    
//     // TODO: need to make sure that this check for newline is correct in utf8!
//     //       we will probably need to decode each rune as we advance
//     for 0..amount-1 {
//         if (cursor+it).* == "\n" {
//             location.line_number += 1;
//             location.character_number = 1;
//         } else {
//             location.character_number += 1;
//         }
//     }
    
//     set_cursor(scanner, cursor + amount);
//     return get_bytes_remaining(scanner);
// }

advance :: (using scanner: *Scanner, desired_amount := 1) -> bytes_remaining: int, runes_advanced: int {
    assert(desired_amount >= 0);
    
    runes_advanced := 0;
    for 1..desired_amount {
        if is_eof(scanner)  break;
        
        ok, rune, rune_length := decode_next_rune(scanner);
        // TODO: I am not sure how to handle an error here at the moment. 
        //       We should probably not just ignore the error though...
        //       In the case of a utf8 decode error, we should be able to just continue, but this is still not ideal.
        
        if rune == #char "\n" {
            location.line_number += 1;
            location.character_number = 1;
        } else {
            location.character_number += 1;
        }
        
        cursor += rune_length;
        runes_advanced += 1;
    }
    
    decode_next_rune(scanner);
    return get_bytes_remaining(scanner), runes_advanced;
}

set_cursor :: (scanner: *Scanner, cursor: *u8) {
    assert(cursor >= scanner.buffer_start && cursor <= scanner.buffer_end);
    scanner.cursor = cursor;
    decode_next_rune(scanner);
}

// advance_until :: (scanner: *Scanner, $predicate: Code) -> eof: bool {
//     while !is_eof(scanner) {
        
//         if !(#insert predicate) return is_eof(scanner);
//         advance(scanner);
//     }
//     return true;
// }


// TODO: may need to specify encoding of prefix text as well so that we can convert if needed...
begins_with :: (scanner: *Scanner, prefix: string) -> bool {
    return begins_with(remaining_as_string(scanner), prefix);
}

// [start, end)
make_string_from_range :: inline (start: *u8, end: *u8) -> string {
    return string.{ max(end - start, 0), start };
}

get_next_byte :: inline (scanner: *Scanner) -> u8 {
    return ifx !is_eof(scanner) then scanner.cursor.*;
}

get_next_rune :: inline (scanner: *Scanner) -> u32 {
    return scanner.next_rune;
}

// This must be called any time the cursor is moved. Otherwise, callers to get_next_rune() will get the wrong value!
decode_next_rune :: (scanner: *Scanner) -> bool, u32, int {
    if has_error(scanner)  return false, 0, 0;
    
    source_length := 1;
    if scanner.text_encoding == {
      case .ASCII;
        scanner.next_rune = scanner.cursor.*.(u32);
        
      case .UTF8;
        utf8_codepoint, source_length=, utf8_decode_result := character_utf8_to_utf32(scanner.cursor, get_bytes_remaining(scanner));
        scanner.next_rune  = utf8_codepoint;
        scanner.error_code = xx utf8_decode_result;
    }
    
    return !has_error(scanner), scanner.next_rune, source_length;
}

get_marker :: (scanner: Scanner) -> Scanner.Marker {
    return .{ scanner.cursor, scanner.location };
}

// TODO: I don't like that we have to call decode_next_rune in order to include the rune pointed at by cursor, 
//       but it's probably better to do this than to store the current rune length...
substring_from_marker :: (scanner: *Scanner, marker: Scanner.Marker, inclusive := false) -> string, Source_Code_Range {
    end := scanner.cursor;
    if inclusive {
        _, _, len := decode_next_rune(scanner);
        end += len;
    }
    
    substring := make_string_from_range(marker.cursor, scanner.cursor);
    source_range := make_source_code_range(marker.location, scanner.location, !inclusive);
    return substring, source_range;
}

// NOTE: there is no option to include the rune pointed to by 'end' because that would require more complication than is probably worth it.
make_string_from_range :: (start: Scanner.Marker, end: Scanner.Marker) -> string, Source_Code_Range {
    substring := make_string_from_range(start.cursor, end.cursor);
    source_range := make_source_code_range(start.location, end.location, exclusive = true);
    return substring, source_range;
}


set_position_from_marker :: (scanner: *Scanner, marker: Scanner.Marker) -> bool {
    if marker.cursor < scanner.buffer_start || marker.cursor > scanner.buffer_end  return false;
    set_cursor(scanner, marker.cursor);
    scanner.location = marker.location;
    return true;
}

// NOTE: The range is inclusive by default, because we can't know the proper end location a priori if the end character position is 1
//       (since the previous valid character location would be at the end of the previous line, and we don't know how long that line is anymore).
//       Maybe we could just do something hacky like say character number is S64_MAX, but then maybe that creates too much of a weird case for 
//       For now, we just decrement the character number by one and call it a day.
//       This means that the end character number may be zero, which is not typically valid, but at least the user can unambiguously know what this means.
make_source_code_range :: (start: Source_Code_Location, end: Source_Code_Location, exclusive := false) -> Source_Code_Range {
    return .{
        fully_pathed_filename  = start.fully_pathed_filename,
        line_number_start      = start.line_number,
        line_number_end        = end.line_number,
        character_number_start = start.character_number,
        character_number_end   = end.character_number - exclusive.(int),
    };
}


default_begins_identifier :: (char: u8) -> bool { return is_alpha(char) || char == "_"; }
default_continues_identifier :: is_alnum;

default_try_lex_identifier :: (using scanner: *Scanner) -> bool, string {
    if default_begins_identifier(cursor.*) {
        start := cursor;
        while default_continues_identifier(cursor.*) && advance(scanner) {}
        return true, make_string_from_range(start, cursor);
    }
    return true, "";
}

default_is_legal_identifier :: (identifier: string) -> bool {
    if !identifier return false;
    if !default_begins_identifier(identifier[0])  return false;
    for identifier  if !default_continues_identifier(it)  return false;
    return true;
}

default_skip_whitespace :: (using scanner: *Scanner, whitespace_characters := Scanner.DEFAULT_WHITESPACE_CHARACTERS) -> bool {
    while is_any(cursor.*, whitespace_characters) && advance(scanner) { }
    return true;
}

skip_whitespace_and_hashtag_comments :: (using scanner: *Scanner, whitespace_characters := Scanner.DEFAULT_WHITESPACE_CHARACTERS) -> bool {
    while loop := !is_eof(scanner) {
        while is_any(get_next_byte(scanner), whitespace_characters) {
            if !advance(scanner)  break loop;
        }
        if get_next_byte(scanner) == "#" {
            while get_next_byte(scanner) != "\n" {
                if !advance(scanner) return false;
            }
            advance(scanner);
            continue;
        }
        break loop;
    }
    return true;
}

skip_whitespace_and_c_style_comments :: (using scanner: *Scanner, whitespace_characters := Scanner.DEFAULT_WHITESPACE_CHARACTERS) -> bool {
    while loop := !is_eof(scanner) {
        while is_any(get_next_byte(scanner), whitespace_characterss) {
            if !advance(scanner)  break loop;
        }
        if begins_with(scanner, "//") {
            advance(scanner, 2);
            while get_next_byte(scanner) != #char "\n" {
                if !advance(scanner)  break loop;
            }
            advance(scanner);
            continue;
        }
        if begins_with(scanner, "/*") {
            advance(scanner, 2);
            while !begins_with(scanner, "*/") {
                if !advance(scanner) {
                    return false;
                }
            }
            advance(scanner, 2);
            continue;
        }
        break loop;
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
    
    TODO: should probably not have separate procedures for parsing and lexing numbers.
    We should just always parse a number and if we don't care about the actual value for some reason, then we throw it away afterwards.
*/
default_try_lex_number :: (scanner: *Scanner) -> string {
    remaining := get_bytes_remaining(scanner);
    if remaining == 0  return "";
    
    first_char := get_next_byte(scanner);
    
    begins_number := is_digit(first_char);
    if !begins_number && remaining > 1 {
        second_char := (scanner.cursor + 1).*;
        begins_number = (first_char == "+" || first_char == "-" || first_char == ".") && is_digit(second_char);
    }
    if !begins_number  return "";
    
    start := scanner.cursor;
    
    if first_char == "0" && advance(scanner) {
        if get_next_byte(scanner) == {
          case "b"; 
            if advance(scanner) {
                while true {
                    char := get_next_byte(scanner);
                    if !((char == "0" || char == "1" || char == "_") && advance(scanner)) break;
                }
            }
            return make_string_from_range(start, scanner.cursor);
            
          case "h"; #through;
          case "x"; 
            if advance(scanner) {
                while true {
                    char := get_next_byte(scanner);
                    if !((is_hex_digit(char) || char == "_") && advance(scanner)) break;
                }
            }
            return make_string_from_range(start, scanner.cursor);
        }
    }
    
    while true {
        char := get_next_byte(scanner);
        if !((is_digit(char) || char == "_") && advance(scanner)) break;
    }
    
    remaining = get_bytes_remaining(scanner);
    if remaining > 1 {
        first_char = scanner.cursor.*;
        second_char := (scanner.cursor + 1).*;
        
        if first_char == "." && (is_digit(second_char) || second_char == "_") {
            if advance(scanner) {
                while true {
                    char := get_next_byte(scanner);
                    if !((is_digit(char) || char == "_") && advance(scanner)) break;
                }
            }
        }
    }
    
    return make_string_from_range(start, scanner.cursor);
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
    
    _text := text;
    sum: u64 = 0;
    cursor := 0;
    
    parsed_digit := false;
    
    // TODO: We should probably handle other higher bases, such as base32 and base64. Could maybe refer to Odin's implementation for ideas.
    if base == 16 {
        while cursor < _text.count {
            defer cursor += 1;
            c := _text[cursor];
            
            if parsed_digit && c == "_"  continue;
            
            digit: u8 = ---;
            if      is_digit(c)              then digit = c - "0";
            else if (c >= "a") && (c <= "f") then digit = c - "a" + 10;
            else if (c >= "A") && (c <= "F") then digit = c - "A" + 10;
            else                                  break;
            parsed_digit = true;
            
            sum *= base;
            sum += digit.(u64);
        }
    } else {
        while cursor < _text.count {
            defer cursor += 1;
            c := _text[cursor];
            
            if parsed_digit && c == "_"  continue;
            
            if !is_digit(c) break;
            
            digit := c - "0";
            if digit >= base break;
            parsed_digit = true;
            
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
    
    success := parsed_digit;
    if success then advance(*_text, cursor);
    return sum, success, _text;
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

parse_any_number :: (s: string) -> success: bool, number: Any_Number, remainder: string {    
    ok, result_bytes, result_type, remainder := parse_number(s);
    return ok, .{ as_u64 = result_bytes, type = result_type }, remainder;
}

parse_number :: (s: string) -> success: bool, result_bytes: u64, result_type: *Type_Info, remainder: string {    
    if !s {
        log("Error: empty string in parse_number!");
        return false, 0, null, remainder;
    }
    
    // if we've got a decimal point in there, we will prefer float64
    // else we parse and store it as an integer below
    if contains(s, ".") {
        float64_value, ok, remainder := string_to_float64(s);
        if !ok  log("Error: failed to parse float from '%'.", s);
        return ok, (*float64_value).(*u64).*, type_info(float64), remainder;
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
    
    ok, u64_value, remainder := string_to_u64(str, base);
    if !ok {
        log("Error: failed to parse integer from '%'.", s);
        return false, 0, null, remainder;
    }
    
    if negate {
        if u64_value > S64_MAX.(u64) + 1 {
            log("Error: cannot negate parsed u64 value, as it would be out of range for s64.");
            return false, 0, null, remainder;
        }
        s64_value := -(u64_value-1).(s64) - 1;
        return true, (*s64_value).(*u64).*, type_info(s64), remainder;
    } else {
        // use s64 unless u64 value would be out of range
        type := ifx u64_value <= S64_MAX.(u64) then type_info(s64) else type_info(u64);
        return true, ret, type, remainder;
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

