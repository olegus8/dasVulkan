options log

require vulkan
require strings


def for_each_physical_device(instance : VkInstance; b : block)
    let MAX_DEVICES = 10
    var devices : VkPhysicalDevice[MAX_DEVICES]
    var dev_cnt:uint
    unsafe
        verify(VkResult VK_SUCCESS ==
            instance |> vkEnumeratePhysicalDevices(addr(dev_cnt), null))
        assert(dev_cnt < length(devices))
        verify(VkResult VK_SUCCESS ==
            instance |> vkEnumeratePhysicalDevices(
                addr(dev_cnt), addr(devices[0])))
    for i in range(dev_cnt)
        invoke(b, devices[i])


def to_string( bytes : int8[] )
    unsafe
        return reinterpret<string>(addr(bytes[0]))


def with_props(device : VkPhysicalDevice; b : block)
    var props : VkPhysicalDeviceProperties
    unsafe
        device |> vkGetPhysicalDeviceProperties(addr(_vk_props))
    b(props)


def with_window(width, height, title, b)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    invoke(b, window)
    window |> glfwDestroyWindow()


def with_instance(b)
    var inst_info <- [[VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]

    unsafe
        inst_info.ppEnabledExtensionNames = glfwGetRequiredInstanceExtensions(
            addr(inst_info.enabledExtensionCount))

    var instance : VkInstance
    unsafe
        verify(VkResult VK_SUCCESS == vkCreateInstance(
            addr(inst_info), null, addr(instance)))

    invoke(b, instance)

    instance |> vkDestroyInstance(null)


def with_surface(window, instance, b)
    var surface : VkSurfaceKHR
    unsafe
        verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
            window, null, addr(surface)))
    invoke(b, surface)
    instance |> vkDestroySurfaceKHR(surface, null)


[export]
def main
    print("started\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    with_window([width=800, height=600, title="dasVulkanExample"]) <| $(window)
        with_instance() <| $(instance)
            print("found following devices:\n")
            instance |> for_each_physical_device() <| $(device)
                device |> with_props <| $(props)
                    print("  {props.deviceName |> to_string()}\n")
            with_surface(window, instance) <| $(surface)
                while window |> glfwWindowShouldClose() != 0
                    glfwPollEvents()

    glfwTerminate()
    print("finished\n")
    return true
