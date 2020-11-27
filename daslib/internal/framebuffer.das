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
    assert(attachments |> length() > 0)

    var patts : VkImageView?
    unsafe
        patts = addr(attachments[0])

    let create_info <- [[VkFramebufferCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO),
        renderPass = render_pass,
        attachmentCount = uint(tatts |> length()),
        width = width,
        height = height,
        layers = layers,
        flags = flags,

        //TODO: does not work with array lock and safe_addr saying this:
        //  can't initialize field pAttachments;
        //  expecting vulkan::VkImageView const? const&,
        //  passing vulkan::VkImageView const# =const? const#
        //pAttachments = safe_addr(tatts[0]),
        pAttachments = patts
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
    var atts <- [{auto[] attachment}]
    defer() <| ${ delete atts; }
    return <- create_framebuffer([device=device, render_pass=render_pass,
        attachments=atts, width=width, height=height, layers=layers,
        flags=flags])


def finalize(var fbuf : Framebuffer)
    fbuf.device |> vkDestroyFramebuffer(fbuf.framebuffer, null)
    memzero(fbuf)
