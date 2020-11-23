//options log, log_infer_passes

require daslib/safe_addr
require fio
require math
require strings
require vulkan


let
    MAX_FRAMES_IN_FLIGHT = 2

    REQUIRED_EXTENSIONS = [[auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ]]


struct Vertex
    position : float2
    color : float3


//TODO: move to math?
def clamp(t, a, b : uint)
    return min(max(t, a), b)


//TODO: move to stdlib?
def to_string(bytes : int8[])
    unsafe
        return reinterpret<string>(addr(bytes[0]))


def to_string(bytes : void?)
    unsafe
        return reinterpret<string>(bytes)


//TODO: need this for heap
def safe_addr_plain(x : auto(T)) : T ? #
    unsafe
        return reinterpret<T?#>(addr(x))


//TODO: need this for heap
def safe_addr_val(var x : auto(T)&) : T-& ? #
    unsafe
        return reinterpret<T-&?#>(addr(x))


def with_physical_devices(inst; b : block<(d:array<VkPhysicalDevice>)>)
    var devices : array<VkPhysicalDevice>
    var count : uint
    verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
        safe_addr(count), null))
    devices |> resize(int(count))
    verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
        safe_addr(count), safe_addr_val(devices[0])))
    b |> invoke(devices)
    delete devices


def with_best_physical_device(inst, surface; b : block<(d:VkPhysicalDevice)>)
    inst |> with_physical_devices() <| $(devices)
        var best_score : int = 0
        var best_device : VkPhysicalDevice
        for device in devices
            var score = device |> get_suitability_score(surface)
            if score > best_score
                best_score = score
                best_device = device
        if best_score == 0
            panic("No suitable physical device found.")
        b |> invoke(best_device)


def get_suitability_score(device, surface)
    var score = 1

    var has_graphics = false
    device |> with_graphics_queue_family(surface) <| $(graphics_i)
        has_graphics = true
    if ! has_graphics
        score = 0
    
    var props <- device |> get_properties()
    if (props.deviceType ==
        VkPhysicalDeviceType VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    )
        score += 1000

    device |> with_ext_props() <| $(exts)
        for required_ext in REQUIRED_EXTENSIONS
            if ! key_exists(exts, hash(required_ext))
                score = 0
                break
    device |> with_formats(surface) <| $(formats)
        if formats |> length() == 0
            score = 0
    device |> with_present_modes(surface) <| $(modes)
        if modes |> length() == 0
            score = 0
    return score


def with_queue_families(
    device; b : block<(families: array<VkQueueFamilyProperties>)>
)
    var families : array<VkQueueFamilyProperties>
    var count : uint
    device |> vkGetPhysicalDeviceQueueFamilyProperties(
        safe_addr(count), null)
    families |> resize(int(count))
    device |> vkGetPhysicalDeviceQueueFamilyProperties(
        safe_addr(count), safe_addr_val(families[0]))
    b |> invoke(families)
    delete families


def with_graphics_queue_family(device, surface; b : block<(index:uint)>)
    device |> with_queue_families() <| $(families)
        for family, index in families, range(INT_MAX)
            var can_present : uint
            verify(VkResult VK_SUCCESS ==
                device |> vkGetPhysicalDeviceSurfaceSupportKHR(
                    uint(index), surface, safe_addr(can_present)))
            if can_present == 0u
                continue

            var graphics_bit = uint(VkQueueFlagBits VK_QUEUE_GRAPHICS_BIT)
            if (family.queueFlags & graphics_bit) == 0u
                continue

            b |> invoke(uint(index))
            return


def with_device(instance, phys_dev, surface;
    b : block<(device:VkDevice; queue:VkQueue)>
)
    phys_dev |> with_queue_create_infos(surface) <| $(queue_infos)
        let features : VkPhysicalDeviceFeatures
        var device : VkDevice
        let create_info = [[VkDeviceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            pQueueCreateInfos = safe_addr_plain(queue_infos[0]),
            queueCreateInfoCount = uint(queue_infos |> length()),
            pEnabledFeatures = safe_addr(features),
            enabledExtensionCount = uint(REQUIRED_EXTENSIONS |> length()),
            ppEnabledExtensionNames = safe_addr(REQUIRED_EXTENSIONS[0])
        ]]
        verify(VkResult VK_SUCCESS == vkCreateDevice(
            phys_dev, safe_addr(create_info), null, safe_addr(device)))
        var queue : VkQueue
        phys_dev |> with_graphics_queue_family(surface) <| $(qfam)
            device |> vkGetDeviceQueue(qfam, 0u, queue |> safe_addr())
        b |> invoke(device, queue)
        device |> vkDeviceWaitIdle()
        device |> vkDestroyDevice(null)


