options log, log_infer_passes

require vulkan
require strings


let
    REQUIRED_EXTENSIONS = [[auto[]
        "VK_KHR_swapchain"
    ]]


def with_physical_devices(inst; b : block<(d:array<VkPhysicalDevice>)>)
    var devices : array<VkPhysicalDevice>
    var count : uint
    unsafe
        verify(VkResult VK_SUCCESS ==
            inst |> vkEnumeratePhysicalDevices(addr(count), null))
        devices |> resize(int(count))
        verify(VkResult VK_SUCCESS ==
            inst |> vkEnumeratePhysicalDevices(addr(count), addr(devices[0])))
    b |> invoke(devices)
    delete devices


def with_best_physical_device(inst, surface; b : block<(d:VkPhysicalDevice)>)
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


def get_suitability_score(device, surface)
    var score = 1

    var has_graphics = false
    device |> with_graphics_queue_family(surface) <| $(graphics_i)
        has_graphics = true
    if ! has_graphics
        score = 0
    
    device |> with_props() <| $(props)
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


def with_queue_families(
    device; b : block<(families: array<VkQueueFamilyProperties>)>
)
    var families : array<VkQueueFamilyProperties>
    var count : uint
    unsafe
        device |> vkGetPhysicalDeviceQueueFamilyProperties(addr(count), null)
        families |> resize(int(count))
        device |> vkGetPhysicalDeviceQueueFamilyProperties(
            addr(count), addr(families[0]))
    b |> invoke(families)
    delete families


def with_graphics_queue_family(device, surface; b : block<(index:uint)>)
    var found_index = -1
    device |> with_queue_families() <| $(families)
        for family, index in families, range(INT_MAX)
            var can_present : uint
            var graphics_bit : uint
            unsafe
                verify(VkResult VK_SUCCESS ==
                    device |> vkGetPhysicalDeviceSurfaceSupportKHR(
                        uint(index), surface, addr(can_present)))
                graphics_bit = reinterpret<uint>(
                    VkQueueFlagBits VK_QUEUE_GRAPHICS_BIT)
            if (family.queueFlags & graphics_bit) != 0u && can_present != 0u
                found_index = index
                break
    if found_index != -1
        b |> invoke(uint(found_index))


def to_string( bytes : int8[] )
    unsafe
        return reinterpret<string>(addr(bytes[0]))


def with_device(instance, phys_dev, surface; b : block<(device:VkDevice)>)
    phys_dev |> with_queue_create_infos(surface) <| $(queue_infos)
        let features : VkPhysicalDeviceFeatures
        var device : VkDevice
        unsafe
            let create_info = [[VkDeviceCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO),
                pQueueCreateInfos = addr(queue_infos[0]),
                queueCreateInfoCount = uint(queue_infos |> length()),
                pEnabledFeatures = addr(features),
                enabledExtensionCount = uint(
                    REQUIRED_EXTENSIONS |> length()),
                ppEnabledExtensionNames = reinterpret<string?>(
                    addr(REQUIRED_EXTENSIONS[0]))
            ]]
            verify(VkResult VK_SUCCESS == vkCreateDevice(
                phys_dev, addr(create_info), null, addr(device)))
        b |> invoke(device)
        device |> vkDeviceWaitIdle()
        device |> vkDestroyDevice(null)


def with_queue_create_infos(device, surface;
    b : block<(infos:array<VkDeviceQueueCreateInfo>)>
)
    var families : array<uint>
    device |> with_graphics_queue_family(surface) <| $(qfam)
        families |> push(qfam)

    var priorities : array<float>
    priorities |> reserve(families |> length())
    for family in families
        priorities |> push(1.0f)

    var priorities_addr : float?
    unsafe
        priorities_addr = reinterpret<float?>(addr(priorities[0]))

    var infos : array<VkDeviceQueueCreateInfo>
    infos |> reserve(families |> length())
    for family in families
        infos |> emplace([[
            VkDeviceQueueCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO),
                queueFamilyIndex = family,
                queueCount = uint(priorities |> length()),
                pQueuePriorities = priorities_addr
        ]])

    b |> invoke(infos)

    delete families
    delete priorities
    delete infos


