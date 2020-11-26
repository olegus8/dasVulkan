options indenting = 4
options no_aot = true

module vulkan_boost

require daslib/safe_addr
require math
require vulkan

require internal/buffer      public
require internal/core        public
require internal/device      public
require internal/render_pass public
require internal/swap_chain  public
require internal/pipeline    public


def with_swap_chain_framebuffers(
    device      : VkDevice#;
    phys_dev    : VkPhysicalDevice#;
    surface     : VkSurfaceKHR#;
    window      : GLFWwindow_DasHandle#;
    views       : array<VkImageView>#;
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
    let qfam = phys_dev |> get_graphics_queue_family(surface)
    let create_info <- [[VkCommandPoolCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = qfam
    ]]
    var pool : VkCommandPool
    verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
        safe_addr(create_info), null, safe_addr(pool)))
    b |> invoke(pool)
    device |> vkDestroyCommandPool(pool, null)


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


def with_memory_type(
    phys_dev : VkPhysicalDevice#;
    type_filter : uint;
    needed_flags : uint;
    b : block<(t:uint)>
)
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


def with_buf_mem(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    buffer : VkBuffer#;
    mem_props : uint;
    b : block<(m:VkDeviceMemory#)>
)
    var mem_reqs : VkMemoryRequirements
    device |> vkGetBufferMemoryRequirements(buffer, mem_reqs |> safe_addr())
    phys_dev |> with_memory_type(mem_reqs.memoryTypeBits, mem_props
    ) <| $(mem_type)
        device |> with_memory(mem_reqs.size, mem_type) <| $(mem)
            b |> invoke(mem)


def with_mem_backed_buf(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    buf_size : uint64;
    offset : uint64;
    usage : uint;
    mem_props : uint;
    b : block<(b:VkBuffer#; m:VkDeviceMemory#)>
)
    device |> with_buffer(buf_size, usage) <| $(buf)
        device |> with_buf_mem(phys_dev, buf, mem_props) <| $(mem)
            verify(VkResult VK_SUCCESS ==
                device |> vkBindBufferMemory(buf, mem, offset))
            b |> invoke(buf, mem)
