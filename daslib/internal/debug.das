options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct DebugUtilsMessenger
    messenger : DebugUtilsMessengerEXT
    _debug_ctx : DebugMsgContext_DasHandle
    _needs_delete : bool
    _callback : lambda<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint >


def create_debug_utils_messenger(
    instance : Instance;
    var create_info : DebugUtilsMessengerCreateInfoEXT;
    var callback : function<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint>;
    var result : VkResult? = [[VkResult?]]
) : DebugUtilsMessenger

    var vk_callback <- @ <| [[:=callback]] (
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint
        var boost_data <- vk_value_to_boost(data)
        let result = callback |> invoke(msg_severity, msg_type, boost_data)
        delete boost_data;
        return result

    var messenger <-[[DebugUtilsMessenger
        _callback <- vk_callback,
        _needs_delete = true,
        _debug_ctx = create_debug_msg_context(vk_callback)
    ]]

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
