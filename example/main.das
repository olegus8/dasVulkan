//options log, log_infer_passes

options persistent_heap = true

require daslib/safe_addr
require daslib/vulkan_boost
require daslib/defer
require math
require strings


let
    MAX_FRAMES_IN_FLIGHT = 2


struct Vertex
    pos : float2
    color : float3
    tex_pos : float2


struct UniformBufferObject
    offset : float2


def create_example_descriptor_set_layout(
    device : Device
) : DescriptorSetLayout
    var info <- [[ DescriptorSetLayoutCreateInfo
        bindings <- [{ auto[]
            [[ DescriptorSetLayoutBinding
                binding = 0u,
                descriptor_count = 1u,
                descriptor_type = (VkDescriptorType
                    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER),
                stage_flags = uint(VkShaderStageFlagBits
                    VK_SHADER_STAGE_VERTEX_BIT)
            ]];
            [[ DescriptorSetLayoutBinding
                binding = 1u,
                descriptor_count = 1u,
                descriptor_type = (VkDescriptorType
                    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER),
                stage_flags = uint(VkShaderStageFlagBits
                    VK_SHADER_STAGE_FRAGMENT_BIT)
            ]]
        }] ]]
    defer() <| { delete info; }
    return <- device |> create_descriptor_set_layout(info)


def create_example_pipeline_layout(
    device : Device;
    desc_set_layout : DescriptorSetLayout
) : PipelineLayout
    var info <- [[ PipelineLayoutCreateInfo
        set_layouts <- [{ auto[] weak_copy(desc_set_layout) }]
    ]]
    defer() <| { delete info; }
    return <- device |> create_pipeline_layout(info)


def create_example_graphics_pipeline(
    sis : SwapchainIndependentState
) : Pipeline
    var extent <- sis.phys_dev |> get_swap_extent(sis.surface, sis.window)
    var create_info <- [[GraphicsPipelineCreateInfo
        layout = weak_copy(sis.pipeline_layout),
        render_pass = weak_copy(sis.render_pass),
        base_pipeline_index = -1,
        input_assembly_state <- [[ PipelineInputAssemblyStateCreateInfo
            topology=VkPrimitiveTopology VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST]],
        rasterization_state <- [[ PipelineRasterizationStateCreateInfo
            polygon_mode = VkPolygonMode VK_POLYGON_MODE_FILL,
            line_width = 1.0f,
            cull_mode = uint(VkCullModeFlagBits VK_CULL_MODE_BACK_BIT),
            front_face = VkFrontFace VK_FRONT_FACE_CLOCKWISE]],
        multisample_state <- [[ PipelineMultisampleStateCreateInfo
            rasterization_samples=VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
            min_sample_shading = 1.0f ]],
        color_blend_state <- [[ PipelineColorBlendStateCreateInfo
            attachments <- [{ auto[] [[PipelineColorBlendAttachmentState
                color_write_mask =
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_R_BIT) |
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_G_BIT) |
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_B_BIT) |
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_A_BIT)
        ]]}]]],
        vertex_input_state <- [[PipelineVertexInputStateCreateInfo
            vertex_binding_descriptions <- [{ auto[]
                [[VertexInputBindingDescription binding = 0u,
                    stride = uint(typeinfo(sizeof type<Vertex>)),
                    input_rate=VkVertexInputRate VK_VERTEX_INPUT_RATE_VERTEX]]
            }],
            vertex_attribute_descriptions <- [{ auto[]
                [[VertexInputAttributeDescription binding=0u, location=0u,
                    format = VkFormat VK_FORMAT_R32G32_SFLOAT,
                    offset = uint(typeinfo(offsetof<pos> type<Vertex>))]];
                [[VertexInputAttributeDescription binding=0u, location=1u,
                    format = VkFormat VK_FORMAT_R32G32B32_SFLOAT,
                    offset = uint(typeinfo(offsetof<color> type<Vertex>))]];
                [[VertexInputAttributeDescription binding=0u, location=2u,
                    format = VkFormat VK_FORMAT_R32G32_SFLOAT,
                    offset = uint(typeinfo(offsetof<tex_pos> type<Vertex>))]]
            }]
        ]],
        viewport_state <- [[PipelineViewportStateCreateInfo
            viewports <- [{ auto[] [[Viewport min_depth=0.f, max_depth=1.f,
                width=float(extent.width), height=float(extent.height) ]]}],
            scissors <- [{ auto[] [[Rect2D extent = extent]] }]
        ]],
        stages <- [{ auto[]
            [[PipelineShaderStageCreateInfo
                module_ = weak_copy(sis.vert_shmod), name = "main",
                stage = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT]];
            [[PipelineShaderStageCreateInfo
                module_ = weak_copy(sis.frag_shmod), name = "main",
                stage = VkShaderStageFlagBits VK_SHADER_STAGE_FRAGMENT_BIT]]
        }]
    ]]
    defer() <| { delete create_info; }

    return <- create_graphics_pipeline([
        device=sis.device, create_info=create_info])


