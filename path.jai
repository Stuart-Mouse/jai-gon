/*
    The Pathfinder is a little interface so you can swap out even how paths are defined.
    It's essentially just a tiny tokenizer that emits commands that tell us how to walk the Data_Model.
    
    The reason this exists is because different path formats may be more intuitive for different file formats,
    and I woudl rather just have a standardized way for people to plug in to the pathfinding instead of
    requiring them to write all their own procedures for finding/navigating nodes in the Data_Model.
    
    This file is also currently home to the procedures for formatting a node's path, 
    although this is not directly related to the pathfinder in any way.
    
    Some notes for language extension implementors:
        A pathfinder should never emit a .END unless remainder.count == 0, 
        because we also check remainder to tell if we are at the final meaningful step in peek_step().
*/

Pathfinder :: struct {
    path:       string;
    remainder:  string;
    next_step:  Step;
    
    get_step := default_pathfinder_step;
    format_node_path := default_format_node_path;
    
    Step :: struct {
        kind:   Kind;
        name:   string;
        index:  int;
        
        Kind :: enum { 
            ABSOLUTE;
            STEP_INTO_BY_NAME;
            STEP_INTO_BY_INDEX;
            STEP_OUT_OF;
            END;
        }
    }
}

reset :: inline (path: *Pathfinder) {
    pathfinder.remainder = pathfinder.path;
}

set_path :: inline (pathfinder: *Pathfinder, path: string) -> {
    parthfinder.path = path;
    reset(pathfinder);
}

peek_step :: inline (pathfinder: *Pathfinder) -> step: Pathfinder.Step, is_final: bool {
    return pathfinder.next_step, is_end(pathfinder);
}

// NOTE: The second return value just tells you if the current step is the last one before .END
//       We use this to make some logic easier in the node insertion code.
get_step :: (pathfinder: *Pathfinder) -> step: Pathfinder.Step, is_final: bool {
    if is_first_step(pathfinder)  pathfinder.get_step(pathfinder);
    
    step := pathfinder.next_step;
    pathfinder.next_step = pathfinder.get_step(pathfinder);
    return step, pathfinder.next_step == .END;
}

is_first_step :: inline (path: Pathfinder) -> bool {
    return path.as_string.data == path.remainder.data;
}

is_end :: inline (path: Pathfinder) -> bool {
    return path.remainder.count == 0;
}

get_pathfinder :: (model: *Data_Model, path: string) -> Pathfinder {
    pathfinder := model.language.pathfinder;
    set_path(*pathfinder, path);
    return pathfinder;
}


default_pathfinder_step :: (using pathfinder: *Pathfinder) -> Pathfinder.Step {
    while true {
        if remainder.count == 0  return .{ kind = END };
        
        if is_first_step(path) && is_any(path[0], "/\\") {
            advance(*remainder, 1);
            return .{ kind = .ABSOLUTE };
        }
        
        _, left, right := split_from_left_by_any(remainder, "/\\");
        remainder = right;
        
        if left == {
          case "..";  return .{ kind = .STEP_OUT_OF };
          case ".";   continue;
        }
        
        return .{ kind = .STEP_INTO, name = left };
    }
}


format_node_path :: (model: *Data_Model, node: *Data_Model.Node) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    model.language.format_node_path(*builder, model, node);
    return builder_to_string(*builder);
}

default_format_node_path :: (builder: *String_Builder, model: *Data_Model, node: *Data_Model.Node) {
    if node.parent != null {
        default_format_node_path(builder, node.parent);
        append(builder, "/");
    }
    append(builder, node.name);
}
