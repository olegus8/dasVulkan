options log

require vulkan
require strings


class Instance
    
    phys_devs : array<PhysicalDevice?>
    _vk_inst : VkInstance
    surface : Surface

    def Instance
        self->_init_instance()
        self->_init_surface()
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

    def _init_surface
        _vk_surface : VkSurfaceKHR
        unsafe
            verify(VkResult VK_SUCCESS == glfwCreateWindowSurface(
                inst._vk_inst, window, null, addr(surface)))
        vkDestroySurfaceKHR(inst._vk_inst, surface, null)
        surface = [[VkSurfaceKHR]]

    def _init_phys_devs
        var vk_devs : array<VkPhysicalDevice>
        unsafe
            var dev_cnt:uint
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                _vk_inst, addr(dev_cnt), null))
            vk_devs |> resize(int(dev_cnt))
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                _vk_inst, addr(dev_cnt), addr(vk_devs[0])))
        for d in vk_devs
            phys_devs |> emplace(new PhysicalDevice(d))
        delete vk_devs

    def finalize
        delete phys_devs
        vkDestroyInstance(_vk_inst, null)
        print("instance finalized\n")


class PhysicalDevice

    _vk_dev : VkPhysicalDevice
    _vk_props : VkPhysicalDeviceProperties

    def PhysicalDevice(vk_dev : VkPhysicalDevice)
        _vk_dev = vk_dev
        unsafe
            vkGetPhysicalDeviceProperties(_vk_dev, addr(_vk_props))

    def name
        return to_string(_vk_props.deviceName)

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

    def Window(width, height, title)
        _glfw_window = glfwCreateWindow(width, height, title,
            [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])

    def should_close
        return _glfw_window |> glfwWindowShouldClose != 0

    def finalize
        _glfw_window |> glfwDestroyWindow


class HelloTriangleApp

    height : 600
    width : 800

    _instance : Instance?
    _window : Window?

    def run
        self->_init_window()
        self->_init_vulkan()
        self->_main_loop()
        self->_cleanup()

    def _init_window
        glfwInit()
        glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
        glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)
        _window = new Window(width=width, height=height,
            title="dasVulkanExample")

    def _init_vulkan
        _instance = new Instance()
        print("{length(inst.phys_devs)} devices found:\n")
        for dev in _instance.phys_devs
            print("  {dev->name()}\n")

    def _main_loop
        while ! window->should_close()
            glfwPollEvents()

    def _cleanup
        unsafe
            delete _instance
        unsafe
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
