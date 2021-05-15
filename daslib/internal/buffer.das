options indenting = 4
options no_aot = true

require vulkan
require generated


def create_buffer_exclusive(
    device  : Device;
    size    : uint64;
    usage   : uint;
    flags   : uint = 0u
) : Buffer
    return <- device |> create_buffer([[BufferCreateInfo
        flags=flags, size=size, usage=usage,
        sharing_mode=VkSharingMode VK_SHARING_MODE_EXCLUSIVE
    ]])

def get_buffer_device_address(device : Device; buffer : Buffer
) : VkDeviceAddress
    var info <- [[ BufferDeviceAddressInfo buffer <- weak_copy(buffer) ]]
    return device |> get_buffer_device_address <| info
