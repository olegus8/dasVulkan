options log

require vulkan
require app


class Instance
    
    phys_devs : array<PhysicalDevice>
    _vk_inst : VkInstance

    def Instance
        self |> _init_instance()
        self |> _init_phys_devs()

    def _create_instance
        let inst_info <- [[VkInstanceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        ]]
        unsafe
            verify(VkResult VK_SUCCESS == vkCreateInstance(
                addr(inst_info), null, addr(self._vk_inst)))

    def _add_phys_devs
        var vk_devs : array<VkPhysicalDevice>
        unsafe
            var dev_cnt:uint
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                self._vk_inst, addr(dev_cnt), null))
            vk_devs |> resize(int(dev_cnt))
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                self._vk_inst, addr(dev_cnt), addr(vk_devs[0])))
        for d in vk_devs
            phys_devs |> emplace(PhysicalDevice(d))
        delete vk_devs

    def finalize
        delete self.phys_devs
        vkDestroyInstance(self._vk_inst, null)


class PhysicalDevice

    _vk_dev : VkPhysicalDevice
    _vk_props : VkPhysicalDeviceProperties

    def PhysicalDevice(vk_dev : VkPhysicalDevice)
        self._vk_dev = vk_dev
        unsafe
            vkGetPhysicalDeviceProperties(self._vk_dev, addr(self._vk_props))


[export]
def main
    print("\nstarted\n")

    var inst = new Instance()
    print("{length(inst.phys_devs)} devices found\n")
    delete *inst

    print("finished\n")
    return true
