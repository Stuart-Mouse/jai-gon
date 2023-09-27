/*
  The Jai GON Parser

  This module is provided with no warranty or guarantees whatsoever. 
  I don't know what all the proper legal jargon is to include here, and I have not yet selected a proper license for the code. 
  For now, do whatever you wish with the code, so long as it's good. And make sure to link back to this original project.
*/


/*
  For all basic types, this basically just kicks the can down the road to regular old print to do the real legwork.
  But for serializing structs to GON, we need some custom formatting, and this gets the job done well enough.
*/
print_gon :: (name: string, value: Any, indent: int = 0) {
  if value.type.type == {
    case .STRUCT;
      struct_info := cast(*Type_Info_Struct) value.type;

      struct_name_member := get_struct_member_with_note(struct_info, "gon_name");
      if struct_name_member print("% ", struct_name_member);

      print("{\n");
      for * m: struct_info.members {
        if m == struct_name_member continue; // Skip printing the gon_name member.
        m_value : Any;
        m_value.type = m.type;
        m_value.value_pointer = s.value_pointer + m.offset_in_bytes;
        print_gon(m.name, m_value, child_indent);
      }
      for 0..indent-1 print(" ");
      print("}\n");

    case .ARRAY;

    case .ENUM;
      if <<cast(*u64)value.value_pointer != 0 {
        enum_info := cast(*Type_Info_Enum) value.type;
        if enum_info.enum_type_flags & .FLAGS {
          print("% " name);
          for enum_info.values {
            if <<cast(*u64)value.value_pointer & xx enum_info.values[it_index]
              print(enum_info.names[it_index]);
          }
        }
        else print("% %\n", name, value);
      }

    case .INTEGER;  #through
    case .FLOAT;
      print("% %\n", name, value);
    case .STRING;
      print("% \"%\"\n", name, value);

    case;
      print("We don't know how to print type \"%\" as a GON field!\n", any.type.type);
  }
}

print_struct_members_and_values :: (s: Any, indent: int = 0, omit: .. *Type_Info_Struct_Member) {
  if s.type.type != .STRUCT {
    print("This is not a struct.\n");
    return;
  }
  struct_info := cast(*Type_Info_Struct) s.type;
  
  INDENT_AMOUNT :: 2;
  child_indent := indent + INDENT_AMOUNT;

  print("{\n");
  for * m: struct_info.members {
    for o: omit if m == o continue m; // Omit struct members we don't want to print. Currently only used to omit the gon_name member.
    m_value : Any;
    m_value.type = m.type;
    m_value.value_pointer = s.value_pointer + m.offset_in_bytes;
    for 1..child_indent print(" ");
    if m.type.type == {
      case .STRUCT;
        // TODO: add if case to do custom printing for certain structs
        // maybe it would be nice to have some comptime procedure to register custom serialization routines for structs in the struct definition instead of polluting this function wiht some huge if case
        print("\"%\" ", m.name);
        print_struct_members_and_values(m_value, child_indent);
      case .ARRAY;
        print("\"%\" ", m.name);
        print_array_values(m_value, child_indent);
      case;
        print("\"%\" \"%\"\n", m.name, m_value);
    }
  }
  for 0..indent-1 print(" ");
  print("}\n");
}

get_struct_member_with_note :: (struct_info: *Type_Info_Struct, note: string) -> *Type_Info_Struct_Member {
  for * m: struct_info.members
    for m.notes
      if it == note
        return m;
  return null;
}

