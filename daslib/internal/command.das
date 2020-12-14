options indenting = 4
options no_aot = true

require daslib/defer
require vulkan
require generated
require device


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
    window          : GLFWwindow_DasHandle;
    surface         : SurfaceKHR;
    render_pass     : RenderPass;
    framebuffer     : Framebuffer;
    clear_values    : array<VkClearValue>;
    b : block
)
    var extent <- physical_device |> get_swap_extent(surface, window)
    var info <- [[RenderPassBeginInfo
        render_pass = weak_copy(render_pass),
        framebuffer = weak_copy(framebuffer),
        render_area = [[ Rect2D extent <- extent ]],
        clear_values <- clone_to_move(clear_values)
    ]]
    defer() <| ${ delete info; }
    let contents = VkSubpassContents VK_SUBPASS_CONTENTS_INLINE
    command_buffer |> record_render_pass_ex(info, contents, b)


def queue_submit(
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
    wait_semaphore      : Semaphore ? = [[ Semaphore ? ]];
    wait_dst_stage_mask : uint = [[ uint ]];
    signal_semaphore    : Semaphore ? = [[ Semaphore ? ]];
    fence               : Fence = [[ Fence ]];
    var result          : VkResult? = [[VkResult?]]
)
    var wait_semaphores : array<Semaphore>
    var wait_dst_stage_mask_array : array<uint>
    var signal_semaphores : array<Semaphore>

    if wait_semaphore != null
        wait_semaphores |> push(<- weak_copy(*wait_semaphore))
        wait_dst_stage_mask_array.push(wait_dst_stage_mask)

    if signal_semaphores != null
        signal_semaphores |> push(<- weak_copy(*signal_semaphore))

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
    wait_semaphore      : const Semaphore ? implicit = [[ const Semaphore ? ]];
    wait_dst_stage_mask : uint = [[ uint ]];
    signal_semaphore    : const Semaphore ? implicit = [[ const Semaphore ? ]];
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


def copy_buffer_sync(
    device : Device;
    command_pool : CommandPool;
    queue : Queue;
    src_buffer : Buffer;
    dst_buffer : Buffer;
    size : uint64
)
    var cmd_bufs <- device |> allocate_command_buffers_primary(
        command_pool, 1)
    defer() <| ${ delete cmd_bufs; }
    let cmd_buf = cmd_bufs.command_buffers[0]

    cmd_buf |> record_command_buffer() <| $()
        cmd_buf |> cmd_copy_buffer(src_buffer, dst_buffer, size)

    queue |> queue_submit(cmd_bufs)
    queue |> queue_wait_idle()
