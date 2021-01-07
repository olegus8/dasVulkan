options indenting = 4
options no_aot = true

require daslib/defer
require generated
require glfw
require vulkan


def create_default_instance()
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- get_required_instance_extensions(),
        p_application_info = new [[ApplicationInfo
            api_version = VK_API_VERSION_1_1
        ]]
    ]]
    defer() <| { delete create_info; }
    return <- create_instance(create_info)