print_array_values :: (a: Any, indent: int = 0) {
  if a.type.type != .ARRAY {
    print("This is not an array.\n");
    return;
  }
  array_info := cast(*Type_Info_Array) a.type;

  count: s64;
  data: *void;
  if array_info.array_type == .FIXED {
    count = array_info.array_count;
    data  = a.value_pointer;
  } else {
    count = << cast(*s64)  (a.value_pointer);
    data  = << cast(**void)(a.value_pointer + 8);
  }

  INDENT_AMOUNT :: 2;
  child_indent := indent + INDENT_AMOUNT;

  if array_info.element_type.type == {
    case .STRUCT;
      struct_info     := cast(*Type_Info_Struct)array_info.element_type;
      gon_name_member := get_struct_member_with_note(struct_info, "gon_name");

      if gon_name_member print("{\n");
      else print("[\n");
      for 0..count-1 {
        item : Any = ---;
        item.type = array_info.element_type;
        item.value_pointer = data + array_info.element_type.runtime_size * it;
        for 1..child_indent print(" ");
        if gon_name_member print("\"%\" ", <<cast(*string)(item.value_pointer + gon_name_member.offset_in_bytes));
        print_struct_members_and_values(item, child_indent, gon_name_member);
      }
      for 1..indent print(" ");
      if gon_name_member print("}\n");
      else print("]\n");

    case .ARRAY;
      print("[\n");
      for 0..count-1 {
        item : Any = ---;
        item.type = array_info.element_type;
        item.value_pointer = data + array_info.element_type.runtime_size * it;
        for 1..child_indent print(" ");
        print_array_values(item, child_indent);
      }
      print("]\n");
    case;
      print("[ ");
      for 0..count-1 {
        item : Any = ---;
        item.type = array_info.element_type;
        item.value_pointer = data + array_info.element_type.runtime_size * it;
        print("\"%\", ", item);
      }
      print("]\n");
  }
}

GonType :: enum u8 {
  INVALID :: 0;

  FIELD   :: 1;
  OBJECT  :: 2;
  ARRAY   :: 3;

  // ANY     :: 255;
}

GonField :: struct { 
  name         : string;
  value        : string;
  type         : GonType;
  data_binding : Any;
  parent       : *GonField;
  array_index  : int;
};

GonDataBinding :: struct {
  // interface
  field_address : [] string;
  data_binding  : Any;

  // internal
  tracker : int = 0;
}

GonParseContext :: struct {
  // interface
  file          : string;  // the entire file being parsed
  data_bindings : [] GonDataBinding;
  event_handler : GonEventHandler;

  // internal
  cursor     : int = 0; // current position in the file being parsed
  depth      : int = 0;
  line_count : int = 0;
}

GonTokenType :: enum {
  INVALID;
  STRING;
  OBJECT_BEGIN;
  OBJECT_END;
  ARRAY_BEGIN;
  ARRAY_END;
  EOF;
}

GonEventHandler :: struct {
  object_begin : (*GonParseContext, *GonField) -> bool;
  object_end   : (*GonParseContext, *GonField) -> bool;
  array_begin  : (*GonParseContext, *GonField) -> bool;
  array_end    : (*GonParseContext, *GonField) -> bool;

}

// gon_match_field_name_and_type :: (parent: *GonField, field: *GonField, data: Any) -> bool {
//   using condition_data : *struct {
//     gon_field_name : string;
//     gon_field_type : GonType;
//   } = xx data.value_pointer;

//   return field.name     == gon_field_name
//       && field.type == gon_field_type;
// }

// gon_scan_for_object_or_array_end :: inline (using parse_context: *GonParseContext, begin_token: u8, end_token: u8) -> bool {
//   nested : int = 0;
//   while true {
//     if !advance_cursor(gon_string) return false;
//     nested += xx (file[cursor] == begin_token);
//     nested -= xx (file[cursor] == end_token  );
//     if nested < 0 {
//       if !advance_cursor(gon_string) return false; // advance one more character after hitting end token
//       return true;
//     }
//   }
//   return false; // unreachable
// }
// gon_scan_for_object_end :: inline (using parse_context: *GonParseContext) -> string, bool {
//   return gon_string, gon_scan_for_object_or_array_end(*gon_string, #char "{", #char "}");
// }
// gon_scan_for_array_end :: inline (using parse_context: *GonParseContext) -> string, bool {
//   return gon_string, gon_scan_for_object_or_array_end(*gon_string, #char "[", #char "]");
// }