def with_queue_create_infos(device, surface;
    b : block<(infos:array<VkDeviceQueueCreateInfo>)>
)
    var families : array<uint>
    device |> with_graphics_queue_family(surface) <| $(qfam)
        families |> push(qfam)

    var priorities : array<float>
    priorities |> reserve(families |> length())
    for family in families
        priorities |> push(1.0f)

    var infos : array<VkDeviceQueueCreateInfo>
    infos |> reserve(families |> length())
    for family in families
        infos |> emplace([[
            VkDeviceQueueCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO),
                queueFamilyIndex = family,
                queueCount = uint(priorities |> length()),
                pQueuePriorities = safe_addr_plain(priorities[0])
        ]])

    b |> invoke(infos)

    delete families
    delete priorities
    delete infos


def with_formats(device, surface;
    b : block<(formats:array<VkSurfaceFormatKHR>)>
)
    var formats : array<VkSurfaceFormatKHR>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
            surface, safe_addr(count), null))
    formats |> resize(int(count))
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
            surface, safe_addr(count), safe_addr_val(formats[0])))
    b |> invoke(formats)
    delete formats


def with_best_format(device, surface; b : block<(format:VkSurfaceFormatKHR)>)
    device |> with_formats(surface) <| $(formats)
        // picking ideal format if available
        for format in formats
            if (format.format == VkFormat VK_FORMAT_B8G8R8A8_SRGB
            &&  format.colorSpace == (VkColorSpaceKHR
                    VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            )
                b |> invoke(format)
                return
        // if no ideal found, picking anything
        for format in formats
            b |> invoke(format)
            return


def with_present_modes(device, surface;
    b : block<(formats:array<VkPresentModeKHR>)>
)
    var modes : array<VkPresentModeKHR>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
            surface, safe_addr(count), null))
    modes |> resize(int(count))
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
            surface, safe_addr(count), safe_addr_val(modes[0])))
    b |> invoke(modes)
    delete modes


def with_best_present_mode(device, surface; b : block<(mode:VkPresentModeKHR)>)
    device |> with_present_modes(surface) <| $(modes)
        for preferred in [[auto[]
            VkPresentModeKHR VK_PRESENT_MODE_MAILBOX_KHR;
            VkPresentModeKHR VK_PRESENT_MODE_FIFO_KHR
        ]]
            for mode in modes
                if mode == preferred
                    b |> invoke(mode)
                    return


def with_ext_props(device;
    b : block<(props:table<uint;VkExtensionProperties>)>
)
    var props : array<VkExtensionProperties>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkEnumerateDeviceExtensionProperties(
            to_string(null), safe_addr(count), null))
    props |> resize(int(count))
    verify(VkResult VK_SUCCESS ==
        device |> vkEnumerateDeviceExtensionProperties(
            to_string(null), safe_addr(count), safe_addr_val(props[0])))

    var props_table : table<uint; VkExtensionProperties>
    for prop in props
        let name <- prop.extensionName |> to_string()
        props_table[hash(name)] <- prop
    b |> invoke(props_table)
    delete props


def get_properties(device)
    var props : VkPhysicalDeviceProperties
    device |> vkGetPhysicalDeviceProperties(safe_addr(props))
    return <- props


def with_window(width, height, title; b : block<(w:GLFWwindow_DasHandle)>)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    b |> invoke(window)
    window |> glfwDestroyWindow()


def with_instance(b : block<(inst:VkInstance)>)
    var inst_info <- [[VkInstanceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    ]]

    let exts = glfwGetRequiredInstanceExtensions(
        safe_addr_val(inst_info.enabledExtensionCount))

    unsafe
        reinterpret<string const?>(inst_info.ppEnabledExtensionNames) = exts

    var instance : VkInstance
    verify(VkResult VK_SUCCESS == vkCreateInstance(
        safe_addr(inst_info), null, safe_addr(instance)))
    b |> invoke(instance)
    instance |> vkDestroyInstance(null)


def with_surface(window, instance; b : block<(s:VkSurfaceKHR)>)
    var surface : VkSurfaceKHR
    verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
        window, null, safe_addr(surface)))
    b |> invoke(surface)
    instance |> vkDestroySurfaceKHR(surface, null)


