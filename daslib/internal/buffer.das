options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Buffer
    device : VkDevice
    buffer : VkBuffer


def create_buffer(
    device : VkDevice#;
    buf_size : uint64;
    usage : uint
) : Buffer
    let create_info <- [[VkBufferCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        size = buf_size,
        usage = usage,
        sharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE
    ]]
    var buf : Buffer
    unsafe
        buf.device = reinterpret<VkDevice>(device)
    verify(VkResult VK_SUCCESS == device |> vkCreateBuffer(
        safe_addr(create_info), null, safe_addr(buf.buffer)))
    return <- buf


def finalize(var buf : Buffer)
    buf.device |> vkDestroyBuffer(buf.buffer, null)
    memzero(buf)
