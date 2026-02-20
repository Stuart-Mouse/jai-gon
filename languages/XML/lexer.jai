

// lex_next_token :: (using lexer: *XML_Lexer) -> XML_Token {
//     trivia, ok := xml_skip_whitespace_and_comments(*script.lexer);
//     if !ok    return make_error_token("Unexpected EOF in the middle of a comment", lexer.location);
//     if !file  return .{ type = .EOF, location = location };
    
//     token_location := lexer.location;
    
//     return_error :: (message: string = "") #expand { `return .{ .ERROR, message, token_location }; }
    
//     // convenience macro for short tokens
//     make_token :: (type: Token_Type, len: int) -> Token #expand {
//         defer advance(*script.lexer, len);
//         return .{
//             type       = type,
//             text       = slice(file, 0, len),
//             location   = token_location,
//             preceding_whitespace = preceding_whitespace, 
//         };
//     }
    
//     // single character tokens
//     if file[0] == {
//       case "<";  advance(lexer);  return make_token(.TAG_BEGIN);
//       case ">";  advance(lexer);  return make_token(.TAG_END);
//       case "=";  advance(lexer);  return make_token(.EQAULS);
//     }
    
//     if file.count >= 2 {
//         if slice(file, 0, 2) == {
//           case "</"; return make_token(.CLOSING_TAG_BEGIN, 2);
//           case "\>"; return make_token(.CLOSING_TAG_END, 2);
//         }
//     }
    
//     // try lexing a number
//     {
//         ok, text := lexer.try_lex_number(lexer);
//         if !ok   return_error(text);
//         if text  return .{ .NUMBER, text, token_location };
//     }
    
//     // try lexing an identifier
//     {
//         ok, text := lexer.try_lex_identifier(lexer);
//         if !ok   return_error(text);
//         if text  return .{ .IDENTIFIER, text, token_location };
//     }
    
//     // try lexing a string
//     if file[0] == "\"" { 
//         quote_char := file[0];
        
//         if !advance(lexer)  return_error("Unexpected EOF while parsing string.");
//         start := file.data;
        
//         while file[0] != quote_char {
//             if file[0] == "\\" {
//                 if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
                
//                 if is_any(file[0], "\"\\/bfnrt") {
//                     if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
//                 } else if file[0] == "u" {
//                     if !advance(lexer)  return_error("Unexpected EOF while parsing escape sequence.");
//                     for 0..3 {
//                         if !is_digit(file[0])  return_error("Unexpected character while parsing escape sequence.");
//                         if !advance(lexer)     return_error("Unexpected EOF while parsing escape sequence.");
//                     }
//                 } else {
//                     return_error("Unexpected character while parsing escape sequence.");
//                 }
//             } else {
//                 codepoint, len, result := character_utf8_to_utf32(file.data, file.count);
//                 if result != .CONVERSION_OK {
//                     return_error("utf8 decode error while parsing string.");
//                 }
//                 if codepoint < 0x20 || codepoint > 0x10FFFF {
//                     return_error("Invalid character while parsing string.");
//                 }
//                 if !advance(lexer, len)  return_error("Unexpected EOF while parsing string.");
//             }
//         }
        
//         text := string.{ file.data - start, start };
//         advance(lexer);
//         return .{ .STRING, text, token_location };
//     }
    
//     return_error("Unexpected character encountered.");
// }
