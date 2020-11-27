options indenting = 4
options no_aot = true

require daslib/safe_addr

require vulkan


def with_memory(
    device : VkDevice#;
    size : uint64;
    mem_type_index : uint;
    b : block<(m:VkDeviceMemory#)>
)
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type_index
    ]]
    var mem : VkDeviceMemory
    verify(VkResult VK_SUCCESS == device |> vkAllocateMemory(
        alloc_info |> safe_addr(), null, mem |> safe_addr()))
    b |> invoke(mem)
    device |> vkFreeMemory(mem, null)


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

