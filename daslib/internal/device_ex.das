options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require device

let
    DEFAULT_REQUIRED_EXTENSIONS = [[auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ]]


def enumerate_physical_devices_ex(instance : VkInstance): array<PhysicalDevice>
    var devices <- instance |> enumerate_physical_devices()
    defer() <| ${ delete devices; }
    return <- devices |> split()


def find_best_physical_device(instance : VkInstance; surface : VkSurfaceKHR#
) : PhysicalDevice
    var best_score : int = 0
    var best_device : PhysicalDevice
    var devices <- instance |> enumerate_physical_devices_ex()
    defer() <| ${ delete devices; }
    for device in devices
        var score = device |> get_suitability_score(surface)
        if score > best_score
            best_score = score
            best_device = device
    if best_score == 0
        panic("No suitable physical device found.")
    return <- best_device


[private]
def get_suitability_score(device : PhysicalDevice; surface : VkSurfaceKHR#)
    var score = 1

    let vk_device = device.physical_device

    var has_graphics = false
    vk_device |> with_graphics_queue_family(surface) <| $(qfam)
        has_graphics = true
    if ! has_graphics
        score = 0
    
    let props <- device |> get_physical_device_properties()
    if (props.deviceType ==
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

    vk_device |> with_present_modes(surface) <| $(modes)
        if modes |> length() == 0
            score = 0
    return score


def with_queue_families(device : VkPhysicalDevice#;
    b : block<(families: array<VkQueueFamilyProperties>#)>
)
    var families : array<VkQueueFamilyProperties>
    var count : uint
    device |> vkGetPhysicalDeviceQueueFamilyProperties(
        safe_addr(count), null)
    families |> resize(int(count))
    families |> lock() <| $(tfamilies)
        device |> vkGetPhysicalDeviceQueueFamilyProperties(
            safe_addr(count), addr(tfamilies[0]))
        b |> invoke(tfamilies)
    delete families


def get_graphics_queue_family(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#
) : uint
    var found_index : uint = UINT_MAX
    device |> with_graphics_queue_family(surface) <| $(qfam)
        found_index = qfam
    assert(found_index != UINT_MAX)
    return found_index


def with_graphics_queue_family(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(qfam:uint)>
)
    device |> with_queue_families() <| $(families)
        for family, index in families, range(INT_MAX)
            var can_present : uint
            verify(VkResult VK_SUCCESS ==
                device |> vkGetPhysicalDeviceSurfaceSupportKHR(
                    uint(index), surface, safe_addr(can_present)))
            if can_present == 0u
                continue

            var graphics_bit = uint(VkQueueFlagBits VK_QUEUE_GRAPHICS_BIT)
            if (family.queueFlags & graphics_bit) == 0u
                continue

            b |> invoke(uint(index))
            return


def get_best_format(
    device                  : PhysicalDevice;
    surface                 : VkSurfaceKHR;
    preferred_format        : VkFormat;
    preferred_color_space   : VkColorSpaceKHR
) : VkSurfaceFormatKHR

    var formats <- device |> get_physical_device_surface_formats_khr(surface)
    defer() <| ${ delete formats; }

    for format in formats
        if (format.format == VkFormat VK_FORMAT_B8G8R8A8_SRGB
        &&  format.colorSpace == (VkColorSpaceKHR
                VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        )
            return <- format

    assert(formats |> length() > 0)
    return <- formats[0]


def get_format_srgb_bgra8(device : PhysicalDevice; surface : VkSurfaceKHR
) : VkSurfaceFormatKHR

    return <- device |> get_best_format(surface,
        VkFormat VK_FORMAT_B8G8R8A8_SRGB,
        VkColorSpaceKHR VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)


def with_present_modes(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(formats:array<VkPresentModeKHR>#)>
)
    var modes : array<VkPresentModeKHR>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
            surface, safe_addr(count), null))
    modes |> resize(int(count))
    modes |> lock() <| $(tmodes)
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
                surface, safe_addr(count), addr(tmodes[0])))
        b |> invoke(tmodes)
    delete modes


def get_best_present_mode(device : VkPhysicalDevice#; surface : VkSurfaceKHR#
) : VkPresentModeKHR
    var found_mode : VkPresentModeKHR
    device |> with_present_modes(surface) <| $(modes)
        for preferred in [[auto[]
            VkPresentModeKHR VK_PRESENT_MODE_MAILBOX_KHR;
            VkPresentModeKHR VK_PRESENT_MODE_FIFO_KHR
        ]]
            for mode in modes
                if mode == preferred
                    found_mode = mode
                    return
        panic("Should not be here since FIFO mode is required " +
            "to be supported by Vulkan spec")
    return found_mode


def with_device(
    instance : VkInstance#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR;
    b : block<(device:VkDevice#; queue:VkQueue#)>
)
    let queue_priority = 1.0f
    let queue_info <- [[VkDeviceQueueCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO),
        queueFamilyIndex = phys_dev |> get_graphics_queue_family(surface),
        queueCount = 1u,
        pQueuePriorities = safe_addr(queue_priority)
    ]]
    let features : VkPhysicalDeviceFeatures
    var device : VkDevice
    let create_info = [[VkDeviceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        pQueueCreateInfos = safe_addr(queue_info),
        queueCreateInfoCount = 1u,
        pEnabledFeatures = safe_addr(features),
        enabledExtensionCount = uint(DEFAULT_REQUIRED_EXTENSIONS |> length()),
        ppEnabledExtensionNames = safe_addr(DEFAULT_REQUIRED_EXTENSIONS[0])
    ]]
    verify(VkResult VK_SUCCESS == vkCreateDevice(
        phys_dev, safe_addr(create_info), null, safe_addr(device)))
    var queue : VkQueue
    let qfam = phys_dev |> get_graphics_queue_family(surface)
    device |> vkGetDeviceQueue(qfam, 0u, queue |> safe_addr())
    b |> invoke(device, queue)
    device |> vkDeviceWaitIdle()
    device |> vkDestroyDevice(null)


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

