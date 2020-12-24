options indenting = 4
options no_aot = true

require daslib/defer
require generated
require glfw


def create_default_instance(
    api_version_major : uint = 1u;
    api_version_minor : uint = 2u
)
    var exts <- get_required_instance_extensions()
    defer() <| { delete exts; }
    exts |> push("VK_KHR_get_physical_device_properties2")
    var create_info <- [[InstanceCreateInfo
        p_application_info = new [[ ApplicationInfo
            api_version = (api_version_major<<22u) + (api_version_minor<<12u)
        ]],
        enabled_extension_names <- exts]]
    defer() <| { delete create_info; }
    return <- create_instance(create_info)
