options indenting = 4
options no_aot = true

module vulkan_boost

require daslib/safe_addr
require fio
require math
require vulkan


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


let
    REQUIRED_EXTENSIONS = [[auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ]]

    ATT_BLENDING_DISABLED <- [[VkPipelineColorBlendAttachmentState
        colorWriteMask =
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_R_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_G_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_B_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_A_BIT)
    ]]

    PIPELINE_BLENDING_DISABLED <- [[VkPipelineColorBlendStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO),
        attachmentCount = 1u,
        pAttachments = safe_addr(ATT_BLENDING_DISABLED)
    ]]

    PIPELINE_MULTISAMPLING_DISABLED <- [[VkPipelineMultisampleStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO),
        rasterizationSamples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        minSampleShading = 1.0f
    ]]

    PIPELINE_RASTERIZER_SIMPLE <- [[VkPipelineRasterizationStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO),
        polygonMode = VkPolygonMode VK_POLYGON_MODE_FILL,
        lineWidth = 1.0f,
        cullMode = uint(VkCullModeFlagBits VK_CULL_MODE_BACK_BIT),
        frontFace = VkFrontFace VK_FRONT_FACE_CLOCKWISE
    ]]

    PIPELINE_INPUT_ASSEMBLY_TRI_LIST <- [[
        VkPipelineInputAssemblyStateCreateInfo
        sType = (VkStructureType 
            VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO),
        topology = VkPrimitiveTopology VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
    ]]


def with_physical_devices(
    inst : VkInstance#; b : block<(d:array<VkPhysicalDevice>#)>
)
    var devices : array<VkPhysicalDevice>
    var count : uint
    verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
        safe_addr(count), null))
    devices |> resize(int(count))
    devices |> lock() <| $(tdevices)
        verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
            safe_addr(count), addr(tdevices[0])))
        b |> invoke(tdevices)
    delete devices


def with_best_physical_device(inst : VkInstance#; surface : VkSurfaceKHR#;
    b : block<(d:VkPhysicalDevice#)>
)
    var best_score : int = 0
    var best_device : VkPhysicalDevice
    inst |> with_physical_devices() <| $(devices)
        for device in devices
            var score = device |> get_suitability_score(surface)
            if score > best_score
                best_score = score
                unsafe
                    best_device = reinterpret<VkPhysicalDevice>(device)
        if best_score == 0
            panic("No suitable physical device found.")
    b |> invoke(best_device)


[private]
def get_suitability_score(device : VkPhysicalDevice#; surface : VkSurfaceKHR#)
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


def with_queue_families(device : VkPhysicalDevice#;
    b : block<(families: array<VkQueueFamilyProperties>#)>
)
    var families : array<VkQueueFamilyProperties>
    var count : uint
    device |> vkGetPhysicalDeviceQueueFamilyProperties(
        safe_addr(count), null)
    families |> resize(int(count))
    families |> lock() <| $(tfamilies)
        device |> vkGetPhysicalDeviceQueueFamilyProperties(
            safe_addr(count), addr(tfamilies[0]))
        b |> invoke(tfamilies)
    delete families


def with_graphics_queue_family(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(index:uint)>
)
    var found_index : int = -1
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

            found_index = index
            break

    if found_index != -1
        b |> invoke(uint(found_index))


def get_properties(device : VkPhysicalDevice#)
    var props : VkPhysicalDeviceProperties
    device |> vkGetPhysicalDeviceProperties(safe_addr(props))
    return <- props


def with_ext_props(device : VkPhysicalDevice#;
    b : block<(props:table<uint;VkExtensionProperties>)>
)
    var props : array<VkExtensionProperties>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkEnumerateDeviceExtensionProperties(
            to_string(null), safe_addr(count), null))
    props |> resize(int(count))
    props |> lock() <| $(tprops)
        verify(VkResult VK_SUCCESS ==
            device |> vkEnumerateDeviceExtensionProperties(
                to_string(null), safe_addr(count), addr(tprops[0])))

    var props_table : table<uint; VkExtensionProperties>
    for prop in props
        let name <- prop.extensionName |> to_string()
        props_table[hash(name)] <- prop
    props_table |> lock() <| $(tprops_table)
        pass
        //TODO: make it work
        //b |> invoke(tprops_table)
    b |> invoke(props_table)
    delete props


def with_formats(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(formats:array<VkSurfaceFormatKHR>#)>
)
    var formats : array<VkSurfaceFormatKHR>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
            surface, safe_addr(count), null))
    formats |> resize(int(count))
    formats |> lock() <| $(tformats)
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfaceFormatsKHR(
                surface, safe_addr(count), addr(tformats[0])))
        b |> invoke(tformats)
    delete formats


def get_format_srgb8(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(format:VkSurfaceFormatKHR)>
)
    return <- device |> get_best_format(surface,
        VkFormat VK_FORMAT_B8G8R8A8_SRGB,
        VkColorSpaceKHR VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)


def get_best_format(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    preferred_format : VkFormat;
    preferred_color_space : VkColorSpaceKHR;
) : VkSurfaceFormatKHR
    var best_format : VkSurfaceFormatKHR
    device |> with_formats(surface) <| $(formats)
        // picking ideal format if available
        for format in formats
            if (format.format == VkFormat VK_FORMAT_B8G8R8A8_SRGB
            &&  format.colorSpace == (VkColorSpaceKHR
                    VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            )
                best_format = format
                return
        // if no ideal found, picking anything
        for format in formats
            best_format = format
            return
        panic("No surface formats.")
    return <- best_format


def with_present_modes(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(formats:array<VkPresentModeKHR>#)>
)
    var modes : array<VkPresentModeKHR>
    var count : uint
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
            surface, safe_addr(count), null))
    modes |> resize(int(count))
    modes |> lock() <| $(tmodes)
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfacePresentModesKHR(
                surface, safe_addr(count), addr(tmodes[0])))
        b |> invoke(tmodes)
    delete modes


