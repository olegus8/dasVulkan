options indenting = 4
options no_aot = true

require daslib/safe_addr

require vulkan
require memory
require generated


def find_memory_type(
    phys_dev        : VkPhysicalDevice implicit;
    type_filter     : uint;
    needed_flags    : uint;
    b : block<(t:uint)>
)
    var actual_props : VkPhysicalDeviceMemoryProperties
    phys_dev |> vkGetPhysicalDeviceMemoryProperties(safe_addr(actual_props))
    for type_i in range(actual_props.memoryTypeCount)
        if ((1u << uint(type_i)) & type_filter) == 0u
            continue
        let actual_flags = actual_props.memoryTypes[type_i].propertyFlags
        if (actual_flags & needed_flags) == needed_flags
            b |> invoke(uint(type_i))
            return


def find_buffer_memory_type(
    device      : Device;
    phys_dev    : VkPhysicalDevice;
    buffer      : Buffer;
    mem_props   : uint;
    b : block<(mem_type:uint; mem_size:uint64)>
)
    let reqs <- device |> get_buffer_memory_requirements(buffer)
    phys_dev |> find_memory_type(reqs.memoryTypeBits, mem_props) <| $(mem_type)
        b |> invoke(mem_type, reqs.size)
