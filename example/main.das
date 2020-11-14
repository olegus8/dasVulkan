options log

require vulkan

typedef
    UIntPtr = smart_ptr<uint>

[export]
def main
    print("\nstarted\n")
    // enums
    assert(VkResult VK_SUCCESS == VkResult VK_SUCCESS)
    assert(VkResult VK_SUCCESS != VkResult VK_NOT_READY)

    // structs
    let offset2d <- [[VkOffset2D x=1]]
    let offset3d <- [[VkOffset3D x=2]]
    assert(offset2d.x * 2 == offset3d.x)

    // bit fields
    var asi <- [[VkAccelerationStructureInstanceKHR]]
    VkAccelerationStructureInstanceKHR_set_mask(asi, 123u)
    assert(VkAccelerationStructureInstanceKHR_get_mask(asi) == 123u)

    var inst_info <- new [[VkInstanceCreateInfo()
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]
    var inst <- new VkInstance
    verify(VkResult VK_SUCCESS == vkCreateInstance(inst_info, null, inst))

    var dev_cnt:uint
    unsafe
        verify(VkResult VK_SUCCESS == vkEnumeratePhysicalDevices(
            *inst, addr(dev_cnt), null))

    vkDestroyInstance(*inst, null)

    print("finished\n")
    return true
