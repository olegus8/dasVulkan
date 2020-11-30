options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan
/*

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


def with_view(
    boost_struct : ApplicationInfo;
    b : block<(vk_struct : VkApplicationInfo)>
) {
    let vk_struct <- [[ VkApplicationInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pApplicationName = boost_struct.application_name,
        applicationVersion = boost_struct.application_version,
        pEngineName = boost_struct.engine_name,
        engineVersion = boost_struct.engine_version,
        apiVersion = boost_struct.api_version
    ]];
    b |> invoke(vk_struct);
}


def with_view(
    boost_struct : InstanceCreateInfo;
    b : block<(vk_struct : VkInstanceCreateInfo)>
) {
    boost_struct.p_application_info |> with_p_view() <| $(
        vk_p_application_info : VkApplicationInfo const?
    ) {
    boost_struct.enabled_layer_names |> lock_data() <| $(
        vk_p_enabled_layer_names, vk_enabled_layer_count
    ) {
    boost_struct.enabled_extension_names |> lock_data() <| $(
        vk_p_enabled_extension_names, vk_enabled_extension_count
    ) {
    let vk_struct <- [[ VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        flags = boost_struct.flags,
        pApplicationInfo = vk_p_application_info,
        enabledLayerCount = uint(vk_enabled_layer_count),
        ppEnabledLayerNames = vk_p_enabled_layer_names,
        enabledExtensionCount = uint(vk_enabled_extension_count),
        ppEnabledExtensionNames = vk_p_enabled_extension_names
    ]];
    b |> invoke(vk_struct);
    }}};
}
*/

def with_p_view(
    p_boost_struct : auto(BOOST_T)?;
    b : block<(p_vk_struct : auto(VK_T)?)>
)
    if p_boost_struct == null
        b |> invoke([[VK_T?]])
    else
        *p_boost_struct |> with_view() <| $(vk_struct)
            unsafe
                b |> invoke(addr(vk_struct))
