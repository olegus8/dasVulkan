options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Buffer
    buffer : VkBuffer
    _device : VkDevice
    _creation_result : VkResult


def create_buffer(
    device : VkDevice implicit;
    size : uint64;
    usage : uint;
    sharing_mode : VkSharingMode;
    queue_family_indices : array<uint> implicit;
    flags : uint = 0u;
    require_success : bool = true
) : Buffer
    var buf : Buffer
    unsafe
        buf._device = reinterpret<VkDevice>(device)
    queue_family_indices |> lock() <| $(tindices)
        var pindices : uint const?
        if tindices |> length() > 0
            //TODO does not work without reinterpret, saying this:
            //  can only copy compatible type, uint const?& -const
            //      = uint const#? const#
            unsafe
                pindices = reinterpret<uint const?>(addr(tindices[0]))
        let info <- [[VkBufferCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            flags = flags,
            size = size,
            usage = usage,
            sharingMode = sharing_mode,
            queueFamilyIndexCount = uint(queue_family_indices |> length()),
            pQueueFamilyIndices = pindices
        ]]
        buf._creation_result = device |> vkCreateBuffer(
            safe_addr(info), null, safe_addr(buf.buffer))
        assert(!require_success || buf._creation_result == VkResult VK_SUCCESS)
    return <- buf


def finalize(var buf : Buffer)
    buf._device |> vkDestroyBuffer(buf.buffer, null)
    memzero(buf)
