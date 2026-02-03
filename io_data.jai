
/*
    Add parsing/serialization settings data for all of your data types here at startup.
*/

IO_Data :: struct {
    // allocator:      Allocator;
    // get_instance:   () -> *void;
    
    preferred_node_kind_for_serialization: Data_Model.Node.Kind;
    
    get_name:       (Any) -> string;
    set_name:       (Any, string);
    
    on_bind:        (*Data_Model, *Data_Model.Node) -> bool;
    
    // TODO: something like on_bind for serialization, so that we can pass some override_kind for child nodes
    
    from_string:    (value: Any, text: string) -> bool;
    to_string:      (value: Any) -> bool, string;
    
    flags: Flags;
    Flags :: enum_flags {
        SKIP_IF_EMPTY;
        SKIP_ELEMS_IF_EMPTY;
    }
}

IO_Data_Table :: [..] struct { type: *Type_Info; io_data: IO_Data; };

reset :: (table: *IO_Data_Table) {
    array_reset(table);
}

add_io_data :: inline (table: *IO_Data_Table, type: Type, io_data: IO_Data) {
    add_io_data(table, type.(*Type_Info), io_data);
}

add_io_data :: (table: *IO_Data_Table, type: *Type_Info, io_data: IO_Data) {
    for *(table.*) {
        if it.type == type {
            it.io_data = io_data;
            return;
        }
    }
    array_add(table, .{ type, io_data });
}

get_io_data :: (model: *Data_Model, type: *Type_Info) -> *IO_Data {
    if type == null || model.io_data_table == null  return null;
    
    // search io data, repeating if type is a variant
    while true {
        for *(model.io_data_table.*) {
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
        for *(model.io_data_table.*) {
            if type.(*Type_Info_Struct).polymorph_source_struct == xx it.type {
                return *it.io_data;
            }
        }
    }
    
    return null;
}

