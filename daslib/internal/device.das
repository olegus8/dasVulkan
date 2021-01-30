options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require generated
require window

let
    DEFAULT_REQUIRED_EXTENSIONS <- [{auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    }]


def get_graphics_queue_family(
    physical_device : PhysicalDevice;
    surface : SurfaceKHR;
    min_queue_count : int;
) : uint
    var found_index : uint = UINT_MAX
    physical_device |> find_graphics_queue_family(surface, min_queue_count
    ) <| $(qfam)
        found_index = qfam
    assert(found_index != UINT_MAX)
    return found_index


def find_graphics_queue_family(
    physical_device : PhysicalDevice;
    surface : SurfaceKHR;
    min_queue_count : int;
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

        if family.timestamp_valid_bits == 0u
            continue

        if family.queue_count < uint(min_queue_count)
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


def get_swap_extent(
    device : PhysicalDevice;
    surface : SurfaceKHR;
    window : Window
) : Extent2D
    var caps <- device |> get_physical_device_surface_capabilities_khr(surface)

    if caps.current_extent.width != UINT_MAX
        return <- caps.current_extent
    else
        let fb_size = window |> get_framebuffer_size()
        return [[Extent2D
            width = clamp(fb_size[0],
                caps.min_image_extent.width,
                caps.max_image_extent.width),
            height = clamp(fb_size[1],
                caps.min_image_extent.height,
                caps.max_image_extent.height)
        ]]
