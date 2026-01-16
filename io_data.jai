
/*
    Add parsing/serialization settings data for all of your data types here at startup.
*/

IO_Data :: struct {
    // for structs only
    name_member: string;
    
    // for arrays only
    // can be used to index any array using an enum name
    enum_index_type: *Type_Info_Enum;
    
    
    bind_proc:      (Any) -> Any;
    parse_proc:     (value: Any, text: string) -> bool;
    serialize_proc: (value: Any) -> bool, string;
    
    flags: Flags;
    
    Flags :: enum_flags {
        SKIP_IF_EMPTY;
        SKIP_ELEMS_IF_EMPTY;
        SERIALIZE_AS_ARRAY;
        IS_INDEXED_ARRAY;
    }
}

IO_Data_Lookup: [..] struct { type: *Type_Info; io_data: IO_Data; };

add_io_data :: inline (type: Type, io_data: IO_Data) {
    add_io_data(type.(*Type_Info), io_data);
}

add_io_data :: (type: *Type_Info, io_data: IO_Data) {
    // basic validation before adding io_data, so that we don't need to check later...
    _io_data := io_data;
    base_type := get_variant_base_type(type);
    if _io_data.name_member && base_type.type != .STRUCT {
        log("Warning: cannot set a name member in io data for on a non-struct type.");
        _io_data.name_member = "";
    }
    if _io_data.enum_index_type && base_type.type != .ARRAY {
        log("Warning: cannot set an enum index type in io data for a non-array type.");
        _io_data.enum_index_type = null;
    }
    
    for *IO_Data_Lookup {
        if it.type == type {
            it.io_data = _io_data;
            return;
        }
    }
    
    array_add(*IO_Data_Lookup, .{ type, _io_data });
}

get_io_data :: (type: *Type_Info) -> *IO_Data {
    if type == null  return null;
    
    // search io data, repeating if type is a variant
    while true {
        for *IO_Data_Lookup {
            if it.type == type {
                return *it.io_data;
            }
        }
        if type.type == .VARIANT {
            type = type.(*Type_Info_Variant).variant_of;
            continue;
        }
        break;
    }
    
    // second pass for polymorphic structs
    if type.type == .STRUCT {
        for *IO_Data_Lookup {
            if type.(*Type_Info_Struct).polymorph_source_struct == xx it.type {
                return *it.io_data;
            }
        }
    }
    
    return null;
}

