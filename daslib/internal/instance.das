options indenting = 4
options no_aot = true

require daslib/defer
require generated
require glfw


def create_default_instance(api_major : int = 1; api_minor : int = 2)
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- get_required_instance_extensions(),
        p_application_info = new [[ApplicationInfo
            api_version = (uint(api_major) << 22u) | (uint(api_minor) << 12u)
        ]],
    ]]
    defer() <| { delete create_info; }
    return <- create_instance(create_info)
