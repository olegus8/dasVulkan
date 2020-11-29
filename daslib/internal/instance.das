options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Instance
    instance : VkInstance


struct ApplicationInfo
    application_name        : string
    application_version     : uint
    engine_name             : string
    engine_version          : uint
    api_version             : uint


struct InstanceCreateInfo
    flags                   : uint
    p_application_info      : ApplicationInfo?
    enabled_layer_names     : array<string>
    enabled_extension_names : array<string>


[private]
def with_view(
    boost_struct : InstanceCreateInfo,
    b : block<(vk_struct : VkInstanceCreateInfo)>
)
    boost_struct.p_application_info |> with_view() <| $(
        vk_p_application_info
    ) {
    boost_struct.enabled_layer_names |> lock_data() < $(
        vk_enabled_layer_count, vk_p_enabled_layer_names
    ) {
    boost_struct.enabled_extension_names |> lock_data() < $(
        vk_enabled_extension_count, vk_p_enabled_extension_names
    ) {
        var vk_struct <- [[ VkInstanceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            flags = instance_create_info.flags,
            pApplicationInfo = vk_p_application_info,
            enabledLayerCount = uint(vk_enabled_layer_count),
            ppEnabledLayerNames = vk_p_enabled_layer_names,
            enabledExtensionCount = uint(vk_enabled_extension_count),
            ppEnabledExtensionNames = vk_p_enabled_extension_names
        ]];
        b |> invoke(vk_struct);
    }}}


[private]
def with_view(
    p_boost_struct : InstanceCreateInfo?,
    b : block<(p_vk_struct : VkInstanceCreateInfo? implicit)>
)
    if boost_struct == null
        b |> invoke([[VkInstanceCreateInfo?]])
    else
        *boost_struct |> with_view() <| $(vk_struct)
            b |> invoke(safe_addr(vk_struct))


def create_instance(
    flags                   : uint              = [[uint]];
    application_info        : ApplicationInfo?  = [[ApplicationInfo?]];
    enabled_layer_names     : array<string>     = [[array<string>]];
    enabled_extension_names : array<string>     = [[array<string>]];
    var result              : VkResult?     = [[ VkResult? ]]
) : Instance
    var instance : Instance
    return <- instance


def finalize(var instance : Instance)
    vkDestroyInstance(instance.instance, null)
    memzero(instance)
