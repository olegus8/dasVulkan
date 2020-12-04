options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require generated

let
    DEFAULT_REQUIRED_EXTENSIONS <- [{auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    }]


def find_physical_device_for_graphics(
    instance : Instance;
    surface : SurfaceKHR
) : PhysicalDevice
    var best_score : int = 0
    var best_device : PhysicalDevice
    var devices <- instance |> enumerate_physical_devices_no_batch()
    defer() <| ${ delete devices; }
    for device in devices
        var score = device |> get_suitability_score(surface)
        if score > best_score
            best_score = score
            best_device = device
    if best_score == 0
        panic("No suitable physical device found.")
    return <- best_device


def get_graphics_queue_family(
    physical_device : PhysicalDevice;
    surface : SurfaceKHR
) : uint
    var found_index : uint = UINT_MAX
    physical_device |> find_graphics_queue_family(surface) <| $(qfam)
        found_index = qfam
    assert(found_index != UINT_MAX)
    return found_index


def find_graphics_queue_family(
    physical_device : PhysicalDevice;
    surface : SurfaceKHR;
    b : block<(qfam:uint)>
)
    var families <- (physical_device |>
        get_physical_device_queue_family_properties())
    defer() <| ${ delete families; }
    for family, index in families, range(INT_MAX)
        if 0u == physical_device |> get_physical_device_surface_support_khr(
            uint(index), surface
        )
            continue

        var graphics_bit = uint(VkQueueFlagBits VK_QUEUE_GRAPHICS_BIT)
        if (family.queue_flags & graphics_bit) == 0u
            continue

        b |> invoke(uint(index))
        break


def find_closest_format(
    physical_device         : PhysicalDevice;
    surface                 : SurfaceKHR;
    preferred_format        : VkFormat;
    preferred_color_space   : VkColorSpaceKHR
) : SurfaceFormatKHR

    var formats <- (physical_device |>
        get_physical_device_surface_formats_khr(surface))
    defer() <| ${ delete formats; }

    for format in formats
        if (format.format == VkFormat VK_FORMAT_B8G8R8A8_SRGB
        &&  format.color_space == (VkColorSpaceKHR
                VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        )
            return <- format

    assert(formats |> length() > 0)
    return <- formats[0]


def find_format_like_srgb_bgra8(
    physical_device : PhysicalDevice;
    surface         : SurfaceKHR
) : SurfaceFormatKHR

    return <- physical_device |> find_closest_format(surface,
        VkFormat VK_FORMAT_B8G8R8A8_SRGB,
        VkColorSpaceKHR VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)


def find_present_mode_like_mailbox(
    physical_device : PhysicalDevice;
    surface         : SurfaceKHR
) : VkPresentModeKHR
    var modes <- (physical_device |>
        get_physical_device_surface_present_modes_khr(surface))
    defer() <| ${ delete modes; }
    for mode in modes
        if mode == VkPresentModeKHR VK_PRESENT_MODE_MAILBOX_KHR
            return mode
    // spec says it's always supported
    return VkPresentModeKHR VK_PRESENT_MODE_FIFO_KHR

def with_device(
    physical_device : PhysicalDevice;
    surface         : SurfaceKHR;
    b : block<(device:Device; queue:Queue)>;
    extensions      : array<string> = DEFAULT_REQUIRED_EXTENSIONS
)
    let graphics_family <- physical_device|>get_graphics_queue_family(surface)

    var create_info <- [[DeviceCreateInfo
        queue_create_infos <- [{auto[] [[DeviceQueueCreateInfo
            queue_family_index = graphics_family,
            queue_priorities <- [{ auto[] 1.0f }]
        ]]}],
        p_enabled_features = new [[PhysicalDeviceFeatures]],
        enabled_extension_names := extensions
    ]]
    defer() <| ${ delete create_info; }

    var device <- physical_device |> create_device(create_info)
    defer() <| ${ delete device; }

    var queue <- device |> get_device_queue(graphics_family)
    defer() <| ${ delete queue; }

    b |> invoke(device, queue)


def get_swap_extent(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    window : GLFWwindow_DasHandle#
)
    var caps <- device |> get_capabilities(surface)

    if caps.currentExtent.width != UINT_MAX
        return <- caps.currentExtent
    else
        let fb_size = window |> get_framebuffer_size()
        return [[VkExtent2D
            width = clamp(fb_size[0],
                caps.minImageExtent.width,
                caps.maxImageExtent.width),
            height = clamp(fb_size[1],
                caps.minImageExtent.height,
                caps.maxImageExtent.height)
        ]]


def get_capabilities(device : VkPhysicalDevice#; surface : VkSurfaceKHR#)
    var caps : VkSurfaceCapabilitiesKHR
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            surface, safe_addr(caps)))
    return <- caps


////////////////////////////
//
// private
//
////////////////////////////


[private]
def get_suitability_score(device : PhysicalDevice; surface : SurfaceKHR)
    var score = 1

    var has_graphics = false
    device |> find_graphics_queue_family(surface) <| $(qfam)
        has_graphics = true
    if ! has_graphics
        score = 0
    
    var props <- device |> get_physical_device_properties()
    defer() <| ${ delete props; }
    if (props.device_type ==
        VkPhysicalDeviceType VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    )
        score += 1000

    var exts <- device |> enumerate_device_extension_properties()
    defer() <| ${ delete exts; }
    for required_ext in DEFAULT_REQUIRED_EXTENSIONS
        var found = false
        for ext in exts
            if hash(ext.extension_name) == hash(required_ext)
                found = true
                break
        if ! found
            score = 0
            break

    var formats <- device |> get_physical_device_surface_formats_khr(surface)
    defer() <| ${ delete formats; }
    if formats |> length() == 0
        score = 0

    var present_modes <- (
        device |> get_physical_device_surface_present_modes_khr(surface))
    defer() <| ${ delete present_modes; }
    if present_modes |> length() == 0
        score = 0

    return score
