options indenting = 4
options no_aot = true

require daslib/defer
require vulkan
require generated
require device


let
    ALL_DESCRIPTOR_TYPES <- [{auto[]
        VkDescriptorType VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        VkDescriptorType VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
        VkDescriptorType VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
        VkDescriptorType VK_DESCRIPTOR_TYPE_SAMPLER;
        VkDescriptorType VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        VkDescriptorType VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC;
        VkDescriptorType VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
        VkDescriptorType VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER;
        VkDescriptorType VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        VkDescriptorType VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
        VkDescriptorType VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER
    }]


def create_simple_descriptor_pool(
    device : Device;
    count : int = 1000;
    desc_types : array<VkDescriptorType> = ALL_DESCRIPTOR_TYPES
) : DescriptorPool
    var info <- [[ DescriptorPoolCreateInfo
        pool_sizes <- [{ for desc_type in desc_types ;
            [[ DescriptorPoolSize type_=desc_type, descriptor_count=count ]]
        }],
        max_sets = uint(count * length(desc_types)),
        flags = uint(VkDescriptorPoolCreateFlagBits
            VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT)
    ]]
    defer() <| { delete info; }
    return <- device |> create_descriptor_pool(info)