// Print field names in reverse order up to root of file
print_field_stack :: (field: *GonField) {
  while field {
    if field.parent 
    && field.parent.type == .ARRAY
      print("%/", field.array_index);
    else print("%/", field.name);
    field = field.parent;
  }
}

set_field_data_binding :: (field: *GonField, data_binding: *Any) -> bool {
  // If the gon type is a field, just set the value directly, 
  //   no need to store the data binding. (But perhaps we should anyways?)
  if field.type == .FIELD {
    assert(data_binding.type.type == .INTEGER 
        || data_binding.type.type == .FLOAT
        || data_binding.type.type == .STRING
        || data_binding.type.type == .ENUM);
    if !set_value_from_string(data_binding, *field.value)
      return false;
  }
  // If the gon type is object or array, we need to store the binding 
  //   so that we can load values from the child gon fields.
  else {
    // Type checks
    if data_binding.type.type == {
      case .ARRAY;
        // no op
      case .STRUCT;
        // Save field name to struct member with @gon_name tag.
        // Only if parent's GON type is object and Jai type is array.
        if field.parent      != null
        && field.parent.type == .OBJECT
        && field.parent.data_binding.type      != null
        && field.parent.data_binding.type.type == .ARRAY {
          ti_struct := cast(*Type_Info_Struct) data_binding.type;
          gon_name_member := get_struct_member_with_note(ti_struct, "gon_name");
          if gon_name_member {
            gon_name_member_any : Any;
            gon_name_member_any.value_pointer = data_binding.value_pointer + gon_name_member.offset_in_bytes;
            gon_name_member_any.type = gon_name_member.type;
            if !set_value_from_string(*gon_name_member_any, *field.name)
              return false;
          }
        }
      case .ENUM;
        // If type is enum, verify that it is enum_flags.
        // We don't want to allow binding regular enums to GON arrays.
        if !(field.type == .ARRAY && ((cast(*Type_Info_Enum)data_binding.type).enum_type_flags & .FLAGS)) {
          print("Gon Parse Error: Invalid data binding. Enum type can only be bound to a GON array if it is enum_flags.\n");
          return false;
        }
      case;
        print("Gon Parse Error: Invalid data binding. GON type % cannot be bound to a %\n", field.type, data_binding.type.type);
        return false;
    }
    field.data_binding = <<data_binding;
  }

  return true;
}

parse_file :: inline (using parse_context: *GonParseContext) -> bool {
  return parse_object(parse_context, null);
}