def with_swap_chain(device, phys_dev, surface, window, surf_fmt, present_mode;
    b : block<(sc:VkSwapchainKHR)>
)
    let caps <- phys_dev |> get_capabilities(surface)
    let extent <- phys_dev |> get_swap_extent(surface, window)

    // we want at least one spare image for multi-buffering
    var img_count : uint = caps.minImageCount + 1u
    if caps.maxImageCount > 0u
        img_count = min(img_count, caps.maxImageCount)

    let create_info = [[VkSwapchainCreateInfoKHR
        sType = VkStructureType VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        surface = surface,
        minImageCount = img_count,
        imageFormat = surf_fmt.format,
        imageColorSpace = surf_fmt.colorSpace,
        imageExtent = extent,
        imageArrayLayers = 1u, // 2 for stereoscopic
        imageUsage = uint(
            VkImageUsageFlagBits VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT),
        imageSharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE,
        preTransform = caps.currentTransform,
        compositeAlpha = (
            VkCompositeAlphaFlagBitsKHR VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR),
        presentMode = present_mode,
        clipped = uint(VK_TRUE)
    ]]

    var swap_chain : VkSwapchainKHR
    verify(VkResult VK_SUCCESS == device |> vkCreateSwapchainKHR(
        safe_addr(create_info), null, safe_addr(swap_chain)))
    b |> invoke(swap_chain)
    device |> vkDestroySwapchainKHR(swap_chain, null)


def get_swap_extent(device, surface, window)
    var caps <- device |> get_capabilities(surface)

    if caps.currentExtent.width != UINT_MAX
        return <- caps.currentExtent
    else
        let fb_size = window |> get_framebuffer_size()
        return [[VkExtent2D
            width = clamp(fb_size[0],
                caps.minImageExtent.width,
                caps.maxImageExtent.width),
            height = clamp(fb_size[1],
                caps.minImageExtent.height,
                caps.maxImageExtent.height)
        ]]


def get_framebuffer_size(window)
    var width, height : int
    window |> glfwGetFramebufferSize(safe_addr(width), safe_addr(height))
    return uint2(uint(width), uint(height))


def get_capabilities(device, surface)
    var caps : VkSurfaceCapabilitiesKHR
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            surface, safe_addr(caps)))
    return <- caps


def with_swap_chain_images(device, swap_chain; b : block<(d:array<VkImage>)>)
    var images : array<VkImage>
    var count : uint
    verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
        swap_chain, safe_addr(count), null))
    images |> resize(int(count))
    verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
        swap_chain, safe_addr(count), safe_addr_val(images[0])))
    b |> invoke(images)
    delete images


def with_swap_chain_image_views(device, images, surf_fmt;
    b : block<(d:array<VkImageView>)>
)
    var views : array<VkImageView>
    views |> resize(images |> length())
    for image, view in images, views
        let no_swizzle = VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY
        let create_info <- [[VkImageViewCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            image = image,
            viewType = VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
            format = surf_fmt.format,
            components = [[VkComponentMapping
                r = no_swizzle,
                g = no_swizzle,
                b = no_swizzle,
                a = no_swizzle]],
            subresourceRange = [[VkImageSubresourceRange
                aspectMask = uint(
                    VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
                baseMipLevel = 0u,
                levelCount = 1u,
                baseArrayLayer = 0u,
                layerCount = 1u]]
        ]]
        verify(VkResult VK_SUCCESS == device |> vkCreateImageView(
            safe_addr(create_info), null, safe_addr(view)))

    b |> invoke(views)

    for view in views
        device |> vkDestroyImageView(view, null)
    delete views


def with_render_pass(device, surf_fmt; b : block<(rp:VkRenderPass)>)
    let atts <- [[auto[] [[VkAttachmentDescription
        format = surf_fmt.format,
        samples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        loadOp = VkAttachmentLoadOp VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp = VkAttachmentStoreOp VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp = VkAttachmentLoadOp VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp = VkAttachmentStoreOp VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout = VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout = VkImageLayout VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    ]]]]
    let att_refs <- [[auto[] [[VkAttachmentReference
        attachment = 0u,
        layout = VkImageLayout VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    ]]]]
    let subs <- [[auto[] [[VkSubpassDescription
        pipelineBindPoint = (
            VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS),
        colorAttachmentCount = uint(att_refs |> length()),
        pColorAttachments = safe_addr(att_refs[0])
    ]]]]
    let deps <- [[auto[] [[VkSubpassDependency
        srcSubpass = VK_SUBPASS_EXTERNAL,
        dstSubpass = 0u,
        srcStageMask = uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        srcAccessMask = 0u,
        dstStageMask = uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        dstAccessMask = uint(VkAccessFlagBits
            VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
    ]]]]
    let create_info <- [[VkRenderPassCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO),
        attachmentCount = uint(atts |> length()),
        pAttachments = safe_addr(atts[0]),
        subpassCount = uint(subs |> length()),
        pSubpasses = safe_addr(subs[0]),
        dependencyCount = uint(deps |> length()),
        pDependencies = safe_addr(deps[0])
    ]]
    var rpass : VkRenderPass;
    verify(VkResult VK_SUCCESS == device |> vkCreateRenderPass(
        safe_addr(create_info), null, safe_addr(rpass)))
    b |> invoke(rpass)
    device |> vkDestroyRenderPass(rpass, null)


def with_shader_module(device, name; b : block<(m:VkShaderModule)>)
    let code_fpath = "{get_das_root()}/modules/dasVulkan/example/{name}.spv"
    var code : string
    var code_size : uint64
    code_fpath |> fopen("rb") <| $(f)
        code <- f |> fread()
        code_size = (f |> fstat()).size
    var code_ptr : uint?
    unsafe
        code_ptr = reinterpret<uint?>(code)
    let create_info <- [[VkShaderModuleCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        codeSize = code_size,
        pCode = code_ptr
    ]]
    var shmod : VkShaderModule
    verify(VkResult VK_SUCCESS == device |> vkCreateShaderModule(
        create_info |> safe_addr(), null, shmod |> safe_addr()))
    b |> invoke(shmod)
    device |> vkDestroyShaderModule(shmod, null)


def with_pipeline_layout(device; b : block<(layout:VkPipelineLayout)>)
    let create_info <- [[ VkPipelineLayoutCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
    ]]
    var layout : VkPipelineLayout
    verify(VkResult VK_SUCCESS == device |> vkCreatePipelineLayout(
        create_info |> safe_addr(), null, layout |> safe_addr()))
    b |> invoke(layout)
    device |> vkDestroyPipelineLayout(layout, null)


def with_pipeline_stages(vert_shmod, frag_shmod;
    b : block<(s:array<VkPipelineShaderStageCreateInfo>)>
)
    var stages <- [{auto[]
        [[VkPipelineShaderStageCreateInfo module_ = vert_shmod, pName = "main",
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO),
            stage = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT
        ]];
        [[VkPipelineShaderStageCreateInfo module_ = frag_shmod, pName = "main",
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO),
            stage = VkShaderStageFlagBits VK_SHADER_STAGE_FRAGMENT_BIT
        ]]
    }]
    b |> invoke(stages)
    delete stages


