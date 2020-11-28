options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Buffer
    buffer  : VkBuffer
    _device : VkDevice


def create_buffer(
    device                  : VkDevice implicit; //TODO: remove implicit
    size                    : uint64;
    usage                   : uint;
    sharing_mode            : VkSharingMode;
    queue_family_indices    : array<uint> implicit;
    flags                   : uint = 0u;
    var result              : VkResult? = [[ VkResult? ]]
) : Buffer
    var buf : Buffer
    //TODO: remove reinterpret once implicit removed
    unsafe
        buf._device = reinterpret<VkDevice>(device)
    queue_family_indices |> lock_data() <| $(pindices, nindices)
        let info <- [[VkBufferCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            flags = flags,
            size = size,
            usage = usage,
            sharingMode = sharing_mode,
            queueFamilyIndexCount = uint(nindices),
            pQueueFamilyIndices = pindices
        ]]
        var result_ = VkResult VK_SUCCESS
        result ?? result_ = device |> vkCreateBuffer(
            safe_addr(info), null, safe_addr(buf.buffer))
        assert(result_ == VkResult VK_SUCCESS)
    return <- buf


def finalize(var buf : Buffer)
    buf._device |> vkDestroyBuffer(buf.buffer, null)
    memzero(buf)
