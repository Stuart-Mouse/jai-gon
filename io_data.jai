
/*
    Add parsing/serialization settings data for all of your data types here at startup.
*/

IO_Data :: struct {
    // for structs only
    name_member:        *Type_Info_Struct_Member;
    map_key_member:     *Type_Info_Struct_Member;
    member_data:        [] struct { member: *Type_Info_Struct_Member; io_data: IO_Data; };
    
    // for arrays only
    // can be used to index any array using an enum name
    enum_index_type:    *Type_Info_Enum;
    
    
    bind_proc:  #type (Any) -> Any;
    parse_proc: #type (value: Any, text: string) -> bool;
    
    flags: Flags;
    
    Flags :: enum_flags {
        // the struct member or data type will be skipped during serialization if 0-valued
        // arrays will also be skipped if all elements are 0-valued
        // elements within indexed arrays will also be skipped if 0-valued
        SKIP_IF_EMPTY;
        
        // will skip array elems or struct members if they are empty
        // will not skip the array/object itself due to being empty, you would just get "array []" or "object {}"
        SKIP_ELEMS_IF_EMPTY;
        
        // serializes a struct as though it were an array, binding to fields by index rather than by name
        // this should only be used if the structure is stable, as changing the order of fields would cause parsing issues across program versions  
        AS_ARRAY;
        
        // serializes an array of structs as a GON object, using the @gon_name struct member as the name for each object
        // this is primarily used just to make some files more human readable/editable
        AS_OBJECT;
        
        // serialize an object or array on a single line
        // uses ", " as field delimiter by default, so you don't need to manually set a custom delim
        ON_ONE_LINE;
        
        // serializes an array as a GON object, using the index of each element as the name for the object
        ARRAY_INDEXED;
    }
}

IO_Data_Lookup: [..] struct { type: *Type_Info; io_data: IO_Data; };

add_io_data :: inline (type: Type, io_data: IO_Data) {
    add_io_data(type.(*Type_Info), io_data);
}

add_io_data :: (type: *Type_Info, io_data: IO_Data) {
    for *IO_Data_Lookup
        if it.type == type {
            it.io_data = io_data;
            return;
        }
    
    array_add(*IO_Data_Lookup, .{ type, io_data });
}

get_io_data :: inline (type: *Type_Info) -> *IO_Data {
    for *IO_Data_Lookup
        if it.type == type
            return *it.io_data;
    return null;
}

get_struct_member_io_data :: (io_data: *IO_Data, member: *Type_Info_Struct_Member) -> *IO_Data {
    for *io_data.member_data  
        if it.member == member  
            return *it.io_data;
    return null;
}