def with_pipeline_vertex_input(
    b : block<(i:VkPipelineVertexInputStateCreateInfo)>
)
    let vtx_bindings <- [[auto[] [[VkVertexInputBindingDescription
        binding = 0u,
        stride = uint(typeinfo(sizeof type<Vertex>)),
        inputRate = VkVertexInputRate VK_VERTEX_INPUT_RATE_VERTEX
    ]]]]
    let vtx_attrs <- [[auto[]
        [[VkVertexInputAttributeDescription binding = 0u, location = 0u,
            format = VkFormat VK_FORMAT_R32G32_SFLOAT,
            offset = uint(typeinfo(offsetof<position> type<Vertex>))
        ]];
        [[VkVertexInputAttributeDescription binding = 0u, location = 1u,
            format = VkFormat VK_FORMAT_R32G32B32_SFLOAT,
            offset = uint(typeinfo(offsetof<color> type<Vertex>))
        ]]
    ]]
    b |> invoke ([[VkPipelineVertexInputStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO),
        vertexBindingDescriptionCount = uint(vtx_bindings |> length()),
        pVertexBindingDescriptions = vtx_bindings[0] |> safe_addr(),
        vertexAttributeDescriptionCount = uint(vtx_attrs |> length()),
        pVertexAttributeDescriptions = vtx_attrs[0] |> safe_addr()
    ]])


def make_pipeline_input_assembly()
    return <- [[VkPipelineInputAssemblyStateCreateInfo
        sType = (VkStructureType 
            VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO),
        topology = VkPrimitiveTopology VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
    ]]


def with_pipeline_viewport(phys_dev, surface, window;
    b : block<(i:VkPipelineViewportStateCreateInfo)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    let viewports <- [[auto[] [[VkViewport minDepth = 0.0f, maxDepth = 1.0f,
        width = float(extent.width), height = float(extent.height)
    ]]]]
    let scissors <- [[auto[] [[VkRect2D extent = extent]]]]
    b |> invoke([[VkPipelineViewportStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO),
        viewportCount = uint(viewports |> length()),
        pViewports = viewports |> safe_addr(),
        scissorCount = uint(scissors |> length()),
        pScissors = scissors |> safe_addr()
    ]])


def make_pipeline_rasterizer()
    return <- [[VkPipelineRasterizationStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO),
        polygonMode = VkPolygonMode VK_POLYGON_MODE_FILL,
        lineWidth = 1.0f,
        cullMode = uint(VkCullModeFlagBits VK_CULL_MODE_BACK_BIT),
        frontFace = VkFrontFace VK_FRONT_FACE_CLOCKWISE
    ]]


def make_pipeline_multisampling()
    return <- [[VkPipelineMultisampleStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO),
        rasterizationSamples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        minSampleShading = 1.0f
    ]]