/*
  This is the main parsing routine. 
  It processes fields within a GON object or array one at a time,
    pulling tokens as necessary.
  This function is recursive, calling itself each time we step into an object or array.
*/
parse_object :: (using parse_context: *GonParseContext, parent: *GonField) -> bool {
  next_token_type : GonTokenType;
  next_token      : string;

  field_index : int = 0;

  // process a single field per loop
  while true { 
    defer field_index += 1;
    field : GonField;
    field.parent = parent; // allows us to traverse the field stack

    // read field name
    if parent == null || parent.type != .ARRAY {
      next_token_type, next_token = get_next_token(parse_context);

      if next_token_type == {
        case .EOF;
          return true;

        case .STRING;
          field.name = next_token;

        case .OBJECT_END;
          if parent == null || parent.type != .OBJECT {
            print("GON parse error: Unexpected % token \"%\".\n", next_token_type, next_token);
            return false;
          }
          return true;

        case;
          print("GON parse error: Unexpected % token \"%\".\n", next_token_type, next_token);
          return false;
      }
    }

    // read field value
    next_token_type, next_token = get_next_token(parse_context);
    if next_token_type == {
      case .STRING;
        field.type = .FIELD;
        field.value = next_token;

      case .OBJECT_BEGIN;
        field.type = .OBJECT;

      case .ARRAY_BEGIN;
        field.type = .ARRAY;

      case .ARRAY_END;
        if parent == null || parent.type != .ARRAY {
          print("GON parse error: Unexpected % token \"%\".\n", next_token_type, next_token);
          return false;
        }
        return true;

      case;
        print("GON parse error: Unexpected % token \"%\".\n", next_token_type, next_token);
        return false;
    }

    // debug asserts
    assert(field.type == .FIELD 
        || field.type == .OBJECT
        || field.type == .ARRAY);
    assert((field.value.data == null) == ((field.type == .OBJECT) || field.type == .ARRAY));
    assert((field.value.data != null) == (field.type == .FIELD));
    assert((field.name.data  == null) == ((parent != null) && (parent.type == .ARRAY)));
    
    // Check for callbacks on field before data bindings

    // Check for direct data bindings on field
    for * b: data_bindings {
      // check that field address matched up to this point
      // also skip completed matches
      if b.tracker < depth || b.field_address.count <= depth
        continue b;

      // check if field_address[depth] is a match
      if field.name != b.field_address[depth]
        continue b;
      b.tracker += 1;

      // check if we've matched the entire field address
      if b.field_address.count == b.tracker {
        b.tracker = -1; // deactivate the binding so that it will be skipped in future checks
        print("Data binding on field: ");
        print_field_stack(*field);
        print("\n");
        if !set_field_data_binding(*field, *b.data_binding) return false;
      }
    }

    /* 
      Check for indirect data bindings on child fields of data-bound parents.
      Because we only allow data bindings on gon objects to structs, arrays, and enum_flags
        we only need to process those cases.
      Likewise for gon arrays, though those can also be bound to enum flags.
    */
    if parent != null && parent.data_binding.value_pointer {
      if parent.data_binding.type.type == {
        case .STRUCT;
          ti_struct := cast(*Type_Info_Struct) parent.data_binding.type;

          /* 
            The method of getting the struct member to assign to depends on gon type.
            If the gon type is object, we match on the member/field name.
            If the gon type is array, we match on the index of the member/field.
          */
          member : Type_Info_Struct_Member;
          if parent.type == {
          case .OBJECT;
            member = get_field(ti_struct, field.name);
          case .ARRAY;
            if field_index < ti_struct.members.count {
              member = ti_struct.members[field_index];
            }
            else { 
              print("Gon Parse Warning: too many fields in array-type struct definition.");
              // TODO: better warning message. print field stack ?
            }
          case;
            print("Gon Parse Error: parent object data binding was invalid.\n");
            // TODO: maybe better error message?
            return false;
          }

          if (member.type) {
            data_binding : Any = --- ;
            data_binding.value_pointer = parent.data_binding.value_pointer + member.offset_in_bytes;
            data_binding.type = member.type;
            if !set_field_data_binding(*field, *data_binding) return false;
          }

        case .ARRAY;
          ti_array := cast(*Type_Info_Array) parent.data_binding.type;

          // determine element destination
          element : Any = ---;
          if ti_array.array_type == {
            case .FIXED;
              if field_index >= ti_array.array_count {
                print("Unable to add item to array, array has already reached capacity.\n");
                return false;
              }
              element.value_pointer = parent.data_binding.value_pointer + field_index * ti_array.element_type.runtime_size;
              element.type = ti_array.element_type;
              if !set_field_data_binding(*field, *element) return false;

            case .VIEW;
              /* 
                Despite not actually being a resizable array, this cast is fine for our purposes.
                We only need to access the data and count members, which are spec'd to line up for array views and resizable arrays.
              */
              array := cast(*Resizable_Array) parent.data_binding.value_pointer;
              if field_index >= array.count {
                print("Unable to add item to array, array has already reached capacity.\n");
                return false;
              }
              element.value_pointer = cast(*u8)array.data + field_index * ti_array.element_type.runtime_size;
              element.type = ti_array.element_type;
              if !set_field_data_binding(*field, *element) return false;


            case .RESIZABLE;
              element = array_add_any_nocheck(xx parent.data_binding.value_pointer, ti_array.element_type);
              if !set_field_data_binding(*field, *element) return false;
          }

        case .ENUM;
          if !set_field_data_binding(*field, *parent.data_binding) return false;
      }
    }

    // Recurse for object / array
    if field.type == .OBJECT 
    || field.type == .ARRAY {
      depth += 1;
      if !parse_object(parse_context, *field) return false;
      depth -= 1;
      // when we come back up from an object or array, decrement bindings' tracker values
      for * b: data_bindings {
        if b.tracker > depth then b.tracker -= 1;
      }
    }

    /*
      Check for callbacks on field before data bindings
    */



  } // end main loop

  return true;
}

