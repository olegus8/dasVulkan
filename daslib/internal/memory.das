options indenting = 4
options no_aot = true

require daslib/defer

require vulkan
require generated


def find_memory_type(
    phys_dev        : PhysicalDevice;
    type_filter     : uint;
    needed_flags    : uint;
    b : block<(t:uint)>
)
    var actual_props <- phys_dev |> get_physical_device_memory_properties()
    defer() <| ${ delete actual_props; }
    for mem_type, type_i in actual_props.memory_types, range(INT_MAX)
        if ((1u << uint(type_i)) & type_filter) == 0u
            continue
        let actual_flags = mem_type.property_flags
        if (actual_flags & needed_flags) == needed_flags
            b |> invoke(uint(type_i))
            return


def find_buffer_memory_type(
    device      : Device;
    phys_dev    : PhysicalDevice;
    buffer      : Buffer;
    mem_props   : uint;
    b : block<(mem_type:uint; mem_size:uint64)>
)
    let reqs <- device |> get_buffer_memory_requirements(buffer)
    phys_dev |> find_memory_type(reqs.memory_type_bits, mem_props
    ) <| $(mem_type)
        b |> invoke(mem_type, reqs.size)


def map_to_array(
    device  : Device;
    memory  : DeviceMemory;
    size    : uint64;
    offset  : uint64 = [[ uint64 ]];
    flags   : uint = [[ uint ]];
    b : block<(var a:array<auto(T)>#)>
)
    var mem_ptr = map_memory([
        device=device, memory=mem, offset=offset, size=size, flags=flags])
    unsafe
        mem_ptr |> map_to_array(int(size)) <| $(var mapped : array<T>#)
            b |> invoke(mapped)
    device |> unmap_memory(memory)