def with_formats(device, surface;
    b : block<(formats:array<VkSurfaceFormatKHR>)>
)
    var formats : array<VkSurfaceFormatKHR>
    var count : uint
    unsafe
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
                surface, addr(count), null))
        formats |> resize(int(count))
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
                surface, addr(count), addr(formats[0])))
    b |> invoke(formats)
    delete formats


def with_present_modes(device, surface;
    b : block<(formats:array<VkPresentModeKHR>)>
)
    var modes : array<VkPresentModeKHR>
    var count : uint
    unsafe
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
                surface, addr(count), null))
        modes |> resize(int(count))
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
                surface, addr(count), addr(modes[0])))
    b |> invoke(modes)
    delete modes


def with_ext_props(device;
    b : block<(props:table<uint;VkExtensionProperties>)>
)
    var props : array<VkExtensionProperties>
    var count : uint
    unsafe
        verify(VkResult VK_SUCCESS ==
            device |> vkEnumerateDeviceExtensionProperties(
                reinterpret<string>(null), addr(count), null))
        props |> resize(int(count))
        verify(VkResult VK_SUCCESS ==
            device |> vkEnumerateDeviceExtensionProperties(
                reinterpret<string>(null), addr(count), addr(props[0])))

    var props_table : table<uint; VkExtensionProperties>
    for prop in props
        let name <- prop.extensionName |> to_string()
        props_table[hash(name)] <- prop
    b |> invoke(props_table)
    delete props


def with_props(device; b : block<(p:VkPhysicalDeviceProperties)>)
    var props : VkPhysicalDeviceProperties
    unsafe
        device |> vkGetPhysicalDeviceProperties(addr(props))
    b |> invoke(props)


def with_window(width, height, title; b : block<(w:GLFWwindow_DasHandle)>)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    b |> invoke(window)
    window |> glfwDestroyWindow()


def with_instance(b : block<(inst:VkInstance)>)
    var inst_info <- [[VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]

    unsafe
        reinterpret<string const ?>(inst_info.ppEnabledExtensionNames) = (
            glfwGetRequiredInstanceExtensions(
                addr(inst_info.enabledExtensionCount)))

    var instance : VkInstance
    unsafe
        verify(VkResult VK_SUCCESS == vkCreateInstance(
            addr(inst_info), null, addr(instance)))

    b |> invoke(instance)

    instance |> vkDestroyInstance(null)


def with_surface(window, instance; b : block<(s:VkSurfaceKHR)>)
    var surface : VkSurfaceKHR
    unsafe
        verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
            window, null, addr(surface)))
    b |> invoke(surface)
    instance |> vkDestroySurfaceKHR(surface, null)


def with_swap_chain(device, phys_dev, surface; b : block<(sc:VkSwapchainKHR)>)
    
    //TODO: create swapchain
    b |> invoke([[VkSwapchainKHR]])

def with_graphics(width, height, title; b : block<(
    instance : VkInstance;
    window : GLFWwindow_DasHandle;
    surface : VkSurfaceKHR;
    phys_dev : VkPhysicalDevice;
    device : VkDevice;
    swap_chain : VkSwapchainKHR
)>)
    with_instance() <| $(instance)
        with_window(width, height, title) <| $(window)
            window |> with_surface(instance) <| $(surface)
                instance |> with_best_physical_device(surface) <| $(phys_dev)
                    instance |> with_device(phys_dev, surface) <| $(device)
                        device |> with_swap_chain(phys_dev, surface) <| $(swap_chain)
                            b |> invoke(instance, window, surface, phys_dev,
                                device, swap_chain)

[export]
def main
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    with_graphics(800, 600, "dasVulkanExample") <| $(
        instance, window, surface, phys_dev, device, swap_chain
    )
        phys_dev |> with_props() <| $(props)
            print("Using {props.deviceName |> to_string()}\n")
        while window |> glfwWindowShouldClose() == 0
            glfwPollEvents()

    glfwTerminate()
    print("Finished\n")
    return true