/*
  Test function that simply prints all of the tokens in a GON file on individual lines.
*/
print_all_tokens :: (using parse_context: *GonParseContext) {
  next_token_type : GonTokenType;
  next_token      : string;
  
  print("Tokens in file: \n");

  while true {
    next_token_type, next_token = get_next_token(parse_context);
    if next_token_type == {
      case .INVALID; 
        print("invalid pat!\n");
        return;
      case .EOF; 
        print("graceful pat!\n");
        return;
      case;
        print("\"%\" ", next_token);
    }
  }

  print("\n");
}

// Returns the type and string value of the next token in the file.
// This function will advance the cursor to 1 char after the end of the next token.
get_next_token :: (using parse_context: *GonParseContext) -> GonTokenType, string {
  if cursor == file.count return .EOF, ""; 
  if !skip_whitespace_and_comments(parse_context) return .EOF, "";
  assert(cursor <= file.count);
  // TODO: could probably clean up the above a little 
  //    I'm not sure if we need the eof check both before and after skip_whitespace
  //    The assert condition can probably be removed, may move >= to eof check just in case

  str : string = ---;
  str.data = *file[cursor];

  // check for single char (structural) tokens
  str.count = 1;
  if str[0] == #char "{" {
    if !advance_cursor(parse_context) 
      return .INVALID, str;
    return .OBJECT_BEGIN, str;
  }
  if str[0] == #char "}" {
    if !advance_cursor(parse_context) 
      return .INVALID, str;
    return .OBJECT_END, str;
  }
  if str[0] == #char "[" {
    if !advance_cursor(parse_context) 
      return .INVALID, str;
    return .ARRAY_BEGIN, str;
  }
  if str[0] == #char "]" {
    if !advance_cursor(parse_context) 
      return .INVALID, str;
    return .ARRAY_END, str;
  }

  // string token
  str.count = 0;
  // scan for end of string in quotation marks
  if file[cursor] == #char "\"" {
    str.data += 1;
    if !advance_cursor(parse_context) 
      return .INVALID, str; 
    while file[cursor] != #char "\"" {
      adv : int = 1;
      if file[cursor] == #char "\\" 
        then adv = 2;
      defer str.count += adv;
      if !advance_cursor(parse_context) 
        return .INVALID, str;
    }
    if !advance_cursor(parse_context) 
      return .INVALID, str;
    return .STRING, str;
  }

  // scan for end of bare string
  if !is_reserved_char(file[cursor]) {
    while !is_reserved_char(file[cursor]) 
       && !is_whitespace(file[cursor]) {
      defer str.count += 1;
      if !advance_cursor(parse_context) 
        return .INVALID, str;
    }
    return .STRING, str;
  }

  print("funky\n");
  return .INVALID, ""; // probably had some funky character in there
}

// TODO?: replace with a macro (gon_move_cursor)
advance_cursor :: inline (using parse_context: *GonParseContext, amount: s64 = 1) -> bool {
  if cursor + amount > file.count
    return false;
  cursor += amount;
  return true;
}

