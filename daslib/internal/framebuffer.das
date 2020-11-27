options indenting = 4
options no_aot = true

require math

require daslib/safe_addr
require daslib/defer
require vulkan
require internal/device


struct Framebuffer
    device : VkDevice
    framebuffer : VkFramebuffer


def create_framebuffer(
    device : VkDevice implicit;
    render_pass : VkRenderPass implicit;
    attachments : array<VkImageView> implicit;
    width : uint;
    height : uint;
    layers : uint;
    flags : uint = 0u
) : Framebuffer
    var fbuf : Framebuffer
    unsafe
        fbuf.device = reinterpret<VkDevice>(device)
    attachments |> lock() <| $(tatts)
        let create_info <- [[VkFramebufferCreateInfo
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO),
            renderPass = render_pass,
            attachmentCount = uint(tatts |> length()),
            pAttachments = safe_addr(tatts[0]),
            width = width,
            height = height,
            layers = layers,
            flags = flags
        ]]
        verify(VkResult VK_SUCCESS == device |> vkCreateFramebuffer(
            safe_addr(info), null, safe_addr(fbuf.framebuffer)))
    return <- fbuf


def create_framebuffer(
    device : VkDevice implicit;
    render_pass : VkRenderPass implicit;
    attachment : VkImageView implicit;
    width : uint;
    height : uint;
    layers : uint;
    flags : uint = 0u
) : Framebuffer
    var atts <- [{attachment}]
    defer() <| ${ delete atts; }
    return <- device |> create_framebuffer(render_pass, atts,
        width=width, height=height, layers=layers, flags=flags)


def finalize(var fbuf : Framebuffer)
    fbuf.device |> vkDestroyFramebuffer(fbuf.framebuffer, null)
    memzero(fbuf)

