options indenting = 4
options no_aot = true

require daslib/defer
require instance
require glfw


def create_default_instance()
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- get_required_instance_extensions()]]
    defer() <| ${ delete create_info; }
    return <- create_instance(create_info)