is_whitespace :: inline (char: u8) -> bool {
  return char == #char " "
      || char == #char ","
      || char == #char "\t"
      || char == #char "\r"
      || char == #char "\n";
}

is_whitespace :: inline (char: u8, newline_count: *int) -> bool {
  if char == #char " "
  || char == #char ","
  || char == #char "\t"
  || char == #char "\r"
    return true;

  if char == #char "\n" {
    <<newline_count += 1;
    return true;
  }

  return false;
}

is_reserved_char :: inline (char: u8) -> bool {
  return char == #char "#"
      || char == #char "{"
      || char == #char "}"
      || char == #char "["
      || char == #char "]";
}

// cycles between skipping whitespace and comments until next character is neither
skip_whitespace_and_comments :: inline (using parse_context: *GonParseContext) -> bool {
  while true {
    while is_whitespace(file[cursor], *line_count)
      if !advance_cursor(parse_context) 
      || cursor == file.count 
        return false;

    if file[cursor] == #char "#" {
      while file[cursor] != #char "\n" 
        if !advance_cursor(parse_context) 
        || cursor == file.count 
          return false;
    }
    else return true;
  }
  return true;
}

set_value_from_string :: (any: *Any, text: *string) -> bool {
  // While unlikely, it is possible that we are passed an empty string.
  // If this happens, just don't set the value and return.
  if text.count <= 0 return true;

  if any.type.type == {
    case .INTEGER;
      result  : int;
      success : bool;
      result, success = string_to_int(<<text);
      if !success return false;

      ti_integer := cast(*Type_Info_Integer)any.type;
      if ti_integer.signed {
          valid, low, high := range_check_and_store(result, ti_integer, any.value_pointer);
          // @ToDo: We could log an error with the ranges here, similar to Command_Line.parse_and_write_integer
          if !valid return false;
      } else {
          valid, low, high := range_check_and_store(cast(u64) result, ti_integer, any.value_pointer);
          // @ToDo: We could log an error with the ranges here, similar to Command_Line.parse_and_write_integer
          if !valid return false;
      }

      return true;

    case .FLOAT;
      success: bool;
      if any.type.runtime_size == 4 {
        f: float; 
        f, success, text.* = string_to_float(text.*);
        if !success return false;
        <<cast(*float)any.value_pointer = f;
      }
      else if any.type.runtime_size == 8 {
        f: float64;
        f, success, text.* = string_to_float64(text.*);
        if !success return false;
        <<cast(*float64)any.value_pointer = f;
      }
      else return false;

    case .BOOL;
      b := (to_upper((<<text)[0]) == #char "T");
      if any.type.runtime_size == 1 { 
        <<cast(*bool)any.value_pointer = b; 
      }
      else return false;

    case .STRING;
      // TODO: add conditional logic to copy string if desired
      <<cast(*string)any.value_pointer = <<text;

    case .ENUM;
      enum_type := cast(*Type_Info_Enum)any.type;

      // TODO: May add this back in later...
      // First, try to parse it as an integer.
      // _any := any;
      // _any.type = enum_type.internal_type;
      // success := set_value_from_string(_any, text);
      success := false;

      // If that doesn't work, try to parse the enum names.
      if !success {
        if enum_type.enum_type_flags & .FLAGS {
          for enum_type.names {
            if it == <<text {
              if      enum_type.runtime_size == 1 { <<cast(*s8 )any.value_pointer |= xx enum_type.values[it_index]; }
              else if enum_type.runtime_size == 2 { <<cast(*s16)any.value_pointer |= xx enum_type.values[it_index]; }
              else if enum_type.runtime_size == 4 { <<cast(*s32)any.value_pointer |= xx enum_type.values[it_index]; }
              else if enum_type.runtime_size == 8 { <<cast(*s64)any.value_pointer |=    enum_type.values[it_index]; }
              return true;
            }
          }
        }
        else {
          for enum_type.names {
            if it == <<text {
              if      enum_type.runtime_size == 1 { <<cast(*s8 )any.value_pointer = xx enum_type.values[it_index]; }
              else if enum_type.runtime_size == 2 { <<cast(*s16)any.value_pointer = xx enum_type.values[it_index]; }
              else if enum_type.runtime_size == 4 { <<cast(*s32)any.value_pointer = xx enum_type.values[it_index]; }
              else if enum_type.runtime_size == 8 { <<cast(*s64)any.value_pointer =    enum_type.values[it_index]; }
              return true;
            }
          }
        }
        
      }
      if !success return false;

    case;
      return false;
  }

  return true;
}

/*
  I may not actually use this first implementation of array_add_any
    since it requires an Any to be passed in with value already assigned.
  This means we have to have a value with some storage other than its actual destination (data binding).
  So the version below which just passes back the Any for us to fill up is prefereable.
  The only complication which needs to be considered is that we must ensure that we always assign a value
    to the Any returned, otherwise we could end up with some uninit'd object in one of our arrays.
  By default, any error which causes a data-bound value not to be assigned is an actual error.
  Though this may change when I add error options. Just something to keep in mind.
*/
array_add_any :: inline (array: Any, item: Any) -> bool {
  // verify that array is in fact an array
  if array.type.type != .ARRAY {
    print("Array any is not an array!\n");
    return false;
  }
  ti_array := cast(*Type_Info_Array) array.type;

  // verify that array element type matches the type of the item that we want to add
  if ti_array.element_type != item.type {
    print("Unable to add element to array, types do not match!\n");
    return false;
  }
  
  return array_add_any_nocheck(xx array.value_pointer, *item);
}

array_add_any_nocheck :: (array: *Resizable_Array, item: *Any) -> bool {
  // maybe grow array
  if array.count >= array.allocated {
    reserve := 2 * array.allocated;
    if reserve < 8  reserve = 8;
    array_reserve_nonpoly(xx array, reserve, item.type.runtime_size);
  }

  // copy element to destination manually
  destination : *void = cast(*u8)array.data + array.count * item.type.runtime_size;
  memcpy(destination, xx item.value_pointer, item.type.runtime_size);
  array.count += 1;

  return true;
}

array_add_any :: inline (array: Any) -> Any, bool {
  any : Any;

  // verify that array is in fact an array
  if array.type.type != .ARRAY {
    print("Array any is not an array!\n");
    return any, false;
  }
  ti_array := cast(*Type_Info_Array) array.type;

  any = array_add_any_nocheck(xx array.value_pointer, ti_array.element_type);
  return any, true;
}

array_add_any_nocheck  :: (array: *Resizable_Array, type: *Type_Info) -> Any {
  // maybe grow array
  if array.count >= array.allocated {
    reserve := 2 * array.allocated;
    if reserve < 8  reserve = 8;
    array_reserve_nonpoly(xx array, reserve, type.runtime_size);
  }

  // copy element to destination manually
  any : Any = --- ;
  any.value_pointer = cast(*void) (cast(*u8)array.data + array.count * type.runtime_size);
  any.type = type;
  array.count += 1;

  return any;
}

#scope_file

/*
  This procedure is duplicated verbatim from Basic/Array, since the procedure is limited to file scope there.
  We need this in order to properly reserve space for any type of resizeable array.
  Perhaps there's a way to get import it from basic despite being file scoped?
    I'll have to look into that shortly...
*/
array_reserve_nonpoly :: (array: *[..] *void, desired_items: s64, size: s64) {
    if desired_items <= array.allocated return;

    if !array.allocator.proc  remember_allocators(array);

    array.data = realloc(array.data, desired_items * size, array.allocated * size, array.allocator);
    assert(array.data != null); // The program will die if we couldn't get memory. We can think about an alternative strategy, but it's hard to know what would be reasonable.

    array.allocated = desired_items;
}

#import "Basic";
#import "Reflection";
#import "File";
