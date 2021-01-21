options indenting = 4
options no_aot = true

require daslib/defer
require generated
require glfw
require vulkan
require debug


let
    DEFAULT_INSTANCE_EXTENSIONS = [{auto[] "VK_EXT_debug_utils"}]
    DEFAULT_INSTANCE_LAYERS = [{auto[] "VK_LAYER_KHRONOS_validation"}]


struct VulkanVersion
    major : int
    minor : int
    patch : int


struct InstanceEx
    instance : Instance
    _debug_ctx : DebugMsgContext_DasHandle
    _callback : lambda<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint >


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


def create_instance(
    api_version : uint = VK_API_VERSION_1_0;
    extensions : array<string> = [[ array<string> ]];
    layers : array<string> = [[ array<string> ]];
    debug_msg_severity : uint = DEBUG_UTILS_MESSENGER_DEFAULT_SEVERITY;
    debug_msg_type : uint = DEBUG_UTILS_MESSENGER_DEFAULT_TYPE;
    var callback : function<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint> = @@debug_utils_messenger_default_callback
)
    var all_extensions <- get_required_instance_extensions()
    for ext in extensions
        all_extensions |> push(clone_string(ext))
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- all_extensions,
        enabled_layer_names := layers,
        p_application_info = new [[ApplicationInfo
            api_version = api_version
        ]]
    ]]
    defer() <| { delete create_info; }
    return <- create_instance(create_info)
