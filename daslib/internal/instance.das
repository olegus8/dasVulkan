options indenting = 4
options no_aot = true

require daslib/defer
require generated
require glfw
require vulkan


struct VulkanVersion
    major : int
    minor : int
    patch : int


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


def create_default_instance()
    var create_info <- [[InstanceCreateInfo
        enabled_extension_names <- get_required_instance_extensions(),
        p_application_info = new [[ApplicationInfo
            api_version = VK_API_VERSION_1_0
        ]]
    ]]
    defer() <| { delete create_info; }
    return <- create_instance(create_info)
