options log

require vulkan
require strings


class Instance
    
    phys_devs : array<PhysicalDevice?>
    _vk_inst : VkInstance

    def Instance
        self->_init_instance()
        self->_init_phys_devs()

    def _init_instance
        var inst_info <- [[VkInstanceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        ]]

        let exts <- get_required_extensions()
        inst_info.enabledExtensionCount = uint(length(exts))
        unsafe
            reinterpret<string const ?>(inst_info.ppEnabledExtensionNames) = (
                addr(exts[0]))

        unsafe
            verify(VkResult VK_SUCCESS == vkCreateInstance(
                addr(inst_info), null, addr(_vk_inst)))

    def _init_phys_devs
        var vk_devs : array<VkPhysicalDevice>
        unsafe
            var dev_cnt:uint
            verify(VkResult VK_SUCCESS ==
                _vk_inst |> vkEnumeratePhysicalDevices(addr(dev_cnt), null))
            vk_devs |> resize(int(dev_cnt))
            verify(VkResult VK_SUCCESS ==
                _vk_inst |> vkEnumeratePhysicalDevices(
                    addr(dev_cnt), addr(vk_devs[0])))
        for d in vk_devs
            phys_devs |> emplace(new PhysicalDevice(d))
        delete vk_devs

    def finalize
        delete phys_devs
        _vk_inst |> vkDestroyInstance(null)
        print("instance finalized\n")


class PhysicalDevice

    _vk_dev : VkPhysicalDevice
    _vk_props : VkPhysicalDeviceProperties

    def PhysicalDevice(vk_dev : VkPhysicalDevice)
        _vk_dev = vk_dev
        unsafe
            _vk_dev |> vkGetPhysicalDeviceProperties(addr(_vk_props))

    def name
        return _vk_props.deviceName |> to_string

    def finalize
        print("physical device finalized\n")


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


class Window

    _glfw_window : GLFWwindow_DasHandle

    def Window(width, height : int; title : string)
        _glfw_window = glfwCreateWindow(width, height, title,
            [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])

    def should_close
        return _glfw_window |> glfwWindowShouldClose() != 0

    def finalize
        _glfw_window |> glfwDestroyWindow()


class Surface

    _window : Window?
    _instance : Instance?
    _vk_surface : VkSurfaceKHR

    def Surface(window : Window?; instance : Instance?)
        _window = window
        _instance = instance
        unsafe
            verify(VkResult VK_SUCCESS ==
                _instance._vk_inst |> glfwCreateWindowSurface(
                    window._glfw_window, null, addr(_vk_surface)))

    def finalize
        _instance._vk_inst |> vkDestroySurfaceKHR(_vk_surface, null)


class HelloTriangleApp

    HEIGHT : int = 600
    WIDTH : int = 800

    _instance : Instance?
    _window : Window?
    _surface : Surface?

    def run
        self->_init_window()
        self->_init_vulkan()
        self->_main_loop()
        self->_cleanup()

    def _init_window
        glfwInit()
        glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
        glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)
        _window = new Window(width=WIDTH, height=HEIGHT,
            title="dasVulkanExample")

    def _init_vulkan
        _instance = new Instance()
        print("{length(inst.phys_devs)} devices found:\n")
        for dev in _instance.phys_devs
            print("  {dev->name()}\n")

        _surface = new Surface(window=_window, instance=_instance)

    def _main_loop
        while ! window->should_close()
            glfwPollEvents()

    def _cleanup
        unsafe
            delete _surface
            delete _instance
            delete _window
        glfwTerminate()


[export]
def main
    print("\nstarted\n")

    var app = new HelloTriangleApp()
    app->run()
    unsafe
        delete app

    print("finished\n")
    return true
