options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require vulkan
require generated
require device
require window


struct QueueEx
    queue           : Queue
    family          : uint
    cmd_pool        : CommandPool
    _sems_to_wait   : array<Semaphore>  // must be weak copies
    _submits        : array<SubmitInfo> // must be weak copies
    _device         : Device

def finalize(var q : QueueEx & explicit)
    delete q.cmd_pool
    delete q.queue
    delete q._sems_to_wait
    delete q._submits
    memzero(q)


def create_queue_ex(device : Device; family : uint; index : uint=0u)
    return <- [[ QueueEx
        queue <- device |> get_device_queue(family, index),
        family = family,
        cmd_pool <- create_command_pool([device=device, queue_family=family]),
        _device <- weak_copy(device)
    ]]


def emplace(var queue : QueueEx; var info : SubmitInfo)
    for sem in queue._sems_to_wait
        info.wait_semaphores |> emplace <| sem
    queue._sems_to_wait |> clear
    queue._submits |> emplace <| info


def wait_in_next_emplace(var queue : QueueEx; var sem : Semaphore)
    queue._sems_to_wait |> emplace <| sem


def submit(var queue : QueueEx; fence_to_signal : Fence = [[ Fence ]])
    queue._device |> queue_submit(queue._submits, fence_to_signal)
    queue._submits |> clear


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


def allocate_command_buffer_primary(
    device : Device;
    pool : CommandPool
) : CommandBuffers
    return <- device |> allocate_command_buffers_primary(pool, 1)


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


def record_render_pass_ex(
    command_buffer          : CommandBuffer;
    var render_pass_begin   : RenderPassBeginInfo;
    contents                : VkSubpassContents;
    b : block
)
    command_buffer |> cmd_begin_render_pass(render_pass_begin)
    b |> invoke()
    command_buffer |> cmd_end_render_pass()


def record_render_pass(
    command_buffer  : CommandBuffer;
    physical_device : PhysicalDevice;
    render_pass     : RenderPass;
    framebuffer     : Framebuffer;
    extent          : int2;
    clear_values    : array<VkClearValue>;
    b : block
)
    var info <- [[RenderPassBeginInfo
        render_pass = weak_copy(render_pass),
        framebuffer = weak_copy(framebuffer),
        render_area = [[ Rect2D extent <- [[ Extent2D
            width=uint(extent.x), height=uint(extent.y) ]] ]],
        clear_values <- clone_to_move(clear_values)
    ]]
    defer() <| ${ delete info; }
    let contents = VkSubpassContents VK_SUBPASS_CONTENTS_INLINE
    command_buffer |> record_render_pass_ex(info, contents, b)


def queue_submit_ex(
    queue               : Queue;
    command_buffers     : CommandBuffers;
    wait_semaphores     : array<Semaphore> = [[ array<Semaphore> ]];
    wait_dst_stage_mask : array<uint> = [[ array<uint> ]];
    signal_semaphores   : array<Semaphore> = [[ array<Semaphore> ]];
    fence               : Fence = [[ Fence ]];
    var result          : VkResult? = [[VkResult?]]
)
    var submits <- [{ auto[] [[SubmitInfo
        wait_semaphores := wait_semaphores,
        wait_dst_stage_mask := wait_dst_stage_mask,
        command_buffers := command_buffers.command_buffers,
        signal_semaphores := signal_semaphores
    ]]}]
    defer() <| ${ delete submits; }
    queue |> queue_submit(submits, fence, result)


