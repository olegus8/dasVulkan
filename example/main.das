options log, log_infer_passes

require vulkan
require strings
require math
require daslib/safe_addr


let
    MAX_FRAMES_IN_FLIGHT = 2

    REQUIRED_EXTENSIONS = [[auto[]
        "VK_KHR_swapchain" //TODO: use VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ]]


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


//TODO: figure out what to do with it. it's for enum -> uint
def to_uint(x)
    unsafe
        return reinterpret<uint>(x)


//TODO: can we extend safe_addr to constants?
def safe_addr_const(x)
    unsafe
        return addr(x)


//TODO: make this better
def safe_addr_val(var x : auto&)
    unsafe
        return addr(x)


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

            var graphics_bit = to_uint(VkQueueFlagBits VK_QUEUE_GRAPHICS_BIT)
            if (family.queueFlags & graphics_bit) == 0u
                continue

            b |> invoke(uint(index))
            return


def with_device(instance, phys_dev, surface; b : block<(device:VkDevice)>)
    phys_dev |> with_queue_create_infos(surface) <| $(queue_infos)
        let features : VkPhysicalDeviceFeatures
        var device : VkDevice
        let create_info = [[VkDeviceCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            pQueueCreateInfos = safe_addr_const(queue_infos[0]),
            queueCreateInfoCount = uint(queue_infos |> length()),
            pEnabledFeatures = safe_addr_const(features),
            enabledExtensionCount = uint(REQUIRED_EXTENSIONS |> length()),
            ppEnabledExtensionNames = safe_addr_const(REQUIRED_EXTENSIONS[0])
        ]]
        verify(VkResult VK_SUCCESS == vkCreateDevice(
            phys_dev, safe_addr_const(create_info), null, safe_addr(device)))
        b |> invoke(device)
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
                pQueuePriorities = safe_addr_const(priorities[0])
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
    unsafe
        verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
            window, null, addr(surface)))
    b |> invoke(surface)
    instance |> vkDestroySurfaceKHR(surface, null)


def with_swap_chain(device, phys_dev, surface, window, surf_fmt, present_mode;
    b : block<(sc:VkSwapchainKHR)>
)
    var caps <- phys_dev |> get_capabilities(surface)
    var extent <- phys_dev |> get_swap_extent(surface, window)

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
        imageExtent = [[VkExtent2D width=extent[0], height=extent[1]]],
        imageArrayLayers = 1u, // 2 for stereoscopic
        imageUsage = to_uint(
            VkImageUsageFlagBits VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT),
        imageSharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE,
        preTransform = caps.currentTransform,
        compositeAlpha = (
            VkCompositeAlphaFlagBitsKHR VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR),
        presentMode = present_mode,
        clipped = uint(VK_TRUE)
    ]]

    var swap_chain : VkSwapchainKHR
    unsafe
        verify(VkResult VK_SUCCESS == device |> vkCreateSwapchainKHR(
            addr(create_info), null, addr(swap_chain)))
    b |> invoke(swap_chain)
    device |> vkDestroySwapchainKHR(swap_chain, null)


def get_swap_extent(device, surface, window)
    var caps <- device |> get_capabilities(surface)

    if caps.currentExtent.width != UINT_MAX
        return uint2(
            caps.currentExtent.width,
            caps.currentExtent.height)
    else
        var fb_size = window |> get_framebuffer_size()
        return uint2(
            clamp(fb_size[0],
                caps.minImageExtent.width,
                caps.maxImageExtent.width),
            clamp(fb_size[1],
                caps.minImageExtent.height,
                caps.maxImageExtent.height))


def get_framebuffer_size(window)
    var width, height : int
    unsafe
        window |> glfwGetFramebufferSize(addr(width), addr(height))
    return uint2(uint(width), uint(height))


def get_capabilities(device, surface)
    var caps : VkSurfaceCapabilitiesKHR
    unsafe
        verify(VkResult VK_SUCCESS ==
            device |> vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
                surface, addr(caps)))
    return <- caps


def with_swap_chain_images(device, swap_chain; b : block<(d:array<VkImage>)>)
    var images : array<VkImage>
    var count : uint
    unsafe
        verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
            swap_chain, addr(count), null))
        images |> resize(int(count))
        verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
            swap_chain, addr(count), addr(images[0])))
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
                aspectMask = to_uint(
                    VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
                baseMipLevel = 0u,
                levelCount = 1u,
                baseArrayLayer = 0u,
                layerCount = 1u]]
        ]]
        unsafe
            verify(VkResult VK_SUCCESS == device |> vkCreateImageView(
                addr(create_info), null, addr(view)))

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
        pColorAttachments = safe_addr_const(att_refs[0])
    ]]]]
    let deps <- [[auto[] [[VkSubpassDependency
        srcSubpass = VK_SUBPASS_EXTERNAL,
        dstSubpass = 0u,
        srcStageMask = to_uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        srcAccessMask = 0u,
        dstStageMask = to_uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        dstAccessMask = to_uint(VkAccessFlagBits
            VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
    ]]]]
    let create_info <- [[VkRenderPassCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO),
        attachmentCount = uint(atts |> length()),
        pAttachments = safe_addr_const(atts[0]),
        subpassCount = uint(subs |> length()),
        pSubpasses = safe_addr_const(subs[0]),
        dependencyCount = uint(deps |> length()),
        pDependencies = safe_addr_const(deps[0])
    ]]
    var rpass : VkRenderPass;
    verify(VkResult VK_SUCCESS == device |> vkCreateRenderPass(
        safe_addr_const(create_info), null, safe_addr(rpass)))
    b |> invoke(rpass)
    device |> vkDestroyRenderPass(rpass, null)


def with_graphics(width, height, title; b : block<(
    window : GLFWwindow_DasHandle;
    phys_dev : VkPhysicalDevice
)>)
    with_instance() <| $(instance) {
    with_window(width, height, title) <| $(window) {
    window |> with_surface(instance) <| $(surface) {
    instance |> with_best_physical_device(surface) <| $(phys_dev) {
    instance |> with_device(phys_dev, surface) <| $(device) {
    phys_dev |> with_best_format(surface) <| $(surf_fmt) {
    phys_dev |> with_best_present_mode(surface) <| $(present_mode) {
    device |> with_swap_chain(
        phys_dev, surface, window, surf_fmt, present_mode
    ) <| $(swap_chain) {
    device |> with_swap_chain_images(swap_chain) <| $(sc_imgs) {
    device |> with_swap_chain_image_views(sc_imgs, surf_fmt) <| $(sc_views) {
    device |> with_render_pass(surf_fmt) <| $(render_pass)
    {
        b |> invoke(window, phys_dev);
    }}}}}}}}}}}


[export]
def main
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    with_graphics(800, 600, "dasVulkanExample") <| $(window, phys_dev)
        var props <- phys_dev |> get_properties()
        print("Using {props.deviceName |> to_string()}\n")
        while window |> glfwWindowShouldClose() == 0
            glfwPollEvents()

    glfwTerminate()
    print("Finished\n")
    return true
