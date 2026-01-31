/*
    Language_Info contains default-initialized instances of all the interfaces that need to be implemented for any particular language.
    
    
*/

Langauge_Info :: struct {
    parser:         Parser;
    serializer:     Serializer;
    pathfinder:     Pathfinder;
    
    default_node_insertion_behaviour := DEFAULT_NODE_INSERTION_BEHAVIOUR;
    
    format_node_path := default_format_node_path;
}

