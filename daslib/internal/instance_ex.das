options indenting = 4
options no_aot = true

require daslib/defer
require instance


def with_instance(b : block<(inst:VkInstance implicit)>)
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- get_required_instance_extensions()]]
    defer() <| ${ delete create_info; }

    var instance <- create_instance(create_info)
    defer() <| ${ delete instance; }

    b |> invoke(instance.instance)
