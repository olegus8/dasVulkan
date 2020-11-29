options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Buffer
    buffer  : VkBuffer
    _device : VkDevice


def create_buffer(
    device                  : VkDevice;
    flags                   : uint          = [[uint]];
    size                    : uint64        = [[uint64]];
    usage                   : uint          = [[uint]];
    sharing_mode            : VkSharingMode = [[ VkSharingMode ]];
    queue_family_indices    : array<uint> implicit = [[array<uint>]];
    var result              : VkResult?     = [[ VkResult? ]]
) : Buffer
    var buf <- [[Buffer _device=device]]
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


def get_buffer_memory_requirements(buffer : Buffer) : VkMemoryRequirements
    var reqs : VkMemoryRequirements
    buffer._device |> vkGetBufferMemoryRequirements(
        buffer.buffer, safe_addr(reqs))
    return <- reqs
    
