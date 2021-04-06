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
    sems_underflow  : int
    _sems           : array<Semaphore>
    _recycled_sems  : array<Semaphore>
    _waits          : array<QueueWait>
    _signals        : array<Semaphore>
    _submits        : array<SubmitInfo>
    _device         : Device

def finalize(var q : QueueEx & explicit)
    delete q.cmd_pool
    delete q.queue
    delete q._sems
    delete q._recycled_sems
    delete q._waits
    delete q._signals
    delete q._submits
    delete q._device
    memzero(q)


struct QueueWait
    weak_sem        : Semaphore
    dst_stage_mask  : uint


def create_queue_ex(
    device              : Device;
    family              : uint;
    index               : uint = 0u;
    recyclable_sems     : int = 100
)
    return <- [[ QueueEx
        queue <- device |> get_device_queue(family, index),
        family = family,
        cmd_pool <- create_command_pool([device=device, queue_family=family]),
        _sems <- [{ for i in range(recyclable_sems);
            device |> create_semaphore }],
        _device <- weak_copy(device)
    ]]


def emplace(var queue : QueueEx; var info : SubmitInfo)
    for w in queue._waits
        info.wait_semaphores |> emplace <| w.weak_sem
        info.wait_dst_stage_mask |> emplace <| w.dst_stage_mask
    for sem in queue._signals
        info.signal_semaphores |> emplace <| sem
    queue._waits |> clear
    queue._signals |> clear
    queue._submits |> emplace <| info


def push(var queue : QueueEx; cmds : CommandBuffers)
    queue |> emplace <| [[ SubmitInfo command_buffers:=cmds.command_buffers ]]


def push_seq(var queue : QueueEx; cmds : CommandBuffers)
    var sem <- queue |> reusable_semaphore
    queue |> next_signal    <| sem
    queue |> push           <| cmds
    queue |> next_wait      <| sem
    queue |> recycle        <| sem


def reusable_semaphore(var queue : QueueEx) : Semaphore
    var sem : Semaphore
    if length(queue._sems) > 0
        sem <- queue._sems[length(queue._sems)-1]
        queue._sems |> pop
    else
        sem <- queue._device |> create_semaphore
        queue.sems_underflow++
    return <- sem
    

def recycle(var queue : QueueEx; var semaphore : Semaphore)
    queue._recycled_sems |> emplace <| semaphore


def next_wait(
    var queue : QueueEx;
    sem : Semaphore;
    dst_stage_mask : uint = uint(
        VkPipelineStageFlagBits VK_PIPELINE_STAGE_ALL_COMMANDS_BIT)
)
    queue._waits |> emplace <| [[ QueueWait
        weak_sem <- weak_copy(sem), dst_stage_mask=dst_stage_mask ]]


def next_signal(var queue : QueueEx; sem : Semaphore)
    queue._signals |> emplace <| weak_copy(sem)


def submit(var queue : QueueEx; fence_to_signal : Fence = [[ Fence ]])
    queue.queue |> queue_submit(queue._submits, fence_to_signal)
    for s in queue._submits
        delete s
    while length(queue._recycled_sems)
        queue._sems |> emplace <| pop(queue._recycled_sems)
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
