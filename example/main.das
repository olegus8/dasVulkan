options log

require vulkan
require strings


class Instance
    
    phys_devs : array<PhysicalDevice?>
    _instance : VkInstance

    def Instance
        self->_init_instance()
        self->_init_phys_devs()

    def _init_instance

    def _init_phys_devs
        var vk_devs : array<VkPhysicalDevice>
        unsafe
            var dev_cnt:uint
            verify(VkResult VK_SUCCESS ==
                _instance |> vkEnumeratePhysicalDevices(addr(dev_cnt), null))
            vk_devs |> resize(int(dev_cnt))
            verify(VkResult VK_SUCCESS ==
                _instance |> vkEnumeratePhysicalDevices(
                    addr(dev_cnt), addr(vk_devs[0])))
        for d in vk_devs
            phys_devs |> emplace(new PhysicalDevice(d))
        delete vk_devs

    def finalize
        delete phys_devs
        _instance |> vkDestroyInstance(null)
        print("instance finalized\n")


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
