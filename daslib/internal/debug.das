options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan
require strings


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

var
    _all_handled_debug_msg_severities : uint = 0u

typedef
    debug_msg_callback_fn = function<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint>
    

struct DebugMsgContext
    debug_ctx : DebugMsgContext_DasHandle
    ignore_list : array<string>
    callback : lambda<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint >


def finalize(var handle : DebugMsgContext & explicit)
    handle.debug_ctx |> destroy_debug_msg_context
    delete handle.callback
    delete handle.ignore_list
    memzero(handle)


struct DebugUtilsMessenger
    messenger : DebugUtilsMessengerEXT
    _debug_ctx : DebugMsgContext


def finalize(var handle : DebugUtilsMessenger & explicit)
    delete handle.messenger
    delete handle._debug_ctx
    memzero(handle)


def debug_msg_handled_any_warnings_or_errors()
    return 0u != (_all_handled_debug_msg_severities & (
        uint(VkDebugUtilsMessageSeverityFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) |
        uint(VkDebugUtilsMessageSeverityFlagBitsEXT
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT)))


def debug_utils_messenger_default_callback(
    msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
    msg_type : uint;
    data : DebugUtilsMessengerCallbackDataEXT
): uint
    print("vk_debug_utils_messenger: {data.message}\n")
    return 0u


[private]
def should_ignore(ctx : DebugMsgContext; msg : string)
    for ignore_msg in ctx.ignore_list
        if msg |> find(ignore_msg) != -1
            return true
    return false


def create_debug_msg_context(
    var ignore_list : array<string>;
    var callback : function<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint>
) : DebugMsgContext

    var debug_ctx <-[[ DebugMsgContext ignore_list <- ignore_list ]]

    debug_ctx.callback <- @ <| [[
        := callback,
        & debug_ctx,
        & _all_handled_debug_msg_severities
    ]](
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint
        var boost_data <- vk_value_to_boost(data)
        if ! debug_ctx |> should_ignore(boost_data.message)
            _all_handled_debug_msg_severities |= uint(msg_severity)
        let result = callback |> invoke(msg_severity, msg_type, boost_data)
        delete boost_data
        return result

    debug_ctx.debug_ctx = create_debug_msg_context(debug_ctx.callback)

    return <- debug_ctx


def debug_utils_messenger_create_info(
    debug_ctx : DebugMsgContext;
    message_severity : uint;
    message_type : uint
) : DebugUtilsMessengerCreateInfoEXT

    var create_info <- [[ DebugUtilsMessengerCreateInfoEXT
        message_severity = message_severity,
        message_type = message_type
    ]]
    unsafe
        create_info.p_user_data = reinterpret<void ?>(debug_ctx.debug_ctx)
        create_info.pfn_user_callback = (
            reinterpret<PFN_vkDebugUtilsMessengerCallbackEXT>(
                vk_debug_msg_callback))
    return <- create_info


def create_debug_utils_messenger(
    instance : Instance;
    message_severity : uint = DEBUG_UTILS_MESSENGER_DEFAULT_SEVERITY;
    message_type : uint = DEBUG_UTILS_MESSENGER_DEFAULT_TYPE;
    var ignore_list : array<string> = [[ array<string> ]];
    var callback : debug_msg_callback_fn = (
        @@debug_utils_messenger_default_callback);
    var result : VkResult? = [[VkResult?]]
) : DebugUtilsMessenger

    var messenger <- [[ DebugUtilsMessenger
        _debug_ctx <- create_debug_msg_context(ignore_list, callback)
    ]]
    var create_info <- debug_utils_messenger_create_info([
        debug_ctx = messenger._debug_ctx,
        message_severity = message_severity,
        message_type = message_type
    ])
    defer <| { delete create_info; }

    messenger.messenger <- create_debug_utils_messenger_ext(
        instance, create_info, result)

    return <- messenger