def with_pipeline_blending(b : block<(b:VkPipelineColorBlendStateCreateInfo)>)
    let blending_atts <- [[auto[] [[VkPipelineColorBlendAttachmentState
        colorWriteMask =
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_R_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_G_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_B_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_A_BIT)
    ]]]]
    b |> invoke([[VkPipelineColorBlendStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO),
        attachmentCount = uint(blending_atts |> length()),
        pAttachments = blending_atts |> safe_addr()
    ]])


def with_pipeline_creation_subobjects(
    phys_dev, surface, window, vert_shmod, frag_shmod;
    b : block<(
        stages : array<VkPipelineShaderStageCreateInfo>;
        vtx_input : VkPipelineVertexInputStateCreateInfo;
        input_assembly : VkPipelineInputAssemblyStateCreateInfo;
        viewport : VkPipelineViewportStateCreateInfo;
        rasterizer : VkPipelineRasterizationStateCreateInfo;
        multisampling : VkPipelineMultisampleStateCreateInfo;
        blending : VkPipelineColorBlendStateCreateInfo
    )>
)
    with_pipeline_stages(vert_shmod, frag_shmod) <| $(stages) {
    with_pipeline_vertex_input() <| $(vtx_input) {
    with_pipeline_blending() <| $(blending) {
    phys_dev |> with_pipeline_viewport(surface, window) <| $(viewport) {
        b |> invoke(
            stages,
            vtx_input,
            make_pipeline_input_assembly(),
            viewport,
            make_pipeline_rasterizer(),
            make_pipeline_multisampling(),
            blending
        );
    }}}}


def with_graphics_pipeline(device, layout, render_pass,
    phys_dev, surface, window, vert_shmod, frag_shmod;
    b : block<(p:VkPipeline)>
)
    with_pipeline_creation_subobjects(
        phys_dev, surface, window, vert_shmod, frag_shmod
    ) <| $(stages, vtx_input, input_assembly, viewport, rasterizer,
        multisampling, blending
    )
        let pipe_infos <- [[auto[] [[VkGraphicsPipelineCreateInfo
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO),
            layout = layout,
            renderPass = render_pass,
            stageCount = uint(stages |> length()),
            pStages = stages[0] |> safe_addr_plain(),
            pVertexInputState = vtx_input |> safe_addr(),
            pInputAssemblyState = input_assembly |> safe_addr(),
            pViewportState = viewport |> safe_addr(),
            pRasterizationState = rasterizer |> safe_addr(),
            pMultisampleState = multisampling |> safe_addr(),
            pColorBlendState = blending |> safe_addr(),
            basePipelineIndex = -1
        ]]]]
        var pipes : array<VkPipeline>
        pipes |> resize(pipe_infos |> length())
        verify(VkResult VK_SUCCESS == device |> vkCreateGraphicsPipelines(
            [[VkPipelineCache]],
            uint(pipe_infos |> length()), pipe_infos[0] |> safe_addr(),
            null, pipes[0] |> safe_addr_val()))
        b |> invoke(pipes[0])
        for pipe in pipes
            device |> vkDestroyPipeline(pipe, null)
        delete pipes


def with_swap_chain_framebuffers(
    device, phys_dev, surface, window, views, render_pass;
    b : block<(fbs:array<VkFramebuffer>)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    var fbufs : array<VkFramebuffer>
    fbufs |> resize(views |> length())
    for fbuf, view in fbufs, views
        let atts <- [[auto[] view]]
        let create_info <- [[VkFramebufferCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            renderPass = render_pass,

            //TODO: make it work. says "can only dereference simple type"
            attachmentCount = 1u, 
            //attachmentCount = uint(atts |> length()),

            pAttachments = atts[0] |> safe_addr(),
            width = extent.width,
            height = extent.height,
            layers = 1u
        ]]
        verify(VkResult VK_SUCCESS == device |> vkCreateFramebuffer(
            create_info |> safe_addr(), null, fbuf |> safe_addr()))
    b |> invoke(fbufs)
    for fbuf in fbufs
        device |> vkDestroyFramebuffer(fbuf, null)
    delete fbufs


def with_command_pool(device, phys_dev, surface; b : block<(p:VkCommandPool)>)
    phys_dev |> with_graphics_queue_family(surface) <| $(qfam)
        let create_info <- [[VkCommandPoolCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = qfam
        ]]
        var pool : VkCommandPool
        verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
            create_info |> safe_addr(), null, pool |> safe_addr()))
        b |> invoke(pool)
        device |> vkDestroyCommandPool(pool, null)


def with_buffer(device, buf_size, usage; b : block<(b:VkBuffer)>)
    let create_info <- [[VkBufferCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        size = uint64(buf_size),
        usage = usage,
        sharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE
    ]]
    var buf : VkBuffer
    verify(VkResult VK_SUCCESS == device |> vkCreateBuffer(
        create_info |> safe_addr(), null, buf |> safe_addr()))
    b |> invoke(buf)
    device |> vkDestroyBuffer(buf, null)