def with_best_present_mode(device : VkPhysicalDevice#; surface : VkSurfaceKHR#;
    b : block<(mode:VkPresentModeKHR#)>
)
    device |> with_present_modes(surface) <| $(modes)
        for preferred in [[auto[]
            VkPresentModeKHR VK_PRESENT_MODE_MAILBOX_KHR;
            VkPresentModeKHR VK_PRESENT_MODE_FIFO_KHR
        ]]
            for mode in modes
                if mode == preferred
                    b |> invoke(mode)
                    return


def with_window(width : int; height : int; title : string;
    b : block<(w:GLFWwindow_DasHandle#)>
)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    b |> invoke(window)
    window |> glfwDestroyWindow()


def with_instance(b : block<(inst:VkInstance#)>)
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


def with_surface(window : GLFWwindow_DasHandle#; instance : VkInstance#;
    b : block<(s:VkSurfaceKHR#)>
)
    var surface : VkSurfaceKHR
    verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
        window, null, safe_addr(surface)))
    b |> invoke(surface)
    instance |> vkDestroySurfaceKHR(surface, null)


def with_device(
    instance : VkInstance#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR;
    b : block<(device:VkDevice#; queue:VkQueue#)>
)
    phys_dev |> with_queue_create_infos(surface) <| $(queue_infos)
        var pqueue_infos : VkDeviceQueueCreateInfo const ?
        unsafe
            pqueue_infos = reinterpret<VkDeviceQueueCreateInfo const ?>(addr(queue_infos[0]))
        let features : VkPhysicalDeviceFeatures
        var device : VkDevice
        let create_info = [[VkDeviceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            pQueueCreateInfos = pqueue_infos,
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


[private]
def with_queue_create_infos(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(infos:array<VkDeviceQueueCreateInfo>#)>
)
    var families : array<uint>
    var priorities : array<float>
    device |> with_graphics_queue_family(surface) <| $(qfam)
        families |> push(qfam)
        priorities |> push(1.0f)

    var infos : array<VkDeviceQueueCreateInfo>
    infos |> reserve(families |> length())
    priorities |> lock() <| $(tpriorities)
        var ppriorities : float const ?
        unsafe
            ppriorities = reinterpret<float const ?>(addr(tpriorities[0]))
        for family in families
            infos |> emplace([[
                VkDeviceQueueCreateInfo
                    sType = (VkStructureType
                        VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO),
                    queueFamilyIndex = family,
                    queueCount = uint(priorities |> length()),
                    pQueuePriorities = ppriorities
            ]])

    infos |> lock() <| $(tinfos)
        b |> invoke(tinfos)

    delete families
    delete priorities
    delete infos


def get_swap_extent(
    device : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    window : GLFWwindow_DasHandle#
)
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


def get_framebuffer_size(window : GLFWwindow_DasHandle#)
    var width, height : int
    window |> glfwGetFramebufferSize(safe_addr(width), safe_addr(height))
    return uint2(uint(width), uint(height))


def get_capabilities(device : VkPhysicalDevice#; surface : VkSurfaceKHR#)
    var caps : VkSurfaceCapabilitiesKHR
    verify(VkResult VK_SUCCESS ==
        device |> vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            surface, safe_addr(caps)))
    return <- caps


def with_swap_chain(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    window : GLFWwindow_DasHandle#;
    surf_fmt : VkSurfaceFormatKHR#;
    present_mode : VkPresentModeKHR#;
    b : block<(sc:VkSwapchainKHR#)>
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


def with_swap_chain_images(device : VkDevice#; swap_chain : VkSwapchainKHR#;
    b : block<(d:array<VkImage>#)>
)
    var images : array<VkImage>
    var count : uint
    verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
        swap_chain, safe_addr(count), null))
    images |> resize(int(count))
    images |> lock() <| $(timages)
        verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
            swap_chain, safe_addr(count), addr(timages[0])))
        b |> invoke(timages)
    delete images


def with_swap_chain_image_views(
    device : VkDevice#;
    images : array<VkImage>#;
    surf_fmt : VkSurfaceFormatKHR#;
    b : block<(d:array<VkImageView>#)>
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

    views |> lock() <| $(tviews)
        b |> invoke(tviews)

    for view in views
        device |> vkDestroyImageView(view, null)
    delete views


def with_render_pass_simple(
    device : VkDevice#;
    surf_fmt : VkSurfaceFormatKHR#;
    b : block<(rp:VkRenderPass#)>
)
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


def with_pipeline_layout_simple(device : VkDevice#;
    b : block<(layout:VkPipelineLayout#)>
)
    let create_info <- [[ VkPipelineLayoutCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
    ]]
    var layout : VkPipelineLayout
    verify(VkResult VK_SUCCESS == device |> vkCreatePipelineLayout(
        create_info |> safe_addr(), null, layout |> safe_addr()))
    b |> invoke(layout)
    device |> vkDestroyPipelineLayout(layout, null)


def with_pipeline_shader_stages(
    vert : VkShaderModule#; vert_main : string;
    frag : VkShaderModule#; frag_main : string;
    b : block<(s:array<VkPipelineShaderStageCreateInfo>#)>
)
    var stages <- [{auto[]
        [[VkPipelineShaderStageCreateInfo module_ = vert, pName = vert_main,
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO),
            stage = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT
        ]];
        [[VkPipelineShaderStageCreateInfo module_ = frag, pName = frag_main,
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO),
            stage = VkShaderStageFlagBits VK_SHADER_STAGE_FRAGMENT_BIT
        ]]
    }]
    stages |> lock() <| $(tstages)
        b |> invoke(tstages)
    delete stages


def with_pipeline_viewport_full_window(
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR;
    window : GLFWwindow_DasHandle#;
    //TODO: make it pass temporary. compilation fails currently if i do
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


def with_graphics_pipeline_simple(
    device          : VkDevice#;
    layout          : VkPipelineLayout#;
    render_pass     : VkRenderPass#;
    stages          : array<VkPipelineShaderStageCreateInfo>#;
    vtx_input       : VkPipelineVertexInputStateCreateInfo;
    input_assembly  : VkPipelineInputAssemblyStateCreateInfo;
    viewport        : VkPipelineViewportStateCreateInfo;
    rasterizer      : VkPipelineRasterizationStateCreateInfo;
    multisampling   : VkPipelineMultisampleStateCreateInfo;
    blending        : VkPipelineColorBlendStateCreateInfo implicit;
    b : block<(p:VkPipeline#)>
)
    var pstages : VkPipelineShaderStageCreateInfo const ?
    unsafe
        pstages = reinterpret<VkPipelineShaderStageCreateInfo const ?>(
            addr(stages[0]))
    let pipe_info <- [[VkGraphicsPipelineCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO),
        layout              = layout,
        renderPass          = render_pass,
        stageCount          = uint(stages |> length()),
        pStages             = pstages,
        pVertexInputState   = vtx_input |> safe_addr(),
        pInputAssemblyState = input_assembly |> safe_addr(),
        pViewportState      = viewport |> safe_addr(),
        pRasterizationState = rasterizer |> safe_addr(),
        pMultisampleState   = multisampling |> safe_addr(),
        pColorBlendState    = blending |> safe_addr(),
        basePipelineIndex   = -1
    ]]
    var pipe : VkPipeline
    verify(VkResult VK_SUCCESS == device |> vkCreateGraphicsPipelines(
        [[VkPipelineCache]], 1u, safe_addr(pipe_info), null, safe_addr(pipe)))
    b |> invoke(pipe)
    device |> vkDestroyPipeline(pipe, null)


def with_shader_modules(device: VkDevice#; code_fpaths : auto;
    b : block<(m:array<VkShaderModule>#)>
)
    var shmods : array<VkShaderModule>
    shmods |> resize(code_fpaths |> length())
    shmods |> lock() <| $(tshmods)
        for code_fpath, tshmod in code_fpaths, tshmods
            var code : string
            var code_size : uint64
            code_fpath |> fopen("rb") <| $(f)
                code <- f |> fread()
                code_size = (f |> fstat()).size
            var code_ptr : uint?
            unsafe
                code_ptr = reinterpret<uint?>(code)
            let create_info <- [[VkShaderModuleCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO),
                codeSize = code_size,
                pCode = code_ptr
            ]]
            verify(VkResult VK_SUCCESS == device |> vkCreateShaderModule(
                create_info |> safe_addr(), null, addr(tshmod)))
        b |> invoke(tshmods)

    for shmod in shmods
        device |> vkDestroyShaderModule(shmod, null)
    delete shmods


def with_swap_chain_framebuffers(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    window : GLFWwindow_DasHandle#;
    views : array<VkImageView>#;
    render_pass : VkRenderPass#;
    b : block<(fbs:array<VkFramebuffer>#)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    var fbufs : array<VkFramebuffer>
    fbufs |> resize(views |> length())
    fbufs |> lock() <| $(tfbufs)
        for tfbuf, view in tfbufs, views
            var pview : VkImageView const ?
            unsafe
                pview = reinterpret<VkImageView const ?>(addr(view))
            let create_info <- [[VkFramebufferCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO),
                renderPass = render_pass,

                //TODO: make it work. says "can only dereference simple type"
                attachmentCount = 1u, 

                pAttachments = pview,
                width = extent.width,
                height = extent.height,
                layers = 1u
            ]]
            verify(VkResult VK_SUCCESS == device |> vkCreateFramebuffer(
                safe_addr(create_info), null, addr(tfbuf)))
        b |> invoke(tfbufs)
    for fbuf in fbufs
        device |> vkDestroyFramebuffer(fbuf, null)
    delete fbufs


def with_command_pool(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(p:VkCommandPool#)>
)
    phys_dev |> with_graphics_queue_family(surface) <| $(qfam)
        let create_info <- [[VkCommandPoolCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = qfam
        ]]
        var pool : VkCommandPool
        verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
            safe_addr(create_info), null, safe_addr(pool)))
        b |> invoke(pool)
        device |> vkDestroyCommandPool(pool, null)


def with_buffer(
    device : VkDevice#;
    buf_size : uint64;
    usage : uint;
    b : block<(b:VkBuffer#)>
)
    let create_info <- [[VkBufferCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        size = buf_size,
        usage = usage,
        sharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE
    ]]
    var buf : VkBuffer
    verify(VkResult VK_SUCCESS == device |> vkCreateBuffer(
        create_info |> safe_addr(), null, buf |> safe_addr()))
    b |> invoke(buf)
    device |> vkDestroyBuffer(buf, null)


def with_memory(
    device : VkDevice#;
    size : uint64;
    mem_type_index : uint;
    b : block<(m:VkDeviceMemory#)>
)
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type_index
    ]]
    var mem : VkDeviceMemory
    verify(VkResult VK_SUCCESS == device |> vkAllocateMemory(
        alloc_info |> safe_addr(), null, mem |> safe_addr()))
    b |> invoke(mem)
    device |> vkFreeMemory(mem, null)