def create_example_draw_commands(
    sis : SwapchainIndependentState;
    sds : SwapchainDependentState
) : CommandBuffers
    var cmd_bufs <- sis.device |> allocate_command_buffers_primary(
        sis.cmd_pool, sds.swapchain.framebuffers |> length())
    var clear_values <- [{ auto[] [[VkClearValue]] }]
    defer() <| { delete clear_values; }
    for cmd_buf, fbuf, dset in cmd_bufs.command_buffers, sds.swapchain.framebuffers, sds.desc_sets.descriptor_sets
        cmd_buf |> record_command_buffer() <|
            cmd_buf |> record_render_pass(
                sis.phys_dev, sis.window, sis.surface, sis.render_pass,
                fbuf, clear_values
            ) <|
                cmd_buf |> cmd_bind_pipeline(
                    VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS,
                    sds.pipeline)
                cmd_buf |> cmd_bind_vertex_buffer(sis.vbuf.buffer)
                cmd_bind_index_buffer([
                    command_buffer = cmd_buf,
                    buffer = sis.ibuf.buffer,
                    index_type = VkIndexType VK_INDEX_TYPE_UINT32])
                
                cmd_buf |> cmd_bind_descriptor_set(
                    VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS,
                    sis.pipeline_layout, dset)

                cmd_draw_indexed([command_buffer = cmd_buf,
                    index_count = uint(sis.indices |> length()),
                    instance_count = 1u])
    return <- cmd_bufs


struct MemoryBackedImage
    image : Image
    memory : DeviceMemory
    format : VkFormat
    width : int
    height : int


def finalize(var b: MemoryBackedImage explicit)
    delete b.memory
    delete b.image
    memzero(b)


def create_memory_backed_image(
    device      : Device;
    phys_dev    : PhysicalDevice;
    width       : int;
    height      : int;
    format      : VkFormat;
    tiling      : VkImageTiling;
    usage       : uint;
    mem_props   : uint
) : MemoryBackedImage

    var created = false
    var mbi<-[[ MemoryBackedImage format=format, width=width, height=height ]]
    mbi.image <- device |> create_image( [[ ImageCreateInfo
        image_type = VkImageType VK_IMAGE_TYPE_2D,
        extent <- [[Extent3D width=uint(width),height=uint(height),depth=1u]],
        mip_levels = 1u,
        array_layers = 1u,
        format = format,
        tiling = tiling,
        initial_layout = VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED,
        usage = usage,
        samples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        sharing_mode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE]])
    device |> find_image_memory_type(phys_dev, mbi.image, mem_props
    ) <| $(mem_type, mem_size)
        mbi.memory <- device |> allocate_memory([[MemoryAllocateInfo
            allocation_size=mem_size, memory_type_index=mem_type]])
        device |> bind_image_memory(mbi.image, mbi.memory)
        created = true
    assert(created)
    return <- mbi


struct MemoryBackedBuffer
    buffer : Buffer
    memory : DeviceMemory


def finalize(var b: MemoryBackedBuffer explicit)
    delete b.memory
    delete b.buffer
    memzero(b)


def create_memory_backed_buffer(
    device      : Device;
    phys_dev    : PhysicalDevice;
    buf_size    : uint64;
    usage       : uint;
    mem_props   : uint
) : MemoryBackedBuffer
    var created = false
    var mbb : MemoryBackedBuffer
    mbb.buffer <- device |> create_buffer_exclusive(buf_size, usage)
    device |> find_buffer_memory_type(phys_dev, mbb.buffer, mem_props
    ) <| $(mem_type, mem_size)
        mbb.memory <- device |> allocate_memory([[MemoryAllocateInfo
            allocation_size=mem_size, memory_type_index=mem_type]])
        device |> bind_buffer_memory(mbb.buffer, mbb.memory)
        created = true
    assert(created)
    return <- mbb


