options indenting = 4
options no_aot = true

require daslib/defer
require generated


def create_single_view_framebuffer(
    device : Device;
    render_pass : RenderPass;
    view : ImageView;
    width : uint ;
    height : uint
) : Framebuffer
    var create_info <- [[FramebufferCreateInfo
        render_pass = render_pass,
        attachments <- [{auto[] view}],
        width = width,
        height = height,
        layers = 1u
    ]]
    defer() <|
        create_info.attachments |> resize(0)
        memzero(create_info.render_pass)
        delete create_info

    return <- device |> create_framebuffer(create_info)
