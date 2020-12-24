options indenting = 4
options no_aot = true

require daslib/defer
require generated
require glfw


def create_default_instance()
    var exts <- get_required_instance_extensions()
    defer() <| { delete exts; }
    exts |> push("VK_KHR_get_physical_device_properties2")
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- exts]]
    defer() <| { delete create_info; }
    return <- create_instance(create_info)