def create_device_local_buffer(
    sis     : SwapchainIndependentState;
    data    : array<auto(T)>;
    usage   : uint
) : MemoryBackedBuffer
    let buf_size = typeinfo(sizeof type<T>) * data |> length()

    var buf <- sis.device |> create_memory_backed_buffer(
        sis.phys_dev, uint64(buf_size),
        usage | uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_DST_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))

    var staging <- sis.device |> create_memory_backed_buffer(
        sis.phys_dev, uint64(buf_size),
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)|
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))
    defer() <| { delete staging; }

    sis.device |> map_device_memory_to_array(
        staging.memory, uint64(buf_size), uint64(0), 0u
    ) <| $(var mapped_data : array<T>#)
        for dst, src in mapped_data, data
            dst = src
    sis.device |> run_cmd_sync(sis.cmd_pool, sis.queue) <| $(cmd_buf)
        cmd_buf |> cmd_copy_buffer(staging.buffer,buf.buffer,uint64(buf_size))

    return <- buf


def create_image_view(
    device : Device;
    image : MemoryBackedImage
) : ImageView
    return <- device |> create_image_view([[ ImageViewCreateInfo
        image = image.image,
        format = image.format,
        view_type = VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
        subresource_range = IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR,
        components = COMPONENT_MAPPING_IDENTITY
    ]])


def create_device_local_sampled_image_rgba8(
    sis     : SwapchainIndependentState;
    width   : int;
    height  : int;
    b       : block<(var mapped_data : array<uint4>#)>
) : MemoryBackedImage
    assert(width % 4 == 0)
    let buf_size = typeinfo(sizeof type<uint>) * width * height

    var staging <- sis.device |> create_memory_backed_buffer(
        sis.phys_dev, uint64(buf_size),
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)|
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))
    defer() <| { delete staging; }

    sis.device |> map_device_memory_to_array(
        staging.memory, uint64(buf_size), uint64(0), 0u
    ) <| $(var mapped_data : array<uint4>#)
        b |> invoke(mapped_data)

    var img <- create_memory_backed_image([
        device = sis.device,
        phys_dev = sis.phys_dev,
        width = width,
        height = height,
        format = VkFormat VK_FORMAT_R8G8B8A8_SRGB,
        tiling = VkImageTiling VK_IMAGE_TILING_OPTIMAL,
        usage = uint(VkImageUsageFlagBits VK_IMAGE_USAGE_TRANSFER_DST_BIT)
              | uint(VkImageUsageFlagBits VK_IMAGE_USAGE_SAMPLED_BIT),
        mem_props = uint(VkMemoryPropertyFlagBits
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    ])

    sis |> transition_image_layout(img,
        VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED,
        VkImageLayout VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)

    sis |> copy_buffer_to_image(staging, img)

    sis |> transition_image_layout(img,
        VkImageLayout VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        VkImageLayout VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)

    return <- img


def copy_buffer_to_image(
    sis : SwapchainIndependentState;
    buffer : MemoryBackedBuffer;
    image : MemoryBackedImage
)
    sis.device |> run_cmd_sync(sis.cmd_pool, sis.queue) <| $(cmd_buf)
        var regions <- [{ auto[] [[ BufferImageCopy
            image_subresource <- [[ ImageSubresourceLayers
                aspect_mask = uint(
                    VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
                layer_count = 1u ]],
            image_extent <- [[ Extent3D
                width = uint(image.width),
                height = uint(image.height),
                depth = 1u ]]
        ]] }]
        defer() <| { delete regions; }
        cmd_buf |> cmd_copy_buffer_to_image(buffer.buffer, image.image,
            VkImageLayout VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            regions)


def transition_image_layout(
    sis : SwapchainIndependentState;
    image : MemoryBackedImage;
    old_layout : VkImageLayout;
    new_layout : VkImageLayout
)
    var src_stage_mask : uint
    var dst_stage_mask : uint
    var src_access_mask : uint
    var dst_access_mask : uint

    if (old_layout == VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED
    &&  new_layout == VkImageLayout VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
    )
        src_access_mask = 0u
        dst_access_mask = uint(
            VkAccessFlagBits VK_ACCESS_TRANSFER_WRITE_BIT)
        src_stage_mask = uint(
            VkPipelineStageFlagBits VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT)
        dst_stage_mask = uint(
            VkPipelineStageFlagBits VK_PIPELINE_STAGE_TRANSFER_BIT)
    elif (old_layout == VkImageLayout VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
    &&    new_layout == (
            VkImageLayout VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
    )
        src_access_mask = uint(
            VkAccessFlagBits VK_ACCESS_TRANSFER_WRITE_BIT)
        dst_access_mask = uint(
            VkAccessFlagBits VK_ACCESS_SHADER_READ_BIT)
        src_stage_mask = uint(
            VkPipelineStageFlagBits VK_PIPELINE_STAGE_TRANSFER_BIT)
        dst_stage_mask = uint(
            VkPipelineStageFlagBits VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT)
    else
        panic("unsupported layout transition!")

    var barriers <- [{ auto[] [[ ImageMemoryBarrier
        src_access_mask = src_access_mask,
        dst_access_mask = dst_access_mask,
        old_layout = old_layout,
        new_layout = new_layout,
        src_queue_family_index = VK_QUEUE_FAMILY_IGNORED,
        dst_queue_family_index = VK_QUEUE_FAMILY_IGNORED,
        image = weak_copy(image.image),
        subresource_range <- [[ ImageSubresourceRange
            aspect_mask = uint(
                VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
            level_count = 1u,
            layer_count = 1u ]]
    ]] }]
    defer() <| { delete barriers; }

    sis.device |> run_cmd_sync(sis.cmd_pool, sis.queue) <| $(cmd_buf)
        cmd_pipeline_barrier([
            command_buffer = cmd_buf,
            src_stage_mask = src_stage_mask,
            dst_stage_mask = dst_stage_mask,
            image_memory_barriers = barriers])


def create_example_sampler(sis : SwapchainIndependentState) : Sampler
    let props <- sis.phys_dev |> get_physical_device_properties()
    return <- sis.device |> create_sampler( [[ SamplerCreateInfo
        mag_filter = VkFilter VK_FILTER_LINEAR,
        min_filter = VkFilter VK_FILTER_LINEAR,
        address_mode_u = VkSamplerAddressMode VK_SAMPLER_ADDRESS_MODE_REPEAT,
        address_mode_v = VkSamplerAddressMode VK_SAMPLER_ADDRESS_MODE_REPEAT,
        address_mode_w = VkSamplerAddressMode VK_SAMPLER_ADDRESS_MODE_REPEAT,
        anisotropy_enable = 1u,
        max_anisotropy = props.limits.max_sampler_anisotropy,
        border_color = VkBorderColor VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        compare_op = VkCompareOp VK_COMPARE_OP_ALWAYS,
        mipmap_mode = VkSamplerMipmapMode VK_SAMPLER_MIPMAP_MODE_LINEAR
    ]] )


//TODO: to builtin
def to_uint4(f : float4) : uint4
    return uint4(f[0], f[1], f[2], f[3])


def create_example_texture(
    sis : SwapchainIndependentState
) : MemoryBackedImage
    let width1 = 1 << 8
    let height = 1 << 8
    return <- sis |> create_device_local_sampled_image_rgba8(
        width1, height
    ) <| $(var texels : array<uint4>#)
        let width = width1 / 4
        let one = float4(1.f, 1.f, 1.f, 1.f)
        for iy in range(height)
            for ix in range(width)
                var x = float(ix)*one*4.f + float4(0.f, 1.f, 2.f, 3.f)
                var y = float(iy)*one
                x /= float(width1)
                y /= float(height)
                let r = 0.5f*(one + sin(17.f*x + 63.f*y + 0.1f*one))
                let g = 0.5f*(one + sin(33.f*x + 37.f*y + 0.5f*one))
                let b = 0.5f*(one + sin(61.f*x + 15.f*y + 1.0f*one))
                texels[iy*width + ix] = (
                    (to_uint4(255.f*saturate(r))) +
                    (to_uint4(255.f*saturate(g)) << 8) +
                    (to_uint4(255.f*saturate(b)) << 16))


def create_example_render_pass(
    device : Device;
    surf_fmt : SurfaceFormatKHR
) : RenderPass
    
    var create_info <- [[RenderPassCreateInfo
        attachments <- [{auto[] [[AttachmentDescription
            format = surf_fmt.format,
            samples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
            load_op = VkAttachmentLoadOp VK_ATTACHMENT_LOAD_OP_CLEAR,
            store_op = VkAttachmentStoreOp VK_ATTACHMENT_STORE_OP_STORE,
            stencil_load_op = (VkAttachmentLoadOp
                VK_ATTACHMENT_LOAD_OP_DONT_CARE),
            stencil_store_op = (VkAttachmentStoreOp
                VK_ATTACHMENT_STORE_OP_DONT_CARE),
            initial_layout = VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED,
            final_layout = VkImageLayout VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
        ]]}],
        subpasses <- [{auto[] [[SubpassDescription
            pipeline_bind_point = (VkPipelineBindPoint
                VK_PIPELINE_BIND_POINT_GRAPHICS),
            color_attachments <- [{auto[] [[AttachmentReference
                attachment = 0u,
                layout = VkImageLayout VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
            ]]}]
        ]]}],
        dependencies <- [{auto[] [[SubpassDependency
            src_subpass = VK_SUBPASS_EXTERNAL,
            dst_subpass = 0u,
            src_stage_mask = uint(VkPipelineStageFlagBits
                VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            src_access_mask = 0u,
            dst_stage_mask = uint(VkPipelineStageFlagBits
                VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            dst_access_mask = uint(VkAccessFlagBits
                VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
        ]]}]
    ]]
    defer() <| { delete create_info; }
    return <- device |> create_render_pass(create_info)


def create_example_device(
    physical_device : PhysicalDevice;
    queue_family    : uint;
    extensions      : array<string> = DEFAULT_REQUIRED_EXTENSIONS
) : Device
    var create_info <- [[DeviceCreateInfo
        queue_create_infos <- [{auto[] [[DeviceQueueCreateInfo
            queue_family_index = queue_family,
            queue_priorities <- [{ auto[] 1.0f }]
        ]]}],
        enabled_extension_names := extensions,
        p_enabled_features = new [[ PhysicalDeviceFeatures
            sampler_anisotropy = 1u ]]
    ]]
    defer() <| ${ delete create_info; }

    return <- physical_device |> create_device(create_info)


def find_best_physical_device(
    instance : Instance;
    surface : SurfaceKHR
) : PhysicalDevice
    var best_score : int = 0
    var best_device : PhysicalDevice
    var devices <- instance |> enumerate_physical_devices()
    defer() <| ${ delete devices; }
    for device in devices
        var score = device |> get_suitability_score(surface)
        if score > best_score
            best_score = score
            best_device = device
    if best_score == 0
        panic("No suitable physical device found.")
    return <- best_device


def get_suitability_score(device : PhysicalDevice; surface : SurfaceKHR)
    var score = 1

    var has_graphics = false
    device |> find_graphics_queue_family(surface) <| $(qfam)
        has_graphics = true
    if ! has_graphics
        return 0
    
    var props <- device |> get_physical_device_properties()
    if (props.device_type ==
        VkPhysicalDeviceType VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    )
        score += 1000

    var feats <- device |> get_physical_device_features()
    if feats.sampler_anisotropy == 0u
        return 0

    var exts <- device |> enumerate_device_extension_properties()
    defer() <| ${ delete exts; }
    for required_ext in DEFAULT_REQUIRED_EXTENSIONS
        var found = false
        for ext in exts
            if hash(ext.extension_name) == hash(required_ext)
                found = true
                break
        if ! found
            return 0

    var formats <- device |> get_physical_device_surface_formats_khr(surface)
    defer() <| ${ delete formats; }
    if formats |> length() == 0
        return 0

    var present_modes <- (
        device |> get_physical_device_surface_present_modes_khr(surface))
    defer() <| ${ delete present_modes; }
    if present_modes |> length() == 0
        return 0

    return score


struct SwapchainIndependentState
    window          : Window
    instance        : Instance
    surface         : SurfaceKHR
    phys_dev        : PhysicalDevice
    device          : Device
    queue           : Queue
    surf_fmt        : SurfaceFormatKHR
    present_mode    : VkPresentModeKHR
    vert_shmod      : ShaderModule
    frag_shmod      : ShaderModule
    render_pass     : RenderPass
    desc_set_layout : DescriptorSetLayout
    pipeline_layout : PipelineLayout
    cmd_pool        : CommandPool
    vertices        : array<Vertex>
    vbuf            : MemoryBackedBuffer
    indices         : array<uint>
    ibuf            : MemoryBackedBuffer
    texture         : MemoryBackedImage
    texture_view    : ImageView
    sampler         : Sampler


def finalize(var s : SwapchainIndependentState explicit)
    s.device |> device_wait_idle()
    delete s.sampler
    delete s.texture_view
    delete s.texture
    delete s.ibuf
    delete s.indices
    delete s.vbuf
    delete s.vertices
    delete s.pipeline_layout
    delete s.desc_set_layout
    delete s.render_pass
    delete s.frag_shmod
    delete s.vert_shmod
    delete s.cmd_pool
    delete s.device
    delete s.surface
    delete s.instance
    delete s.window
    memzero(s)


def create_swapchain_independent_state(
    width, height : int;
    title : string
) : SwapchainIndependentState
    var s : SwapchainIndependentState
    s.window <- create_window(width, height, title)
    s.instance <- create_default_instance()
    s.surface <- s.instance |> create_window_surface(s.window)
    s.phys_dev <- s.instance |> find_best_physical_device(s.surface)
    s.present_mode <- s.phys_dev |> find_present_mode_like_mailbox(s.surface)
    s.surf_fmt <- s.phys_dev |> find_format_like_srgb_bgra8(s.surface)
    let qfam <- s.phys_dev |> get_graphics_queue_family(s.surface)
    s.device <- s.phys_dev |> create_example_device(qfam)
    s.queue <- s.device |> get_device_queue(qfam)
    s.cmd_pool <- create_command_pool([device=s.device, queue_family=qfam])
    s.vert_shmod <- s.device |> create_shader_module_from_file(
        "{get_das_root()}/modules/dasVulkan/example/vert.spv")
    s.frag_shmod <- s.device |> create_shader_module_from_file(
        "{get_das_root()}/modules/dasVulkan/example/frag.spv")
    s.render_pass <- s.device |> create_example_render_pass(s.surf_fmt)
    s.desc_set_layout <- s.device |> create_example_descriptor_set_layout()
    s.pipeline_layout <- s.device |> create_example_pipeline_layout(
        s.desc_set_layout)
    s.vertices <- [{auto[]
        [[Vertex pos=float2(-0.5f, -0.5f), color=float3(1f, 0f, 0f),
                                                     tex_pos=float2(1f, 0f)]];
        [[Vertex pos=float2( 0.5f, -0.5f), color=float3(0f, 1f, 0f),
                                                     tex_pos=float2(0f, 0f)]];
        [[Vertex pos=float2( 0.5f,  0.5f), color=float3(0f, 0f, 1f),
                                                     tex_pos=float2(0f, 1f)]];
        [[Vertex pos=float2(-0.5f,  0.5f), color=float3(1f, 1f, 1f),
                                                     tex_pos=float2(1f, 1f)]]}]
    s.indices <- [{auto[] 0u; 1u; 2u; 2u; 3u; 0u}]
    s.vbuf <- s |> create_device_local_buffer(s.vertices,
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_VERTEX_BUFFER_BIT))
    s.ibuf <- s |> create_device_local_buffer(s.indices, 
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_INDEX_BUFFER_BIT))
    s.texture <- s |> create_example_texture()
    s.texture_view <- s.device |> create_image_view(s.texture)
    s.sampler <- s |> create_example_sampler()
    return <- s


struct SwapchainDependentState
    swapchain           : SwapchainEx
    pipeline            : Pipeline
    img_avail_sems      : array<Semaphore>
    render_done_sems    : array<Semaphore>
    frame_fences        : array<Fence>
    uniform_bufs        : array<MemoryBackedBuffer>
    desc_pool           : DescriptorPool
    desc_sets           : DescriptorSets
    draw_cmds           : CommandBuffers
    frames_since_start  : int
    imgs_used_by_frames : array<int>
    _device             : Device


def finalize(var s : SwapchainDependentState explicit)
    s._device |> device_wait_idle()
    delete s.imgs_used_by_frames
    delete s.draw_cmds
    delete s.pipeline
    delete s.desc_sets
    delete s.desc_pool
    delete s.uniform_bufs
    delete s.swapchain
    delete s.frame_fences
    delete s.render_done_sems
    delete s.img_avail_sems
    memzero(s)


def create_swapchain_dependent_state(
    sis : SwapchainIndependentState
) : SwapchainDependentState
    var sds <- [[ SwapchainDependentState _device <- weak_copy(sis.device) ]]
    sds.img_avail_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_semaphore() }]
    sds.render_done_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_semaphore() }]
    sds.frame_fences <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_fence([[FenceCreateInfo
            flags=uint(VkFenceCreateFlagBits VK_FENCE_CREATE_SIGNALED_BIT)
    ]]) }]
    sds.swapchain <- sis.device |> create_swapchain_ex(sis.phys_dev,
        sis.surface, sis.window, sis.surf_fmt, sis.present_mode,
        sis.render_pass)
    sds.uniform_bufs <- sis |> create_example_uniform_buffers(
        sds.swapchain.framebuffers)
    sds.desc_pool <- sis |> create_example_descriptor_pool(
        sds.swapchain.framebuffers)
    sds.desc_sets <- sis |> create_example_descriptor_sets(
        sds.desc_pool, sds.uniform_bufs)
    sds.pipeline <- sis |> create_example_graphics_pipeline()
    sds.draw_cmds <- create_example_draw_commands(sis, sds)
    sds.imgs_used_by_frames <- [{for x in sds.swapchain.framebuffers; -1}]

    return <- sds


def create_example_descriptor_sets(
    sis : SwapchainIndependentState;
    pool : DescriptorPool;
    ubufs : array<MemoryBackedBuffer>
) : DescriptorSets
    var create_info <- [[ DescriptorSetAllocateInfo
        descriptor_pool = weak_copy(pool),
        set_layouts <- [{ for ubuf in ubufs ;
            weak_copy(sis.desc_set_layout) }]
    ]]
    defer() <| { delete create_info; }
    var dsets <- sis.device |> allocate_descriptor_sets(create_info)
    for dset, ubuf in dsets.descriptor_sets, ubufs
        if true
            var writes <- [{ auto[]
                [[ WriteDescriptorSet
                    dst_set = weak_copy(dset),
                    dst_binding = 0u,
                    descriptor_type = (VkDescriptorType
                        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER),
                    buffer_info <- [{ auto[] [[ DescriptorBufferInfo
                        buffer = weak_copy(ubuf.buffer),
                        range_ = uint64(
                            typeinfo(sizeof type<UniformBufferObject>))
                ]] }] ]];
                [[ WriteDescriptorSet
                    dst_set = weak_copy(dset),
                    dst_binding = 1u,
                    descriptor_type = (VkDescriptorType
                        VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER),
                    image_info <- [{ auto[] [[ DescriptorImageInfo
                        image_layout = (VkImageLayout
                            VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL),
                        image_view = weak_copy(sis.texture_view),
                        sampler = weak_copy(sis.sampler)
                ]] }] ]]
            }]
            defer <| { delete writes; }
            sis.device |> update_descriptor_sets(writes)
    return <- dsets


def create_example_descriptor_pool(
    sis : SwapchainIndependentState;
    framebuffers : array<Framebuffer>
) : DescriptorPool
    var info <- [[ DescriptorPoolCreateInfo
        pool_sizes <- [{ auto[]
            [[ DescriptorPoolSize
                type_ = VkDescriptorType VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptor_count = uint(framebuffers |> length())
            ]];
            [[ DescriptorPoolSize
                type_ = (VkDescriptorType
                    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER),
                descriptor_count = uint(framebuffers |> length())
            ]]
        }],
        max_sets = uint(framebuffers |> length()),
        flags = uint(VkDescriptorPoolCreateFlagBits
            VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT)
    ]]
    defer() <| { delete info; }
    return <- sis.device |> create_descriptor_pool(info)


def create_example_uniform_buffers(
    sis : SwapchainIndependentState;
    framebuffers : array<Framebuffer>
) : array<MemoryBackedBuffer>
    return <- [{ for fbuf in framebuffers ;
        sis.device |> create_memory_backed_buffer(
            sis.phys_dev, uint64(typeinfo(sizeof type<UniformBufferObject>)),
            uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT),
            uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)|
            uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
        ) }]


