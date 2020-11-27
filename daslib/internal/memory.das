options indenting = 4
options no_aot = true

require daslib/safe_addr

require vulkan


struct Memory
    device : VkDevice
    memory : VkDeviceMemory


def allocate_memory(
    device : VkDevice#;
    size : uint64;
    mem_type_index : uint
) : Memory
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type_index
    ]]
    var mem : Memory
    unsafe
        mem.device = reinterpret<VkDevice>(device)
    verify(VkResult VK_SUCCESS == device |> vkAllocateMemory(
        safe_addr(alloc_info), null, safe_addr(mem.memory)))
    return <- mem


def finalize(var mem : Memory)
    mem.device |> vkFreeMemory(mem.memory, null)
    memzero(mem)


def with_memory(
    device : VkDevice#;
    size : uint64;
    mem_type_index : uint;
    b : block<(m:VkDeviceMemory#)>
)
    var mem <- allocate_memory(device, size, mem_type_index)
    b |> invoke(mem.memory)
    delete mem


def with_memory_type(
    phys_dev : VkPhysicalDevice#;
    type_filter : uint;
    needed_flags : uint;
    b : block<(t:uint)>
)
    var actual_props : VkPhysicalDeviceMemoryProperties
    phys_dev |> vkGetPhysicalDeviceMemoryProperties(
        actual_props |> safe_addr())
    for type_i in range(actual_props.memoryTypeCount)
        if ((1u << uint(type_i)) & type_filter) == 0u
            continue
        let actual_flags = actual_props.memoryTypes[type_i].propertyFlags
        if (actual_flags & needed_flags) == needed_flags
            b |> invoke(uint(type_i))
            return


def with_buffer_memory_type(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    buffer : VkBuffer#;
    mem_props : uint;
    b : block<(mem_type:uint; mem_size:uint64)>
)
    var mem_reqs : VkMemoryRequirements
    device |> vkGetBufferMemoryRequirements(buffer, mem_reqs |> safe_addr())
    phys_dev |> with_memory_type(mem_reqs.memoryTypeBits, mem_props
    ) <| $(mem_type)
        b |> invoke(mem_type, mem_reqs.size)

