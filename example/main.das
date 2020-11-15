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
        let inst_info <- [[VkInstanceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        ]]
        unsafe
            verify(VkResult VK_SUCCESS == vkCreateInstance(
                addr(inst_info), null, addr(_vk_inst)))

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
        var bytes : array<uint8>
        for c in _vk_props.deviceName
            unsafe
                bytes |> emplace(reinterpret<uint8>(c))
        return string(bytes)

    def finalize
        print("physical device finalized\n")


[export]
def main
    print("\nstarted\n")

    glfwInit()

    var inst = new Instance()
    print("{length(inst.phys_devs)} devices found:\n")

    for dev in inst.phys_devs
        print("  {dev->name()}\n")

    unsafe
        delete inst

    glfwTerminate()

    print("finished\n")
    return true
