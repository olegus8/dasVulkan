options indenting = 4
options no_aot = true

require vulkan
require generated


struct CommandBuffers
    command_buffers : array<CommandBuffer>
    _device : Device
    _command_pool : CommandPool
    _needs_delete : bool


def allocate_command_buffers(
    device : Device = [[ Device ]];
    var allocate_info : CommandBufferAllocateInfo = [[ CommandBufferAllocateInfo ]];
    var result : VkResult? = [[VkResult?]]
) : CommandBuffers
    var buffers <- [[ CommandBuffers
        _needs_delete = true,
        _device = weak_copy(device),
        _command_pool = weak_copy(allocate_info.command_pool)
    ]]
    buffers.command_buffers <- allocate_command_buffers__inner([
        device = device, allocate_info = allocate_info, result = result])
    return <- buffers


def finalize(var bufs : CommandBuffers explicit)
    if bufs._needs_delete
        bufs._device |> free_command_buffers(bufs._command_pool,
            bufs.command_buffers)
    delete bufs.command_buffers
    memzero(bufs)


def allocate_command_buffers_primary(
    device : Device;
    pool : CommandPool;
    count : int
) : CommandBuffers
    return <- device |> allocate_command_buffers([[
        CommandBufferAllocateInfo
            command_pool = pool,
            command_buffer_count = uint(count),
            level = VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY
        ]])


def create_command_pool(
    device : Device;
    queue_family : uint;
    flags : uint = 0u
) : CommandPool
    return <- device |> create_command_pool([[CommandPoolCreateInfo
        queue_family_index = queue_family,
        flags = flags
    ]])


def record_command_buffer_ex(
    command_buffer : CommandBuffer;
    var begin_info : CommandBufferBeginInfo = [[ CommandBufferBeginInfo ]];
    b : block
)
    command_buffer |> begin_command_buffer(begin_info)
    b |> invoke()
    command_buffer |> end_command_buffer()


def record_command_buffer(command_buffer : CommandBuffer; b : block)
    record_command_buffer_ex([command_buffer=command_buffer, b=b])
