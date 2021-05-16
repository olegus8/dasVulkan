options indenting = 4
options no_aot = true

require daslib/defer
require generated
require window
require vulkan
require debug


let
    DEFAULT_INSTANCE_EXTENSIONS <- [{auto[] "VK_EXT_debug_utils"}]
    DEFAULT_INSTANCE_LAYERS <- [{auto[] "VK_LAYER_KHRONOS_validation"}]


struct VulkanVersion
    major : int
    minor : int
    patch : int


struct InstanceEx
    instance : Instance
    _debug_ctx : DebugMsgContext


def finalize(var handle : InstanceEx & explicit)
    verify(vk_get_linked_instance() == handle.instance.instance)
    vk_unlink_instance()

    delete handle.instance
    delete handle._debug_ctx
    memzero(handle)


def to_string(v : VulkanVersion) : string
    return "{v.major}.{v.minor}.{v.patch}"


def vk_version_to_boost(v : uint) : VulkanVersion
    return [[VulkanVersion
        major = int(v >> 22u),
        minor = int((v >> 12u) & 0x3ff),
        patch = int(v & 0xfff)
    ]]


def boost_value_to_vk(b : VulkanVersion) : uint
    return (uint(b.major) << 22u) | (uint(b.minor) << 12u) | uint(b.patch)


def create_instance_ex(
    api_version : VulkanVersion = [[ VulkanVersion major=1, minor=2 ]];
    extensions : array<string>  = DEFAULT_INSTANCE_EXTENSIONS;
    layers : array<string>      = DEFAULT_INSTANCE_LAYERS;
    debug_msg_severity : uint   = DEBUG_UTILS_MESSENGER_DEFAULT_SEVERITY;
    debug_msg_type : uint       = DEBUG_UTILS_MESSENGER_DEFAULT_TYPE;
    enabled_validation_features : array<VkValidationFeatureEnableEXT> = [[ array<VkValidationFeatureEnableEXT> ]];
    disabled_validation_features : array<VkValidationFeatureDisableEXT> = [[ array<VkValidationFeatureDisableEXT> ]];
    var debug_msg_ignore_list   : array<string> = [[ array<string> ]];
    var callback : debug_msg_callback_fn = @@debug_utils_messenger_default_callback
) : InstanceEx
    var instance <- [[ InstanceEx
        _debug_ctx <- create_debug_msg_context(debug_msg_ignore_list, callback)
    ]]

    var validation_features <- [[ ValidationFeaturesEXT
        enabled_validation_features := enabled_validation_features,
        disabled_validation_features := disabled_validation_features
    ]]

    var debug_msg_create_info <- debug_utils_messenger_create_info([
        debug_ctx = instance._debug_ctx,
        message_severity = debug_msg_severity,
        message_type = debug_msg_type
    ])

    debug_msg_create_info.next <- validation_features

    var all_extensions <- get_required_instance_extensions()
    for ext in extensions
        all_extensions |> push(clone_string(ext))
    var create_info <- [[InstanceCreateInfo
        next <- debug_msg_create_info,
        enabled_extension_names <- all_extensions,
        enabled_layer_names := layers,
        p_application_info = new [[ApplicationInfo
            api_version=boost_value_to_vk(api_version)]]
    ]]
    defer() <| { delete create_info; }

    instance.instance <- create_instance(create_info)
    verify(vk_get_linked_instance() == [[VkInstance]])
    instance.instance.instance |> vk_link_instance
    verify(vk_get_linked_instance() == instance.instance.instance)
    return <- instance
