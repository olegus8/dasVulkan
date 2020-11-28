options indenting = 4
options no_aot = true

require daslib/safe_addr

require vulkan


struct Memory
    memory  : VkDeviceMemory
    _device : VkDevice


def allocate_memory(
    device          : VkDevice;
    allocation_size : uint64;
    mem_type_index  : uint;
    var result      : VkResult? = [[ VkResult? ]]
) : Memory
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = allocation_size,
        memoryTypeIndex = mem_type_index
    ]]
    var mem <- [[Memory _device=device]]
    var result_ = VkResult VK_SUCCESS
    result ?? result_ = device |> vkAllocateMemory(
        safe_addr(alloc_info), null, safe_addr(mem.memory))
    assert(result_ == VkResult VK_SUCCESS)
    return <- mem


def finalize(var mem : Memory)
    mem._device |> vkFreeMemory(mem.memory, null)
    memzero(mem)
