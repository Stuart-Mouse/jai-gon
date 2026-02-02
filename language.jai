/*
    Language contains default-initialized instances of all the interfaces that need to be implemented for any particular language.
    
    Things that every language submodule needs to implement:
        get_language :: () -> Language
        
        TODO: other things, some way to set langauge defaults and such..
    
*/

Language :: struct {
    name:               string;
    language_context:   *void;      // context structure for lanaguage parser/serializer, or anything else the language implementation needs.
    pathfinder:         Pathfinder;
    
    default_node_insertion_behaviour := Data_Model.DEFAULT_NODE_INSERTION_BEHAVIOUR;
    
    format_node_path := default_format_node_path;
    
    // TODO: maybe optionally pass node to treat as root to parse()
    parse:          (model: *Data_Model, file: string, file_path_for_logging: string) -> success: bool;
    serialize_node: (builder: *String_Builder, model: *Data_Model, node: *Data_Model.Node) -> success: bool;
    
    deinit: #type (model: *Data_Model);
}



