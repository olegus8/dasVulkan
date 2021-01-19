options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct DebugUtilsMessenger
    messenger : VkDebugUtilsMessengerEXT
    _debug_ctx : DebugMsgContext_DasHandle
    _instance : Instance
    _needs_delete : bool


def boost_value_to_vk(b : DebugUtilsMessenger) : VkDebugUtilsMessengerEXT
    return b.messenger

def boost_value_to_vk(b : DebugUtilsMessenger ?) : VkDebugUtilsMessengerEXT ?
    return b?.messenger

def vk_value_to_boost(v : VkDebugUtilsMessengerEXT) : DebugUtilsMessenger
    return [[ DebugUtilsMessenger messenger=v ]]


def create_debug_utils_messenger(
    instance : Instance;
    var create_info : DebugUtilsMessengerCreateInfoEXT;
    callback : lambda<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint>;
    var result : VkResult? = [[VkResult?]]
)
    var vk_callback <- @ <| [[:= callback]] (
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint
        var boost_data <- vk_value_to_boost(data)
        defer <| { delete boost_data; }
        return callback(msg_severity, msg_type, boost_data)
    defer <| { delete vk_callback; }

    var messenger <- [[DebugUtilsMessenger
        _instance = instance |> weak_copy,
        _needs_delete = true
    ]]

    var vk_create_info <- create_info |> vk_view_create_unsafe()
    defer <| { create_info |> vk_view_destroy(); }

    var result_ = VkResult VK_SUCCESS

    result ?? result_ = vkCreateDebugUtilsMessengerEx(
        boost_value_to_vk(instance),
        safe_addr(vk_create_info),
        null,
        vk_callback,
        safe_addr(messenger.messenger),
        safe_addr(messenger._debug_ctx)
    )
    assert(result_ == VkResult VK_SUCCESS)

    return <- messenger


def finalize(var handle : DebugUtilsMessenger & explicit)
    if handle._needs_delete
        vkDestroyDebugUtilsMessengerEx(
            boost_value_to_vk(handle._instance),
            handle.messenger,
            handle._debug_ctx,
            null
        )
    memzero(handle)
