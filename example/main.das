options log

require vulkan
require app


class Instance
    
    phys_devs : array<PhysicalDevice>
    __vk_instance : VkInstance

    def Instance
        self.__init_instance()
        self.__init_phys_devs()

    def __create_instance
        let inst_info <- [[VkInstanceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        ]]
        unsafe
            verify(VkResult VK_SUCCESS == vkCreateInstance(
                addr(inst_info), null, addr(self.__vk_inst)))

    def __add_phys_devs
        var vk_devs : array<VkPhysicalDevice>
        unsafe
            var dev_cnt:uint
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                inst, addr(dev_cnt), null))
            vk_devs |> resize(int(dev_cnt))
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                inst, addr(dev_cnt), addr(vk_devs[0])))
        for d in vk_devs
            phys_devs |> emplace(PhysicalDevice(d))

    def finalize
        delete self.phys_devs
        vkDestroyInstance(self.__vk_instance, null)


class PhysicalDevice

    __vk_dev : VkPhysicalDevice
    __vk_props : VkPhysicalDeviceProperties

    def PhysicalDevice(vk_dev : VkPhysicalDevice)
        self.__vk_dev = vk_dev
        unsafe
            vkGetPhysicalDeviceProperties(self.__vk_dev, addr(self.__vk_props))


[export]
def main
    print("\nstarted\n")

    var inst <- [[Instance]]
    print("{length(inst.phys_devs)} devices found\n")
    delete inst

    print("finished\n")
    return true
