
format_location :: (builder: *String_Builder, using location: Source_Code_Location) {
    if fully_pathed_filename {
        print(builder, "%:", fully_pathed_filename);
    }
    print(builder, "%,%", line_number, character_number);
}

report_error :: (model: *Data_Model, location: Source_Code_Location, format: string, args: ..Any) {
    builder: String_Builder;
    builder.allocator = temp;
    
    format_location(*builder, location);
    
    append(*builder, ": ");
    append(*builder, model.language.name);
    append(*builder, " error: ");
    
    print(*builder, format, ..args);
    
    model.last_error_string = builder_to_string(*builder);
    log("%", model.last_error_string);
} @PrintLike

report_error :: (model: *Data_Model, node: *Data_Model.Node, format: string, args: ..Any) {
    location := ifx node then node.location;
    report_error(model, location, format, args);
} @PrintLike

