options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


let
    DEBUG_UTILS_MESSENGER_DEFAULT_SEVERITY : uint = (
        uint(VkDebugUtilsMessageSeverityFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) |
        uint(VkDebugUtilsMessageSeverityFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT))

let
    DEBUG_UTILS_MESSENGER_DEFAULT_TYPE : uint = (
        uint(VkDebugUtilsMessageTypeFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT) |
        uint(VkDebugUtilsMessageTypeFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT) |
        uint(VkDebugUtilsMessageTypeFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT))


struct DebugUtilsMessenger
    messenger : DebugUtilsMessengerEXT
    _debug_ctx : DebugMsgContext_DasHandle
    _needs_delete : bool
    _callback : lambda<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint >


def debug_utils_messenger_default_callback(
    msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
    msg_type : uint;
    data : DebugUtilsMessengerCallbackDataEXT
): uint
    print("vk_debug_utils_messenger: {data.message}\n")
    return 0u


def create_debug_utils_messenger(
    instance : Instance;
    message_severity : uint = DEBUG_UTILS_MESSENGER_DEFAULT_SEVERITY;
    message_type : uint = DEBUG_UTILS_MESSENGER_DEFAULT_TYPE;
    var create_info : DebugUtilsMessengerCreateInfoEXT;
    var callback : function<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint> = @@debug_utils_messenger_default_callback;
    var result : VkResult? = [[VkResult?]]
) : DebugUtilsMessenger

    var vk_callback <- @ <| [[:=callback]] (
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint
        var boost_data <- vk_value_to_boost(data)
        let result = callback |> invoke(msg_severity, msg_type, boost_data)
        delete boost_data
        return result

    var messenger <-[[DebugUtilsMessenger
        _callback <- vk_callback,
        _needs_delete = true
    ]]

    messenger._debug_ctx = create_debug_msg_context(messenger._callback)

    unsafe
        create_info.p_user_data = reinterpret<void ?>(messenger._debug_ctx)

        create_info.pfn_user_callback = (
            reinterpret<PFN_vkDebugUtilsMessengerCallbackEXT>(
                vk_debug_msg_callback))

    messenger.messenger <- create_debug_utils_messenger_ext(
        instance, create_info, result)

    return <- messenger


def finalize(var handle : DebugUtilsMessenger & explicit)
    if handle._needs_delete
        delete handle.messenger
        handle._debug_ctx |> destroy_debug_msg_context
        delete handle._callback
    memzero(handle)
