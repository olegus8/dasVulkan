options log

require vulkan

class Foo
    x, y : int = 0
    [export] def Foo
        Foo`set(self,1,1)
    def set(X,Y:int)
        x = X
        y = Y
    def finalize
        print("finalized\n")

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

    vkDestroyInstance(inst, null)

    var f = new Foo()
    delete *f

    print("finished\n")
    return true