def with_memory(device, size, mem_type; b : block<(m:VkDeviceMemory)>)
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type
    ]]
    var mem : VkDeviceMemory
    verify(VkResult VK_SUCCESS == device |> vkAllocateMemory(
        alloc_info |> safe_addr(), null, mem |> safe_addr()))
    b |> invoke(mem)
    device |> vkFreeMemory(mem, null)


def with_memory_type(phys_dev, type_filter, needed_flags; b : block<(t:uint)>)
    var actual_props : VkPhysicalDeviceMemoryProperties
    phys_dev |> vkGetPhysicalDeviceMemoryProperties(
        actual_props |> safe_addr())
    for type_i in range(actual_props.memoryTypeCount)
        if ((1u << uint(type_i)) & type_filter) == 0u
            continue
        let actual_flags = actual_props.memoryTypes[type_i].propertyFlags
        if (actual_flags & needed_flags) == needed_flags
            b |> invoke(uint(type_i))
            return


def with_buf_mem(device, phys_dev, buffer, mem_props;
    b : block<(m:VkDeviceMemory)>
)
    var mem_reqs : VkMemoryRequirements
    device |> vkGetBufferMemoryRequirements(buffer, mem_reqs |> safe_addr())
    phys_dev |> with_memory_type(mem_reqs.memoryTypeBits, mem_props
    ) <| $(mem_type)
        device |> with_memory(mem_reqs.size, mem_type) <| $(mem)
            b |> invoke(mem)


def with_mem_backed_buf(device, phys_dev, buf_size, usage, mem_props;
    b : block<(b:VkBuffer; m:VkDeviceMemory)>
)
    device |> with_buffer(buf_size, usage) <| $(buf)
        device |> with_buf_mem(phys_dev, buf, mem_props) <| $(mem)
            verify(VkResult VK_SUCCESS ==
                device |> vkBindBufferMemory(buf, mem, uint64(0)))
            b |> invoke(buf, mem)