def queue_submit(
    queue               : Queue;
    command_buffers     : CommandBuffers;
    wait_semaphore      : Semaphore const ? implicit = [[ Semaphore const ? ]];
    wait_dst_stage_mask : uint = [[ uint ]];
    signal_semaphore    : Semaphore const ? implicit = [[ Semaphore const ? ]];
    fence               : Fence = [[ Fence ]];
    var result          : VkResult? = [[VkResult?]]
)
    var wait_semaphores : array<Semaphore>
    var wait_dst_stage_mask_array : array<uint>
    var signal_semaphores : array<Semaphore>

    if wait_semaphore != null
        wait_semaphores |> push(weak_copy(*wait_semaphore))
        wait_dst_stage_mask_array |> push(wait_dst_stage_mask)

    if signal_semaphore != null
        signal_semaphores |> push(weak_copy(*signal_semaphore))

    var submits <- [{ auto[] [[SubmitInfo
        wait_semaphores <- wait_semaphores,
        wait_dst_stage_mask <- wait_dst_stage_mask_array,
        command_buffers := command_buffers.command_buffers,
        signal_semaphores <- signal_semaphores
    ]]}]
    defer() <| ${ delete submits; }

    queue |> queue_submit(submits, fence, result)


def queue_submit(
    queue               : Queue;
    command_buffer      : CommandBuffer;
    wait_semaphore      : Semaphore const ? implicit = [[ Semaphore const ? ]];
    wait_dst_stage_mask : uint = [[ uint ]];
    signal_semaphore    : Semaphore const ? implicit = [[ Semaphore const ? ]];
    fence               : Fence = [[ Fence ]];
    var result          : VkResult? = [[VkResult?]]
)
    var command_buffers <- [[ CommandBuffers
        command_buffers <- [{ auto[] weak_copy(command_buffer) }]
    ]]
    defer() <| ${ delete command_buffers; }
    queue_submit([
        queue = queue,
        command_buffers = command_buffers,
        wait_semaphore = wait_semaphore,
        wait_dst_stage_mask = wait_dst_stage_mask,
        signal_semaphore = signal_semaphore,
        fence = fence,
        result = result
    ])


def queue_submit(
    queue               : Queue;
    command_buffer      : CommandBuffer;
    wait_semaphore      : Semaphore;
    wait_dst_stage_mask : uint;
    signal_semaphore    : Semaphore;
    fence               : Fence;
    var result          : VkResult? = [[VkResult?]]
)
    var command_buffers <- [[ CommandBuffers
        command_buffers <- [{ auto[] weak_copy(command_buffer) }]
    ]]
    defer() <| ${ delete command_buffers; }
    queue_submit([
        queue = queue,
        command_buffers = command_buffers,
        wait_semaphore = safe_addr(wait_semaphore),
        wait_dst_stage_mask = wait_dst_stage_mask,
        signal_semaphore = safe_addr(signal_semaphore),
        fence = fence,
        result = result
    ])


def cmd_copy_buffer(
    command_buffer : CommandBuffer;
    src_buffer : Buffer;
    dst_buffer : Buffer;
    size : uint64;
    src_offset : uint64 = [[ uint64 ]];
    dst_offset : uint64 = [[ uint64 ]]
)
    var regions <- [{ auto[] [[BufferCopy
        size=size, src_offset=src_offset, dst_offset=dst_offset]] }]
    defer() <| ${ delete regions; }
    command_buffer |> cmd_copy_buffer(src_buffer, dst_buffer, regions)


def cmd_bind_vertex_buffer(
    command_buffer : CommandBuffer;
    buffer : Buffer;
    binding : uint = [[ uint ]];
    offset : uint64 = [[ uint64 ]]
)
    var buffers <- [{ auto[] weak_copy(buffer) }]
    defer() <| ${ delete buffers; }
    var offsets <- [{ auto[] offset }]
    defer() <| ${ delete offsets; }
    command_buffer |> cmd_bind_vertex_buffers(binding, buffers, offsets)


def run_cmd_sync(
    device          : Device;
    command_pool    : CommandPool;
    queue           : Queue;
    b               : block<(cmd_buf:CommandBuffer)>
)
    var cmd_bufs <- device |> allocate_command_buffers_primary(command_pool, 1)
    defer() <| ${ delete cmd_bufs; }
    let cmd_buf = cmd_bufs.command_buffers[0]

    cmd_buf |> record_command_buffer() <|
        b |> invoke(cmd_buf)

    queue |> queue_submit(cmd_bufs)
    queue |> queue_wait_idle()
