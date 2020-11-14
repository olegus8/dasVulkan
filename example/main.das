options log

require vulkan
require app

//TODO: try the following pattern: wrap all vulkan resources into das classes,
//  share them only via references, and never store pointers to them.
//  destroy the resources in finalizers.
//  like instance.physical_devices will add all physical devices and iterate
//  over them by references. then "delete instance" will destroy the devices.

class Foo
    x, y : int = 0
    finalized : bool = false
    def finalize
        if ! self.finalized
            print("finalized\n")
            self.finalized = true
        else
            print("already finalized\n")

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
