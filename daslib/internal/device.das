options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require generated
require window
require instance

let
    DEFAULT_REQUIRED_EXTENSIONS <- [{auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    }]


def get_graphics_queue_family(
    physical_device : PhysicalDevice;
    surface : SurfaceKHR;
    min_queue_count : int
) : uint
    var found_index : uint = UINT_MAX
    physical_device |> find_graphics_queue_family(surface, min_queue_count
    ) <| $(qfam)
        found_index = qfam
    assert(found_index != UINT_MAX)
    return found_index


def get_exact_queue_family(
    physical_device : PhysicalDevice;
    min_queue_count : int;
    queue_flags : uint
) : uint
    var found_index : uint = UINT_MAX
    physical_device |> find_exact_queue_family(
      min_queue_count, queue_flags
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


def find_exact_queue_family(
    physical_device : PhysicalDevice;
    min_queue_count : int;
    queue_flags : uint;
    b : block<(qfam:uint)>
)
    var families <- (physical_device |>
        get_physical_device_queue_family_properties())
    defer() <| ${ delete families; }
    for family, index in families, range(INT_MAX)
        if family.queue_flags != queue_flags
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


def allocate_descriptor_set(
    device : Device;
    descriptor_pool : DescriptorPool;
    set_layout : DescriptorSetLayout;
    var result : VkResult? = [[VkResult?]]
) : DescriptorSets
    var create_info <- [[ DescriptorSetAllocateInfo
        descriptor_pool = weak_copy(descriptor_pool),
        set_layouts <- [{ auto[] weak_copy(set_layout) }]
    ]]
    defer <| { delete create_info; }
    return <- device |> allocate_descriptor_sets <| create_info


def find_best_physical_device(
    instance : Instance;
    surface : SurfaceKHR;
    score_fn : function<(d : PhysicalDevice; s : SurfaceKHR) : int>
) : PhysicalDevice
    var best_score : int = 0
    var best_device : PhysicalDevice
    var devices <- instance |> enumerate_physical_devices()
    defer() <| ${ delete devices; }
    print("Looking for a suitable physical device\n")
    for device in devices
        var props <- device |> get_physical_device_properties()
        defer() <| { delete props ; }
        let version = props.api_version |> vk_version_to_boost |> to_string
        print("Considering {props.device_name} (supports vulkan {version})\n")
        var score = score_fn |> invoke(device, surface)
        if score > best_score
            print("Found new best device.\n")
            best_score = score
            best_device = device
    if best_score == 0
        panic("No suitable physical device found.")
    return <- best_device


def simple_device_score(device : PhysicalDevice; surface : SurfaceKHR)
    var score = 1

    var has_graphics = false
    device |> find_graphics_queue_family(surface, 1) <| $(qfam)
        has_graphics = true
    if ! has_graphics
        print("No graphics. No go.\n")
        return 0
    
    var props <- device |> get_physical_device_properties()
    if (props.device_type ==
        VkPhysicalDeviceType VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    )
        score += 1000

    var feats <- device |> get_physical_device_features()
    if feats.sampler_anisotropy == 0u
        print("No anisotropy. No go.\n")
        return 0

    var exts <- device |> enumerate_device_extension_properties()
    defer() <| ${ delete exts; }
    for required_ext in DEFAULT_REQUIRED_EXTENSIONS
        var found = false
        for ext in exts
            if ext.extension_name == required_ext
                found = true
                break
        if ! found
            print("Required extension {required_ext} not found. No go.\n")
            return 0

    var formats <- device |> get_physical_device_surface_formats_khr(surface)
    defer() <| ${ delete formats; }
    if formats |> length() == 0
        print("No surface formats. No go.\n")
        return 0

    var present_modes <- (
        device |> get_physical_device_surface_present_modes_khr(surface))
    defer() <| ${ delete present_modes; }
    if present_modes |> length() == 0
        print("No present modes. No go.\n")
        return 0

    return score


def create_simple_device(
    physical_device : PhysicalDevice;
    queue_family    : uint
) : Device
    var create_info <- [[DeviceCreateInfo
        queue_create_infos <- [{auto[] [[DeviceQueueCreateInfo
            queue_family_index = queue_family,
            queue_priorities <- [{ auto[] 1.0f }]
        ]]}],
        enabled_extension_names := DEFAULT_REQUIRED_EXTENSIONS,
        p_enabled_features = new [[ PhysicalDeviceFeatures
            sampler_anisotropy = 1u ]]
    ]]
    defer() <| ${ delete create_info; }

    return <- physical_device |> create_device(create_info)
