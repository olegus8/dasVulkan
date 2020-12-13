options indenting = 4
options no_aot = true

require vulkan


def create_buffer_exclusive(
    device  : Device;
    size    : uint64;
    usage   : uint;
    flags   : uint = 0u
) : Buffer
    return <- create_buffer([device=device, [[BufferCreateInfo
        flags=flags, size=size, usage=usage,
        sharing_mode=VkSharingMode VK_SHARING_MODE_EXCLUSIVE,
    ]]])
