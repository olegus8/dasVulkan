options log

require vulkan

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

    var dev_cnt:uint
    unsafe
        verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
            inst, addr(dev_cnt), null))

    print("{int(dev_cnt)} devices found\n")

    vkDestroyInstance(inst, null)

    print("finished\n")
    return true
