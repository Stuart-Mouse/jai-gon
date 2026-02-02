
/*
    Add parsing/serialization settings data for all of your data types here at startup.
*/

IO_Data :: struct {
    get_name:       (Any) -> string;
    set_name:       (Any, string);
    
    on_bind:        (*Data_Model, *Data_Model.Node) -> bool;
    
    from_string:    (value: Any, text: string) -> bool;
    to_string:      (value: Any) -> bool, string;
    
    flags: Flags;
    Flags :: enum_flags {
        SKIP_IF_EMPTY;
        SKIP_ELEMS_IF_EMPTY;
        SERIALIZE_AS_ARRAY;
        IS_INDEXED_ARRAY;
    }
}

// TODO: instead of having this globally, we should have some ability for the user to put a *[]IO_Data on the language info and data model itself.
//       then the user can just manage their own global lookup if they so choose, and they can also just point the model or language at their global array.
IO_Data_Lookup: [..] struct { type: *Type_Info; io_data: IO_Data; };

add_io_data :: inline (type: Type, io_data: IO_Data) {
    add_io_data(type.(*Type_Info), io_data);
}

add_io_data :: (type: *Type_Info, io_data: IO_Data) {
    for *IO_Data_Lookup {
        if it.type == type {
            it.io_data = io_data;
            return;
        }
    }
    array_add(*IO_Data_Lookup, .{ type, io_data });
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

