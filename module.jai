/*
    The Jai GON Parser

    This module is provided with no warranty or guarantees whatsoever. 
    I don't know what all the proper legal jargon is to include here, and I have not yet selected a proper license for the code. 
    For now, do whatever you wish with the code, so long as it's good. And make sure to link back to this original project.
*/

struct_member_has_note :: (m: *Type_Info_Struct_Member, note: string) -> bool {
    for m.notes
        if it == note
            return true;
    return false;
}

get_struct_member_with_note :: (struct_info: *Type_Info_Struct, note: string) -> *Type_Info_Struct_Member {
    for * m: struct_info.members
        if inline struct_member_has_note(m, note)
            return m;
    return null;
}



set_value_from_string :: (any: Any, text: string) -> bool {
    // While unlikely, it is possible that we are passed an empty string.
    // If this happens, just don't set the value and return.
    if text.count <= 0 return true;
  
    if any.type.type == {
        case .INTEGER;
            result  : int;
            success : bool;
            result, success = string_to_int(text);
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
            if any.type.runtime_size == 4 {
                val, ok, text := string_to_float(text);
                if !ok return false;
                (cast(*float)any.value_pointer).* = val;
            }
            else if any.type.runtime_size == 8 {
                val, ok, text := string_to_float64(text);
                if !ok return false;
                (cast(*float64)any.value_pointer).* = val;
            }
            else return false;  
  
        case .BOOL;
            b := (to_upper(text[0]) == #char "T");
            if any.type.runtime_size == 1 { 
                (cast(*bool)any.value_pointer).* = b; 
            }
            else return false;
            
        case .STRING;
            // TODO: add conditional logic to NOT copy string if desired
            (cast(*string)any.value_pointer).* = text;  
            // (cast(*string)any.value_pointer).* = copy_string(text);  
  
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
                        if it == text {
                            if enum_type.runtime_size == {
                                case 1; (cast(*s8 )any.value_pointer).* |= xx enum_type.values[it_index]; 
                                case 2; (cast(*s16)any.value_pointer).* |= xx enum_type.values[it_index]; 
                                case 4; (cast(*s32)any.value_pointer).* |= xx enum_type.values[it_index]; 
                                case 8; (cast(*s64)any.value_pointer).* |= xx enum_type.values[it_index]; 
                            }
                            return true;
                        }
                    }
                }
                else {
                    for enum_type.names {
                        if it == text {
                            if enum_type.runtime_size == {
                                case 1; (cast(*s8 )any.value_pointer).* = xx enum_type.values[it_index]; 
                                case 2; (cast(*s16)any.value_pointer).* = xx enum_type.values[it_index]; 
                                case 4; (cast(*s32)any.value_pointer).* = xx enum_type.values[it_index]; 
                                case 8; (cast(*s64)any.value_pointer).* = xx enum_type.values[it_index]; 
                            }
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

// TODO: translate array add any at index and array reserve any

array_add_any :: inline (array: Any) -> Any, bool {
    // verify that array is in fact an array
    if array.type.type != .ARRAY {
        print("Array any is not an array!\n");
        return Any.{}, false;
    }
    ti_array := cast(*Type_Info_Array) array.type;
    
    any := array_add_any_nocheck(xx array.value_pointer, ti_array.element_type);
    return any, true;
}

// Technically, this proc will never return an invalid value, since the only possibe failure is failing to allocate memory, in which case we just crash.
array_add_any_nocheck :: (array: *Resizable_Array, elem_type: *Type_Info) -> Any {
    // maybe grow array
    if array.count >= array.allocated {
        reserve := 2 * array.allocated;
        if reserve < 8  reserve = 8;
        array_reserve_nonpoly(xx array, reserve, elem_type.runtime_size);
    }
    
    ret := Any.{
        value_pointer = cast(*u8) array.data + (array.count * elem_type.runtime_size),
        type          = elem_type,
    };
    array.count += 1;
    
    return ret;
}

/*
  This procedure is duplicated verbatim from Basic/Array, since the procedure is limited to file scope there.
  We need this in order to properly reserve space for any type of resizeable array.
  Perhaps there's a way to get import it from basic despite being file scoped?
    I'll have to look into that eventually...
*/
array_reserve_nonpoly :: (array: *Resizable_Array, desired_items: s64, elem_size: s64) {
    if desired_items <= array.allocated return;
    
    if !array.allocator.proc  remember_allocators(array);
    
    array.data = realloc(array.data, desired_items * elem_size, array.allocated * elem_size,, array.allocator);
    assert(array.data != null); // The program will die if we couldn't get memory. We can think about an alternative strategy, but it's hard to know what would be reasonable.
    
    array.allocated = desired_items;
}

array_add_any_at_index :: (array_any: Any, index: int) -> Any {
    if array_any.value_pointer == null || array_any.type.type != .ARRAY 
        then return false;
    
    ti_array  := cast(*Type_Info_Array) array_any.type;
    raw_array := cast(*Resizable_Array) array_any.value_pointer;
    new_cap   := max(next_power_of_two(index + 1), 8);
    
    array_reserve_nonpoly(xx raw_array, new_cap, ti_array.element_type.runtime_size);
    
    raw_array.count = max(raw_array.count, index + 1);
    
    return Any.{
        value_pointer = cast(*u8) raw_array.data + (index * ti_array.element_type.runtime_size),
        type          = ti_array.element_type, 
    };
}

// second return value indicates that the any value was actually a pointer
// deref_any_pointer :: (value: any) -> (any, bool) {
//     ti := runtime.type_info_base(type_info_of(value.id))
//     ti_pointer, ok := ti.variant.(runtime.Type_Info_Pointer)
//     if ok {
//         ret := any {
//             id   = ti_pointer.elem.id,
//             data = (cast(*rawptr)value.data)*,
//         }
//         return ret, true
//     }
    
//     // if the type is not a pointer, just return the original value
//     return value, false
// }

// convert between any types whose underlying value is essentially an integer, using s64 as intermediate value
// tbh, maybe we should just skip the s64 intermediate and replace with a simple memcpy (actually, memset the dst to zero then memcpy src to dst sizeof whichever is smaller)
dynamic_int_cast :: (dst: Any, src: Any, enforce_size: bool = false) -> bool {
    if enforce_size && src.type.runtime_size > dst.type.runtime_size {
        return false;
    }
    
    if src.type.type == {
        case .INTEGER;
        case .ENUM;
        case .BOOL;
             
        case; return false;
    }
    if dst.type.type == {
        case .INTEGER;
        case .ENUM;
        case .BOOL;
             
        case; return false;
    }
    
    s64_value: s64;
  
    if src.type.runtime_size == {
        case  1; s64_value = xx (cast(*s8  )src.value_pointer).*;
        case  2; s64_value = xx (cast(*s16 )src.value_pointer).*;
        case  4; s64_value = xx (cast(*s32 )src.value_pointer).*;
        case  8; s64_value = xx (cast(*s64 )src.value_pointer).*;
        // case 16; s64_value = xx (cast(*i128)src.data).*;
    }
  
    if dst.type.runtime_size == {
        case  1; (cast(*s8  )dst.value_pointer).* = xx s64_value;
        case  2; (cast(*s16 )dst.value_pointer).* = xx s64_value;
        case  4; (cast(*s32 )dst.value_pointer).* = xx s64_value;
        case  8; (cast(*s64 )dst.value_pointer).* = xx s64_value;
        // case 16; (cast(*i128)dst.data).* = xx s64_value;
    }
  
    return true;
}

dynamic_float_cast :: (dst: Any, src: Any) -> bool {
    if dst.type.type != .FLOAT  return false;
    
    f64_value: float64;
    
    if src.type.type == {
        case .FLOAT;
            if src.type.runtime_size == {
                // case 2; f64_value = xx (cast(*f16)src.value_pointer).*;
                case 4; f64_value = xx (cast(*float32)src.value_pointer).*;
                case 8; f64_value = xx (cast(*float64)src.value_pointer).*;
            }
        case .INTEGER;
            if src.type.runtime_size == {
                case  1; f64_value = xx (cast(*s8  )src.value_pointer).*;
                case  2; f64_value = xx (cast(*s16 )src.value_pointer).*;
                case  4; f64_value = xx (cast(*s32 )src.value_pointer).*;
                case  8; f64_value = xx (cast(*s64 )src.value_pointer).*;
                // case 16; f64_value = xx (cast(*s128)src.value_pointer).*;
            }
        case;
            return false;
    }
    
    if dst.type.runtime_size == {
        // case 2; (cast(*f16)dst.data).* = xx f64_value;
        case 4; (cast(*float32)dst.value_pointer).* = xx f64_value;
        case 8; (cast(*float64)dst.value_pointer).* = xx f64_value;
    }
    
    return true;
}

all_bytes_are_zero :: (any: Any) -> bool {
    return all_bytes_are_zero(any.value_pointer, any.type.runtime_size);
}

all_bytes_are_zero :: (data: *void, count: int) -> bool {
    bytes: []u8 = ---;
    bytes.data  = data;
    bytes.count = count;
    for bytes  if b != 0  return false;
    return true;
}

dynamic_new :: (type: Type) -> Any {
    return Any.{
        data = alloc(type.runtime_size),
        id   = type_info(type),
    };
}


#scope_module

#import "Basic";
#import "Reflection";
#import "String";
#import "Hash_Table";
#import "Flat_Pool";

#load "dom.jai";
#load "parse.jai";
#load "serialize.jai";
#load "tokenize.jai";
#load "io_data.jai";
