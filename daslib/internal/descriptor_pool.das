options indenting = 4
options no_aot = true

require daslib/defer
require vulkan
require generated
require device


def create_simple_descriptor_pool(
    device : Device;
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