def with_next_image(device, swapchain, sem_to_signal; b : block<(i:uint)>)
    var result : VkResult
    var p_result : VkResult ?
    unsafe
        p_result = addr(result)
    let img_index = device |> acquire_next_image_khr(
        swapchain, ULONG_MAX, sem_to_signal, [[Fence]], p_result)
    if result == VkResult VK_SUCCESS
        b |> invoke(img_index)
    else
        assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
            result == VkResult VK_SUBOPTIMAL_KHR)


def submit_draw(
    device          : Device;
    queue           : Queue;
    cmd_buf         : CommandBuffer;
    sem_to_wait     : Semaphore;
    sem_to_signal   : Semaphore;
    fence_to_signal : Fence
)
    queue_submit([queue = queue, command_buffer = cmd_buf,
        wait_semaphore = safe_addr(sem_to_wait),
        wait_dst_stage_mask = uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        signal_semaphore = safe_addr(sem_to_signal),
        fence = fence_to_signal])


def present(device, queue, swapchain, img_i, sem_to_wait) : bool
    var result : VkResult
    var p_result : VkResult ?
    unsafe
        p_result = addr(result)
    queue |> queue_present_khr(
        swapchain, img_i, safe_addr(sem_to_wait), p_result)
    if result == VkResult VK_SUCCESS
        return true
    assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
        result == VkResult VK_SUBOPTIMAL_KHR)
    return false


