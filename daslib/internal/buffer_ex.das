options indenting = 4
options no_aot = true

require vulkan
require buffer


let
    QUEUE_FAMILY_INDICES_EMPTY : array<uint>


def create_buffer_exclusive(
    device : VkDevice implicit;
    size : uint64;
    usage : uint;
    flags : uint = 0u
) : Buffer
    return <- create_buffer([device=device, size=size, usage=usage,
        sharing_mode=VkSharingMode VK_SHARING_MODE_EXCLUSIVE,
        queue_family_indices=QUEUE_FAMILY_INDICES_EMPTY,
        flags=flags])
