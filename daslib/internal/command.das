options indenting = 4
options no_aot = true

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
    command_buffer : CommandBuffer;
    var render_pass_begin : RenderPassBeginInfo;
    b : block
)
    command_buffer |> cmd_begin_render_pass(render_pass_begin)
    b |> invoke()
    command_buffer |> cmd_end_render_pass()

def record_render_pass_full_window(
    command_buffer  : CommandBuffer;
    physical_device : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : GLFWwindow_DasHandle;
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
    command_buffer |> record_render_pass_ex(info, b)