def update_uniform_buffer(
    device : Device;
    ubuf : MemoryBackedBuffer;
    frames_since_start : int
)
    device |> map_device_memory_to_array(
        ubuf.memory, uint64(typeinfo(sizeof type<UniformBufferObject>)),
        uint64(0), 0u
    ) <| $(var mapped_ubos : array<UniformBufferObject>#)
        mapped_ubos[0] <- [[ UniformBufferObject offset = float2(
            0.0f,
            0.5f*sin(float(frames_since_start)*2.0f*PI / 100.0f))
        ]]


def draw_frame(
    sis : SwapchainIndependentState;
    var sds : SwapchainDependentState
)
    let frame = sds.frames_since_start % MAX_FRAMES_IN_FLIGHT
    sis.device |> wait_for_fence(sds.frame_fences[frame], ULONG_MAX)
    var img_acquired = false
    var presented = false
    sis.device |> with_next_image(sds.swapchain.swapchain,
        sds.img_avail_sems[frame]
    ) <| $(img_i)
        img_acquired = true

        var img_frame = sds.imgs_used_by_frames[img_i]
        if img_frame != -1
            sis.device |> wait_for_fence(
                sds.frame_fences[img_frame], ULONG_MAX)
        sds.imgs_used_by_frames[img_i] = frame

        sis.device |> update_uniform_buffer(sds.uniform_bufs[img_i],
            sds.frames_since_start)

        sis.device |> reset_fence(sds.frame_fences[frame])
        sis.device |> submit_draw(sis.queue,
            sds.draw_cmds.command_buffers[img_i],
            sds.img_avail_sems[frame], sds.render_done_sems[frame],
            sds.frame_fences[frame])

        presented = sis.device |> present(sis.queue, sds.swapchain.swapchain,
            img_i, sds.render_done_sems[frame])

    sds.frames_since_start += 1
    return img_acquired && presented


[export]
def key_callback(
    window : GLFWwindow_DasHandle;
    key, scancode, action, mods : int
)
    print("key={key} scancode={scancode} action={action} mods={mods}\n")


def run_example
    var sis <- create_swapchain_independent_state(800, 600, "dasVulkanExample")
    defer() <| { delete sis; }

    sis.window.window |> glfwSetKeyCallback(@@key_callback)
    var props <- sis.phys_dev |> get_physical_device_properties()
    defer() <| { delete props ; }
    print("Using {props.device_name}\n")

    var keep_running = true
    while keep_running // swapchain re-creation loop
        // waiting while window is minimized
        while uint2(0,0) == sis.window |> get_framebuffer_size()
            glfwWaitEvents()
        sis.device |> device_wait_idle()

        if true
            var sds <- create_swapchain_dependent_state(sis)
            defer() <| { delete sds; }

            print("{sds.swapchain.framebuffers |> length()} " +
                "images in swap chain\n")

            while keep_running
                keep_running = sis.window.window |> glfwWindowShouldClose()==0
                glfwPollEvents()
                if ! draw_frame(sis, sds)
                    break

            sis.device |> device_wait_idle()


[export]
def main
    let heap_on_start = heap_bytes_allocated()
    let string_heap_on_start = string_heap_bytes_allocated()
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE)
    run_example()
    glfwTerminate()

    unsafe
        string_heap_collect()

    let heap_leaks = int(heap_bytes_allocated() - heap_on_start)
    let string_heap_leaks = int(string_heap_bytes_allocated()
        - string_heap_on_start)

    print("{heap_leaks} heap bytes have leaked\n")
    print("{string_heap_leaks} string heap bytes have leaked\n")
    assert(heap_leaks == 0)
    assert(string_heap_leaks == 0)

    print("Finished\n")
    return true
