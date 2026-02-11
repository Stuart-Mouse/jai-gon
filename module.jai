/*
    Jai Data Marshaller      ( written by u0 )
    
    Feel free to use this code in part or whole however you wish, though I do ask that you give credit if you use this module or a substantial portion of this code in your project.
    
    I want to say a special thanks to Tyler Glaiel for creating GON. 
    Implementing a GON model has been my first real project in just about every language I know well, and the experience has taught me a lot each time.
    This module started its life as a humble GON model and serializer, and now it's grown up to do a lot more stuff.
    
    TODO: Write a little bit of documentation here about the features of the module and how to use it.
    
    
    
    
*/


#module_parameters ()(LANGUAGES: [] string);

// ========== Parsing ==========

// TODO: pass parameter for language to these convenience functions

// load_and_parse_file_with_bindings :: (file_path: string, bindings: ..Binding_With_Path) -> bool {
//     model: Data_Model;
//     init_data_model(*model);
//     defer deinit_data_model(*model);
    
//     model.language = GON_get_langauge();
    
//     file, ok := read_entire_file(file_path,, get_allocator(*model.memory_pool));
//     if !ok  return false;
    
//     if !model.language.parse {
//         log("Data Model Error: language does not implement parse()!"); 
//         return false;
//     }
//     if !model.language.parse()
    
//     ok = add_data_bindings(*model, ..bindings);
//     if !ok  return false;
    
//     ok = process_data_bindings(*model);
//     if !ok  return false;
    
//     return true;
// }

// // NOTE: user does not need to worry about freeing file, since we allocate it in the model's pool.
// load_and_parse_file :: (file_path: string) -> Data_Model, bool {
//     model: Data_Model;
//     init_model(*model, "");
    
//     ok: bool;
//     defer if !ok  deinit_model(*model);
    
//     file:, ok = read_entire_file(file_path,, get_pool_allocator(*model.node_pool));
//     if !ok  return .{}, false;
    
//     init_lexer(*model.lexer, file, file_path);
    
//     ok = construct_dom(*model);
//     if !ok  return .{}, false;
    
//     return model, ok;
// }

parse_file :: (model: *Data_Model, file: string, file_path_for_logging := "") -> bool {
    if !model.language.parse {
        log("Data Model Error: language does not implement parse()!"); 
        return false;
    }
    if !model.language.parse(model, file, file_path_for_logging) {
        log("Data Model Error: Failed to parse file: %", file_path_for_logging);
        return false;
    }
    return true;
}


// ========== Serialization ==========

serialize_to_string :: (using model: *Data_Model) -> bool, string {
    builder: String_Builder;
    if !serialize_to_builder(model, *builder) {
        free_buffers(*builder);
        return false, "";
    }
    return true, builder_to_string(*builder);
}

serialize_to_file :: (using model: *Data_Model, file_path: string) -> bool {
    builder: String_Builder;
    if !serialize_to_builder(model, *builder) {
        free_buffers(*builder);
        return false;
    }
    return write_entire_file(file_path, builder_to_string(*builder));
}

serialize_to_builder :: (using model: *Data_Model, builder: *String_Builder) -> bool {
    if model.root == null  return false;
    
    for model.root.children 
        if !model.language.serialize_node(builder, model, it)
            return false;
    
    return true;
}


#scope_module

#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";
#import "Math";
#import "Flat_Pool";
#import "Unicode";

// I have no idea why next_power_of_two is #scope_export...
using,except(next_power_of_two) Hash_Table :: #import "Hash_Table";

Convert :: #import "Convert";
#import "Reflect";

#load "data_model.jai";
#load "language.jai";
#load "io_data.jai";
#load "path.jai";
#load "log.jai";
#load "utils.jai";

// TODO: While we still get this weird compiler warning due to inserting a #load, we should just read the entire file and insert the contents here. 
//       I don't exactly like that, but it's probably better than getting weird compiler warnings every compile.
#insert #run,stallable -> string {
    builder: String_Builder;
    for LANGUAGES {
        find_submodule_and_append(*builder, "languages", it);
    }
    result := builder_to_string(*builder,, temp);
    return result;
};

// #insert #run,stallable -> string {
//     builder: String_Builder;
//     for TYPES {
//         find_submodule_and_append(*builder, "types", it);
//     }
//     return builder_to_string(*builder,, temp);
// };

find_submodule_and_append :: (builder: *String_Builder, submodule_directory: string, submodule_name: string, loc := #caller_location) #compile_time {
    module_directory := path_strip_filename(loc.fully_pathed_filename);
    
    // try importing single-file submodule
    submodule_file_path := tprint("%/%/%.jai", module_directory, submodule_directory, submodule_name);
    if file_exists(submodule_file_path) {
        print(builder, "#load \"%/%.jai\";", submodule_directory, submodule_name);
        return;
    }
    
    // try importing folder-based submodule
    submodule_file_path = tprint("%/%/%/submodule.jai", module_directory, submodule_directory, submodule_name);
    if file_exists(submodule_file_path) {
        print(builder, "#load \"%/%/submodule.jai\";", submodule_directory, submodule_name);
        return;
    }
    
    assert(false, "Unable to locate submodule '%' in '%/%'.", submodule_name, module_directory, submodule_directory);
}

