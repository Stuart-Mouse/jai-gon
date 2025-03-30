Serialization_Flags :: enum_flags {
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

Serialization_Settings :: struct {
    flags: Serialization_Flags;
    // TODO: replace with an interface for user to insert nodes manually
    to_string_proc: #type (Any) -> (string, string, bool);
}

Parse_Flags :: enum_flags {
    // only applies to arrays
    ARRAY_INDEXED;
    ARRAY_ENUMERATED;
    
    INIT; // will initialize via an initialization proc if one is provided, or else memset to 0
    SKIP; // will prevent any data bindings from occurring
}

Parse_Settings :: struct {
    flags:      Parse_Flags;
    bind_proc:  #type (Any) -> Any;
    parse_proc: #type (value: Any, text: string) -> bool;
}


/*
    Add parsing/serialization settings data for all of your data types here at startup.
*/

IO_Data :: struct {
    parse:      Parse_Settings;
    serialize:  Serialization_Settings;
    
    // for structs only
    name_member:        *Type_Info_Struct_Member;
    map_key_member:     *Type_Info_Struct_Member;
    // member_data:        Table(*Type_Info_Struct_Member, IO_Data);
    
    // for arrays only
    // can be used to index any array using an enum name
    enum_index_type:    *Type_Info_Enum;
}

IO_Data_Lookup: Table(*Type_Info, IO_Data);

// very minor convenience
add_io_data :: inline (type: Type, io_data: IO_Data) {
    table_add(*IO_Data_Lookup, type.(*Type_Info), io_data);
}

get_io_data :: inline (type: *Type_Info) -> *IO_Data {
    return table_find_pointer(*IO_Data_Lookup, type);
}
