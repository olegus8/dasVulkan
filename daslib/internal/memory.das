options indenting = 4
options no_aot = true

require daslib/safe_addr

require vulkan


struct Memory
    memory : VkDeviceMemory
    _device : VkDevice
    _result : VkResult


def allocate_memory(
    device          : VkDevice implicit;
    allocation_size : uint64;
    mem_type_index  : uint;
    require_success : bool = true
) : Memory
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = allocation_size,
        memoryTypeIndex = mem_type_index
    ]]
    var mem : Memory
    unsafe
        mem._device = reinterpret<VkDevice>(device)
    mem._result = device |> vkAllocateMemory(
        safe_addr(alloc_info), null, safe_addr(mem.memory))
    assert(!require_success || mem._result == VkResult VK_SUCCESS)
    return <- mem


def finalize(var mem : Memory)
    mem._device |> vkFreeMemory(mem.memory, null)
    memzero(mem)
