options indenting = 4
options no_aot = true

module vulkan_boost

require vulkan
require daslib/safe_addr


//TODO: move to stdlib?
def to_string(bytes : int8[])
    unsafe
        return reinterpret<string>(addr(bytes[0]))


def to_string(bytes : void?)
    unsafe
        return reinterpret<string>(bytes)


//TODO: need this for heap
def safe_addr_plain(x : auto(T)) : T ? #
    unsafe
        return reinterpret<T?#>(addr(x))


//TODO: need this for heap
def safe_addr_val(var x : auto(T)&) : T-& ? #
    unsafe
        return reinterpret<T-&?#>(addr(x))


let
    REQUIRED_EXTENSIONS = [[auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ]]


def with_physical_devices(
    inst : VkInstance#; b : block<(d:array<VkPhysicalDevice>#)>
)
    var devices : array<VkPhysicalDevice>
    var count : uint
    verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
        safe_addr(count), null))
    devices |> resize(int(count))
    devices |> lock() <| $(tdevices)
        verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
            safe_addr(count), addr(tdevices[0])))
        b |> invoke(tdevices)
    delete devices


def with_best_physical_device(inst : VkInstance#; surface : VkSurfaceKHR#;
    b : block<(d:VkPhysicalDevice#)>
)
    inst |> with_physical_devices() <| $(devices)
        var best_score : int = 0
        var best_device : VkPhysicalDevice
        for device in devices
            var score = device |> get_suitability_score(surface)
            if score > best_score
                best_score = score
                best_device = device
        if best_score == 0
            panic("No suitable physical device found.")
        b |> invoke(best_device)


[private]
def get_suitability_score(device : VkPhysicalDevice#; surface : VkSurfaceKHR#)
    var score = 1

    var has_graphics = false
    device |> with_graphics_queue_family(surface) <| $(graphics_i)
        has_graphics = true
    if ! has_graphics
        score = 0
    
    var props <- device |> get_properties()
    if (props.deviceType ==
        VkPhysicalDeviceType VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    )
        score += 1000

    device |> with_ext_props() <| $(exts)
        for required_ext in REQUIRED_EXTENSIONS
            if ! key_exists(exts, hash(required_ext))
                score = 0
                break
    device |> with_formats(surface) <| $(formats)
        if formats |> length() == 0
            score = 0
    device |> with_present_modes(surface) <| $(modes)
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


def with_graphics_queue_family(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(index:uint)>
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


def get_properties(device : VkPhysicalDevice#)
    var props : VkPhysicalDeviceProperties
    device |> vkGetPhysicalDeviceProperties(safe_addr(props))
    return <- props


def with_ext_props(device : VkPhysicalDevice#;
    b : block<(props:table<uint;VkExtensionProperties>)>
)
    var props : array<VkExtensionProperties>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkEnumerateDeviceExtensionProperties(
            to_string(null), safe_addr(count), null))
    props |> resize(int(count))
    props |> lock() <| $(tprops)
        verify(VkResult VK_SUCCESS ==
            device |> vkEnumerateDeviceExtensionProperties(
                to_string(null), safe_addr(count), addr(tprops[0])))

    var props_table : table<uint; VkExtensionProperties>
    for prop in props
        let name <- prop.extensionName |> to_string()
        props_table[hash(name)] <- prop
    props_table |> lock() <| $(tprops_table)
        pass
        //TODO: make it work
        //b |> invoke(tprops_table)
    b |> invoke(props_table)
    delete props


def with_formats(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(formats:array<VkSurfaceFormatKHR>#)>
)
    var formats : array<VkSurfaceFormatKHR>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
            surface, safe_addr(count), null))
    formats |> resize(int(count))
    formats |> lock() <| $(tformats)
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
                surface, safe_addr(count), addr(tformats[0])))
        b |> invoke(tformats)
    delete formats


def with_best_format(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(format:VkSurfaceFormatKHR#)>
)
    device |> with_formats(surface) <| $(formats)
        // picking ideal format if available
        for format in formats
            if (format.format == VkFormat VK_FORMAT_B8G8R8A8_SRGB
            &&  format.colorSpace == (VkColorSpaceKHR
                    VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            )
                b |> invoke(format)
                return
        // if no ideal found, picking anything
        for format in formats
            b |> invoke(format)
            return


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


def with_best_present_mode(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(mode:VkPresentModeKHR#)>
)
    device |> with_present_modes(surface) <| $(modes)
        for preferred in [[auto[]
            VkPresentModeKHR VK_PRESENT_MODE_MAILBOX_KHR;
            VkPresentModeKHR VK_PRESENT_MODE_FIFO_KHR
        ]]
            for mode in modes
                if mode == preferred
                    b |> invoke(mode)
                    return


def with_window(width : int; height : int; title : string;
    b : block<(w:GLFWwindow_DasHandle#)>
)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    b |> invoke(window)
    window |> glfwDestroyWindow()


def with_instance(b : block<(inst:VkInstance#)>)
    var inst_info <- [[VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]

    let exts = glfwGetRequiredInstanceExtensions(
        safe_addr_val(inst_info.enabledExtensionCount))

    unsafe
        reinterpret<string const?>(inst_info.ppEnabledExtensionNames) = exts

    var instance : VkInstance
    verify(VkResult VK_SUCCESS == vkCreateInstance(
        safe_addr(inst_info), null, safe_addr(instance)))
    b |> invoke(instance)
    instance |> vkDestroyInstance(null)


def with_surface(window : GLFWwindow_DasHandle#; instance : VkInstance#;
    b : block<(s:VkSurfaceKHR#)>
)
    var surface : VkSurfaceKHR
    verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
        window, null, safe_addr(surface)))
    b |> invoke(surface)
    instance |> vkDestroySurfaceKHR(surface, null)
