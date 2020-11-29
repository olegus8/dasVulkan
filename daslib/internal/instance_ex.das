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

/*
def with_instance(b : block<(inst:VkInstance#)>)
    var inst_info <- [[VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]

    let exts = glfwGetRequiredInstanceExtensions(
        safe_addr_val(inst_info.enabledExtensionCount))

    unsafe
        reinterpret<string const?>(inst_info.ppEnabledExtensionNames) = exts

    var instance : VkInstance
    verify(VkResult VK_SUCCESS == vkCreateInstance(
        safe_addr(inst_info), null, safe_addr(instance)))
    b |> invoke(instance)
    instance |> vkDestroyInstance(null)
*/
