options log

require vulkan
require app

//TODO: try the following pattern: wrap all vulkan resources into das classes,
//  share them only via references, and never store pointers to them.
//  destroy the resources in finalizers.
//  like instance.physical_devices will add all physical devices and iterate
//  over them by references. then "delete instance" will destroy the devices.


class Instance
    __phys_devs : array<PhysicalDevice>
    __vk_instance : VkInstance

    def Instance
        self.__create_instance()
        self.__add_phys_devs()

    def __create_instance
        let inst_info <- [[VkInstanceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        ]]
        unsafe
            verify(VkResult VK_SUCCESS == vkCreateInstance(
                addr(inst_info), null, addr(self.__vk_inst)))

    def __add_phys_devs
        var devs:array<VkPhysicalDevice>
        unsafe
            var dev_cnt:uint
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                inst, addr(dev_cnt), null))
            devs |> resize(int(dev_cnt))
            verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
                inst, addr(dev_cnt), addr(devs[0])))
        for dev in devs
            phys_devs |> emplace(PhysicalDevice(dev))

    def finalize
        delete self.__phys_devs
        vkDestroyInstance(self.__vk_instance, null)


[export]
def main
    print("\nstarted\n")

    var inst_info <- [[VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]
    var inst:VkInstance
    unsafe
        verify(VkResult VK_SUCCESS == vkCreateInstance(
            addr(inst_info), null, addr(inst)))

    var devs:array<VkPhysicalDevice>
    unsafe
        var dev_cnt:uint
        verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
            inst, addr(dev_cnt), null))
        devs |> resize(int(dev_cnt))
        verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
            inst, addr(dev_cnt), addr(devs[0])))

    print("{length(devs)} devices found\n")

    for dev in devs
        var props:VkPhysicalDeviceProperties
        unsafe
            vkGetPhysicalDeviceProperties(dev, addr(props))
        print("got props\n")

    vkDestroyInstance(inst, null)

    var foo <- new Foo()
    delete *foo
    delete *foo

    var sm <- new SmartObject

    print("finished\n")
    return true
