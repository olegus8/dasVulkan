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
        render_pass = weak_copy(render_pass),
        attachments <- [{auto[] weak_copy(view)}],
        width = width,
        height = height,
        layers = 1u
    ]]
    defer() <| ${ delete create_info; }
    return <- device |> create_framebuffer(create_info)