def with_mapped_vk_mem(device, mem, offset, size;
    b : block<(var a:array<auto(T)>#)>
)
    var mem_ptr : void?
    verify(VkResult VK_SUCCESS == device |> vkMapMemory(
        mem, uint64(offset), uint64(size), 0u, mem_ptr |> safe_addr()))
    unsafe
        mem_ptr |> map_to_array(size) <| $(var mapped : array<T>#)
            b |> invoke(mapped)
    device |> vkUnmapMemory(mem)


def with_cmd_bufs(device, cmd_pool, count;
    b : block<(c:array<VkCommandBuffer>)>
)
    let alloc_info <- [[VkCommandBufferAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        level = VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        commandPool = cmd_pool,
        commandBufferCount = uint(count)
    ]]
    var bufs : array<VkCommandBuffer>
    bufs |> resize(count)
    verify(VkResult VK_SUCCESS == device |> vkAllocateCommandBuffers(
        alloc_info |> safe_addr(), bufs[0] |> safe_addr_val()))
    b |> invoke(bufs)
    device |> vkFreeCommandBuffers(
        cmd_pool, uint(count), bufs[0] |> safe_addr_val())
    delete bufs


def record(cmd_buf : VkCommandBuffer; b : block)
    let begin_info <- [[VkCommandBufferBeginInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO]]
    verify(VkResult VK_SUCCESS ==
        cmd_buf |> vkBeginCommandBuffer(begin_info |> safe_addr()))
    b |> invoke()
    cmd_buf |> vkEndCommandBuffer()


def record_render_pass(cmd_buf, phys_dev, window, surface, render_pass, fbuf;
    b : block
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    cmd_buf |> record() <| $()
        let clear_values <- [[auto[] [[VkClearValue]]]]
        let info <- [[VkRenderPassBeginInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            renderPass = render_pass,
            framebuffer = fbuf,
            renderArea = [[VkRect2D extent = extent]],
            clearValueCount = uint(clear_values |> length()),
            pClearValues = clear_values |> safe_addr()
        ]]
        cmd_buf |> vkCmdBeginRenderPass(
            info |> safe_addr(), VkSubpassContents VK_SUBPASS_CONTENTS_INLINE)
        b |> invoke()
        cmd_buf |> vkCmdEndRenderPass()


def submit(queue : VkQueue; cmd_bufs : array<VkCommandBuffer>)
    let infos <- [[auto[] [[VkSubmitInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SUBMIT_INFO,
        commandBufferCount = uint(cmd_bufs |> length()),
        pCommandBuffers = cmd_bufs[0] |> safe_addr_plain()
    ]]]]
    verify(VkResult VK_SUCCESS == queue |> vkQueueSubmit(
        uint(infos |> length()), infos[0] |> safe_addr(), [[VkFence]]))


def copy_buf_sync(device, cmd_pool, queue, src_buf, dst_buf, buf_size)
    device |> with_cmd_bufs(cmd_pool, 1) <| $(cmd_bufs)
        let cmd_buf = cmd_bufs[0]
        cmd_buf |> record() <| $()
            let params <- [[auto[] [[VkBufferCopy size = uint64(buf_size)]]]]
            cmd_buf |> vkCmdCopyBuffer(src_buf, dst_buf,
                uint(params |> length()), params[0] |> safe_addr())
        queue |> submit(cmd_bufs)
        queue |> vkQueueWaitIdle()


def with_draw_commands(device, phys_dev, window, surface, render_pass,
    fbufs, pipeline, cmd_pool, queue, vbuf, vertices_count;
    b : block<(cmds:array<VkCommandBuffer>)>
)
    let vbufs <- [[auto[] vbuf]]
    let offsets : uint64[1]
    device |> with_cmd_bufs(cmd_pool, fbufs |> length()) <| $(cmd_bufs)
        for cmd_buf, fbuf in cmd_bufs, fbufs
            cmd_buf |> record_render_pass(
                phys_dev, window, surface, render_pass, fbuf
            ) <| $()
                cmd_buf |> vkCmdBindPipeline(
                    VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS,
                    pipeline)
                cmd_buf |> vkCmdBindVertexBuffers(0u, // first binding idx
                    //TODO: make it work. says "can only dereference
                    //      simple type"
                    1u,
                    //uint(vbufs |> length()),

                    vbufs[0] |> safe_addr(),
                    offsets[0] |> safe_addr())
                cmd_buf |> vkCmdDraw(uint(vertices_count),
                    1u, // instance count
                    0u, // first vertex
                    0u  // first instance
                )

        b |> invoke(cmd_bufs)


def with_baked_vertex_buffer(device, phys_dev, cmd_pool, queue;
    vertices:array<auto(VT)>; b : block<(b:VkBuffer)>
)
    let buf_size = typeinfo(sizeof type<VT>) * vertices |> length()

    device |> with_mem_backed_buf(phys_dev, buf_size,
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_DST_BIT) |
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_VERTEX_BUFFER_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    ) <| $(vbuf, vbuf_mem)

        device |> with_mem_backed_buf(phys_dev, buf_size,
            uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
            uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)|
            uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
        ) <| $(staging_buf, staging_mem)
            device |> with_mapped_vk_mem(staging_mem, 0, buf_size
            ) <| $(var mapped_vertices : array<VT>#)
                for dst, src in mapped_vertices, vertices
                    dst = src
            device |> copy_buf_sync(
                cmd_pool, queue, staging_buf, vbuf, buf_size)

        b |> invoke(vbuf)


def with_semaphores(device, count; b : block<(sems:array<VkSemaphore>)>)
    var sems : array<VkSemaphore>
    sems |> resize(count)
    let info <- [[VkSemaphoreCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO]]
    for sem in sems
        verify(VkResult VK_SUCCESS == device |> vkCreateSemaphore(
            info |> safe_addr(), null, sem |> safe_addr_val()))
    b |> invoke(sems)
    for sem in sems
        device |> vkDestroySemaphore(sem, null)
    delete sems


def with_fences(device, count, flags; b : block<(fences:array<VkFence>)>)
    var fences : array<VkFence>
    fences |> resize(count)
    let info <- [[VkFenceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        flags = flags
    ]]
    for fence in fences
        verify(VkResult VK_SUCCESS == device |> vkCreateFence(
            info |> safe_addr(), null, fence |> safe_addr_val()))
    b |> invoke(fences)
    for fence in fences
        device |> vkDestroyFence(fence, null)
    delete fences


def with_swap_chain_independent_state(width, height, title; b : block<(
    instance : VkInstance;
    window : GLFWwindow_DasHandle;
    surface : VkSurfaceKHR;
    phys_dev : VkPhysicalDevice;
    device : VkDevice;
    queue : VkQueue;
    surf_fmt : VkSurfaceFormatKHR;
    present_mode : VkPresentModeKHR;
    vert_shmod : VkShaderModule;
    frag_shmod : VkShaderModule;
    render_pass : VkRenderPass;
    pipeline_layout : VkPipelineLayout;
    cmd_pool : VkCommandPool
)>)
    with_instance()                                 <| $(instance) {
    with_window(width, height, title)               <| $(window) {
    window |> with_surface(instance)                <| $(surface) {
    instance |> with_best_physical_device(surface)  <| $(phys_dev) {
    instance |> with_device(phys_dev, surface)      <| $(device, queue) {
    phys_dev |> with_best_format(surface)           <| $(surf_fmt) {
    phys_dev |> with_best_present_mode(surface)     <| $(present_mode) {
    device |> with_shader_module("vert")            <| $(vert_shmod) {
    device |> with_shader_module("frag")            <| $(frag_shmod) {
    device |> with_render_pass(surf_fmt)            <| $(render_pass) {
    device |> with_pipeline_layout()                <| $(pipeline_layout) {
    device |> with_command_pool(phys_dev, surface)  <| $(cmd_pool)
    {
        b |> invoke(
            instance,
            window,
            surface,
            phys_dev,
            device,
            queue,
            surf_fmt,
            present_mode,
            vert_shmod,
            frag_shmod,
            render_pass,
            pipeline_layout,
            cmd_pool
        );
    }}}}}}}}}}}}


def with_swap_chain_dependent_state(
    instance,
    window,
    surface,
    phys_dev,
    device,
    queue,
    surf_fmt,
    present_mode,
    vert_shmod,
    frag_shmod,
    render_pass,
    pipeline_layout,
    cmd_pool;
    b : block<(
        swap_chain : VkSwapchainKHR;
        sc_imgs : array<VkImage>;
        sc_views : array<VkImageView>;
        sc_fbufs : array<VkFramebuffer>;
        pipeline : VkPipeline;
        img_avail_sems : array<VkSemaphore>;
        render_done_sems : array<VkSemaphore>;
        frame_fences : array<VkFence>
)>)
    device |> with_swap_chain(phys_dev, surface,
        window, surf_fmt, present_mode)             <| $(swap_chain) {
    device |> with_swap_chain_images(swap_chain)    <| $(sc_imgs) {
    device |> with_swap_chain_image_views(
        sc_imgs, surf_fmt)                          <| $(sc_views) {
    device |> with_swap_chain_framebuffers(
        phys_dev, surface, window, sc_views,
        render_pass)                                <| $(sc_fbufs) {
    device |> with_graphics_pipeline(layout,
        render_pass, phys_dev, surface, window,
        vert_shmod, frag_shmod)                     <| $(pipeline) {
    device |> with_semaphores(MAX_FRAMES_IN_FLIGHT) <| $(img_avail_sems) {
    device |> with_semaphores(MAX_FRAMES_IN_FLIGHT) <| $(render_done_sems) {
    device |> with_fences(MAX_FRAMES_IN_FLIGHT,
        uint(VkFenceCreateFlagBits
            VK_FENCE_CREATE_SIGNALED_BIT))          <| $(frame_fences)
    {
        b |> invoke(
            swap_chain,
            sc_imgs,
            sc_views,
            sc_fbufs,
            pipeline
        );
    }}}}}}}}


def wait(device; fence : VkFence)
    verify(VkResult VK_SUCCESS == device |> vkWaitForFences(
        1u, fence |> safe_addr(), uint(VK_TRUE), UINT64_MAX))


[export]
def main
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    let vertices <- [{auto[]
        [[Vertex position=float2( 0.0f, -0.5f), color=float3(1f, 0f, 0f)]];
        [[Vertex position=float2( 0.5f,  0.5f), color=float3(0f, 1f, 0f)]];
        [[Vertex position=float2(-0.5f,  0.5f), color=float3(0f, 0f, 1f)]]
    }]

    with_swap_chain_independent_state(800, 600, "dasVulkanExample") <| $(
        instance,
        window,
        surface,
        phys_dev,
        device,
        queue,
        surf_fmt,
        present_mode,
        vert_shmod,
        frag_shmod,
        render_pass,
        pipeline_layout,
        cmd_pool
    )
        var props <- phys_dev |> get_properties()
        print("Using {props.deviceName |> to_string()}\n")
        device |> with_baked_vertex_buffer(
            phys_dev, cmd_pool, queue, vertices
        ) <| $(vbuf)
            with_swap_chain_dependent_state(
                instance,
                window,
                surface,
                phys_dev,
                device,
                queue,
                surf_fmt,
                present_mode,
                vert_shmod,
                frag_shmod,
                render_pass,
                pipeline_layout,
                cmd_pool
            ) <| $(
                swap_chain : VkSwapchainKHR;
                sc_imgs : array<VkImage>;
                sc_views : array<VkImageView>;
                sc_fbufs : array<VkFramebuffer>;
                pipeline : VkPipeline;
                img_avail_sems : array<VkSemaphore>;
                render_done_sems : array<VkSemaphore>;
                frame_fences : array<VkFence>
            )
                device |> with_draw_commands(phys_dev, window, surface,
                    render_pass, sc_fbufs, pipeline, cmd_pool, queue,
                    vbuf, vertices |> length()
                ) <| $(sc_draw_cmds)
                    var current_frame = 0
                    while window |> glfwWindowShouldClose() == 0
                        glfwPollEvents()

    glfwTerminate()
    print("Finished\n")
    return true
