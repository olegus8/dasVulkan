options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Buffer
    buffer  : VkBuffer
    _device : VkDevice


def create_buffer(
    device                  : VkDevice implicit;
    size                    : uint64;
    usage                   : uint;
    sharing_mode            : VkSharingMode;
    queue_family_indices    : array<uint> implicit;
    flags                   : uint = 0u;
    var result              : VkResult? = null
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
        var result_ = device |> vkCreateBuffer(
            safe_addr(info), null, safe_addr(buf.buffer))
        if result == null
            assert(result_ == VkResult VK_SUCCESS)
        else
            *result = result_
    return <- buf


def finalize(var buf : Buffer)
    buf._device |> vkDestroyBuffer(buf.buffer, null)
    memzero(buf)
