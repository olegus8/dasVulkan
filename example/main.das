options log

require vulkan
require strings


let physical_devices <- generator<VkPhysicalDevice>(instance : VkInstance) <|
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
        yield devices[i]


def to_string( bytes : int8[] )
    unsafe
        return reinterpret<string>(addr(bytes[0]))


def get_required_extensions()
    var exts_array : array<string>
    var ext_count : uint
    var exts : string const ?
    unsafe
        exts = glfwGetRequiredInstanceExtensions(addr(ext_count))
    
    exts_array |> reserve(int(ext_count))
    for i in range(ext_count)
        unsafe
            exts_array |> push(exts[i])
    return <- exts_array


def with_props(device : VkPhysicalDevice&, b : block)
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

    let exts <- get_required_extensions()
    inst_info.enabledExtensionCount = uint(length(exts))
    unsafe
        reinterpret<string const ?>(inst_info.ppEnabledExtensionNames) = (
            addr(exts[0]))

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
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    with_window([width=800, height=600, title="dasVulkanExample"]) <| $(window)
        with_instance() <| $(instance)
            print("found following devices:\n"
            //TODO: try iterator here
            //for dev in instance |> physical_devices
            //    print("  {dev->name()}\n")
            with_surface(window, instance) <| $(surface)
                while window |> glfwWindowShouldClose() != 0
                    glfwPollEvents()

    glfwTerminate()
    return true
