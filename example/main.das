options log

require vulkan
require strings


def for_each_physical_device(inst : VkInstance; b : block<(d:VkPhysicalDevice)>)
    inst |> with_physical_devices() <| $(devices)
        for device in devices
            invoke(b, device)


def with_physical_devices(inst : VkInstance; b : block<(d:array<VkPhysicalDevice>)>)
    var devices : array<VkPhysicalDevice>
    var count : uint
    unsafe
        verify(VkResult VK_SUCCESS ==
            inst |> vkEnumeratePhysicalDevices(addr(count), null))
        devices |> resize(int(count))
        verify(VkResult VK_SUCCESS ==
            inst |> vkEnumeratePhysicalDevices(addr(count), addr(devices[0])))
    invoke(b, devices)


def with_best_physical_device(inst : VkInstance; surface : VkSurfaceKHR; b : block<(d:VkPhysicalDevice)>)
    inst |> with_physical_devices() <| $(devices)
        var best_score : int = 0
        var best_device : VkPhysicalDevice
        for device in devices
            var score = device |> get_suitability_score()
            device |> with_queue_family_present(surface) <| $(present_i)
                device |> with_queue_family_graphics() <| $(graphics_i)
                    if score > best_score
                        best_score = score
                        best_device = device
        if best_score == 0
            panic("No suitable physical device found.")
        invoke(b, best_device)


def with_queue_families(device : VkPhysicalDevice; b : block<(families: array<VkQueueFamilyProperties>)>)
    var families : array<VkQueueFamilyProperties>
    var count : uint
    unsafe
        device |> vkGetPhysicalDeviceQueueFamilyProperties(addr(count), null)
        families |> resize(int(count))
        device |> vkGetPhysicalDeviceQueueFamilyProperties(
            addr(count), addr(families[0]))
    invoke(b, families)


def with_queue_family_present(device : VkPhysicalDevice; surface : VkSurfaceKHR; b : block<(index:uint)>)
    device |> with_queue_families() <| $(families)
        for index in range(families |> length())
            var supported : uint = 0u
            unsafe
                verify(VkResult VK_SUCCESS ==
                    device |> vkGetPhysicalDeviceSurfaceSupportKHR(
                        uint(index), surface, addr(supported)))
            if supported != 0u
                invoke(b, uint(index))
                break


def with_queue_family_graphics(device : VkPhysicalDevice; b : block<(index:uint)>)
    device |> with_queue_families() <| $(families)
        for index, family in range(families |> length()), families
            var graphics_bit : uint
            unsafe
                graphics_bit = reinterpret<uint>(
                    VkQueueFlagBits VK_QUEUE_GRAPHICS_BIT)
            if (family.queueFlags & graphics_bit) != 0u
                invoke(b, uint(index))
                break


def get_suitability_score(device : VkPhysicalDevice)
    var score = 1
    device |> with_props() <| $(props : VkPhysicalDeviceProperties)
        if (props.deviceType ==
            VkPhysicalDeviceType VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
        )
            score += 1000
    return score


def to_string( bytes : int8[] )
    unsafe
        return reinterpret<string>(addr(bytes[0]))


def with_props(device : VkPhysicalDevice; b : block<(p:VkPhysicalDeviceProperties)>)
    var props : VkPhysicalDeviceProperties
    unsafe
        device |> vkGetPhysicalDeviceProperties(addr(props))
    invoke(b, props)


def with_window(width, height, title; b : block<(w:GLFWwindow_DasHandle)>)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    invoke(b, window)
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

    invoke(b, instance)

    instance |> vkDestroyInstance(null)


def with_surface(window, instance; b : block<(s:VkSurfaceKHR)>)
    var surface : VkSurfaceKHR
    unsafe
        verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
            window, null, addr(surface)))
    invoke(b, surface)
    instance |> vkDestroySurfaceKHR(surface, null)


[export]
def main
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    with_instance() <| $(instance)
        with_window(800, 600, "dasVulkanExample") <| $(window)
            with_surface(window, instance) <| $(surface)
                instance |> with_best_physical_device(surface) <| $(device)
                    device |> with_props() <| $(props)
                        print("Using {props.deviceName |> to_string()}\n")
                    while window |> glfwWindowShouldClose() == 0
                        glfwPollEvents()

    glfwTerminate()
    print("Finished\n")
    return true
