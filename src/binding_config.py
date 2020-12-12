from das_binder.config import ConfigBase
from boost_generator import BoostGenerator


class Config(ConfigBase):

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def save_ast(self):
        return True

    @property
    def c_headers_to_extract_macro_consts_from(self):
        return ['GLFW/glfw3.h', 'vulkan/vulkan_core.h']

    def custom_pass(self, context):
        generator = BoostGenerator(context)
        add_boost_content(generator)
        generator.write()

    def configure_macro_const(self, macro_const):
        if '"' in macro_const.value:
            macro_const.ignore()
            return
        for prefix in [
            'GLFW_',
            'VK_',
        ]:
            if macro_const.name.startswith(prefix):
                return
        macro_const.ignore()

    def configure_opaque_struct(self, struct):
        if struct.name.endswith('_T'):
            struct.set_das_type(struct.name[:-2])
        if struct.name.startswith('GLFW'):
            ptr_type = struct.name + '_DasHandle'
            struct.set_das_type(ptr_type)
            struct.define_ptr_type(ptr_type)

    def configure_struct_field(self, field):
        # These structs have function pointers, but we can probably
        # live without them for a time being.
        if field.name.startswith('pfn') and field.struct.name in [
            'VkAllocationCallbacks',
            'VkDebugReportCallbackCreateInfoEXT',
            'VkDebugUtilsMessengerCreateInfoEXT',
        ]:
            field.ignore()

    def configure_function(self, func):
        # whitelist
        if func.name in [
            'vkAcquireNextImageKHR',
            'vkCreateSwapchainKHR',
            'vkDestroySurfaceKHR',
            'vkDestroySwapchainKHR',
            'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
            'vkGetPhysicalDeviceSurfaceFormatsKHR',
            'vkGetPhysicalDeviceSurfacePresentModesKHR',
            'vkGetPhysicalDeviceSurfaceSupportKHR',
            'vkGetSwapchainImagesKHR',
            'vkQueuePresentKHR',
        ]:
            return

        #TODO: make these work
        if ('size_t' in func.type
        or  'PFN_' in func.type
        or  func.name.endswith('KHR')
        or  func.name.endswith('EXT')
        or  func.name.endswith('INTEL')
        or  func.name.endswith('AMD')
        or  func.name.endswith('GOOGLE')
        or  func.name.endswith('NV')
        or  func.name.endswith('NVX')
        ):
            func.ignore()

        if func.name.startswith('glfw'):
            for kw in [
                'ProcAddress',
                'Callback',
            ]:
                if kw in func.name:
                    func.ignore()


def add_boost_content(g):

    #
    # Handles
    #

    for name in [
        'VkDevice',
        'VkCommandPool',
        'VkDescriptorSetLayout',
        'VkFence',
        'VkFramebuffer',
        'VkImage',
        'VkImageView',
        'VkInstance',
        'VkPhysicalDevice',
        'VkQueue',
        'VkPipelineCache',
        'VkPipelineLayout',
        'VkRenderPass',
        'VkSampler',
        'VkSemaphore',
        'VkShaderModule',
        'VkSwapchainKHR',
    ]:
        g.add_gen_handle(name = name)

    h = g.add_gen_handle(name = 'VkPipeline')
    h.declare_ctor(name = 'vkCreateGraphicsPipelines'
        ).declare_array(count = 'createInfoCount', items = 'pCreateInfos'
        ).declare_array(count = 'createInfoCount', items = 'pPipelines')
    h.declare_ctor(name = 'vkCreateComputePipelines',
        ).declare_array(count = 'createInfoCount', items = 'pCreateInfos'
        ).declare_array(count = 'createInfoCount', items = 'pPipelines')

    #
    # Structs
    #

    for name in [
        'VkApplicationInfo',
        'VkAttachmentDescription',
        'VkAttachmentReference',
        'VkComponentMapping',
        'VkExtent2D',
        'VkExtent3D',
        'VkImageSubresourceRange',
        'VkOffset2D',
        'VkPhysicalDeviceLimits',
        'VkPhysicalDeviceFeatures',
        'VkPhysicalDeviceSparseProperties',
        'VkPushConstantRange',
        'VkQueueFamilyProperties',
        'VkRect2D',
        'VkSubpassDependency',
        'VkSurfaceCapabilitiesKHR',
        'VkSurfaceFormatKHR',
        'VkViewport',
    ]:
        g.add_gen_struct(name = name)

    for name in [
        'VkExtensionProperties',
        'VkPhysicalDeviceProperties',
    ]:
        g.add_gen_struct(name=name, boost_to_vk=False)

    for name in [
        'VkCommandPoolCreateInfo',
        'VkFenceCreateInfo',
        'VkImageViewCreateInfo',
        'VkPipelineColorBlendAttachmentState',
        'VkPipelineDepthStencilStateCreateInfo',
        'VkPipelineInputAssemblyStateCreateInfo',
        'VkPipelineMultisampleStateCreateInfo',
        'VkPipelineRasterizationStateCreateInfo',
        'VkPipelineShaderStageCreateInfo',
        'VkPipelineTessellationStateCreateInfo',
        'VkSamplerCreateInfo',
        'VkSemaphoreCreateInfo',
        'VkSpecializationMapEntry',
        'VkStencilOpState',
        'VkVertexInputAttributeDescription',
        'VkVertexInputBindingDescription',
    ]:
        g.add_gen_struct(name=name, vk_to_boost=False)

    g.add_gen_struct(name='VkComputePipelineCreateInfo', vk_to_boost=False,
        ).ignore_field('stage')
    g.add_gen_struct(name = 'VkDescriptorSetLayoutBinding', vk_to_boost=False,
        ).declare_array(items = 'pImmutableSamplers')
    g.add_gen_struct(name = 'VkDescriptorSetLayoutCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'bindingCount', items = 'pBindings')
    g.add_gen_struct(name = 'VkDeviceCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'queueCreateInfoCount', items = 'pQueueCreateInfos',
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(name = 'VkDeviceQueueCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'queueCount', items = 'pQueuePriorities')
    g.add_gen_struct(name = 'VkFramebufferCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'attachmentCount', items = 'pAttachments')
    g.add_gen_struct(name = 'VkGraphicsPipelineCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'stageCount', items = 'pStages')
    g.add_gen_struct(name = 'VkImageCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(name = 'VkInstanceCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(name = 'VkPipelineCacheCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'initialDataSize', items = 'pInitialData', force_item_type = 'uint8')
    g.add_gen_struct(name = 'VkPipelineColorBlendStateCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'attachmentCount', items = 'pAttachments')
    g.add_gen_struct(name = 'VkPipelineDynamicStateCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'dynamicStateCount', items = 'pDynamicStates')
    g.add_gen_struct(name = 'VkPipelineLayoutCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'setLayoutCount', items = 'pSetLayouts',
        ).declare_array(count = 'pushConstantRangeCount', items = 'pPushConstantRanges')
    g.add_gen_struct(name = 'VkPipelineVertexInputStateCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'vertexBindingDescriptionCount', items = 'pVertexBindingDescriptions',
        ).declare_array(count = 'vertexAttributeDescriptionCount', items = 'pVertexAttributeDescriptions')
    g.add_gen_struct(name = 'VkPipelineViewportStateCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'viewportCount', items = 'pViewports',
        ).declare_array(count = 'scissorCount', items = 'pScissors')
    g.add_gen_struct(name = 'VkRenderPassCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'attachmentCount', items = 'pAttachments',
        ).declare_array(count = 'subpassCount', items = 'pSubpasses',
        ).declare_array(count = 'dependencyCount', items = 'pDependencies')
    g.add_gen_struct(name = 'VkShaderModuleCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'codeSize', items = 'pCode', force_item_type = 'uint8')
    g.add_gen_struct(name = 'VkSpecializationInfo', vk_to_boost=False,
        ).declare_array(count = 'mapEntryCount', items = 'pMapEntries',
        ).declare_array(count = 'dataSize', items = 'pData', force_item_type = 'uint8')
    g.add_gen_struct(name = 'VkSubpassDescription', vk_to_boost=False,
        ).declare_array(count = 'inputAttachmentCount', items = 'pInputAttachments',
        ).declare_array(count = 'colorAttachmentCount', items = 'pColorAttachments',
        ).declare_array(count = 'colorAttachmentCount', items = 'pResolveAttachments', optional=True,
        ).declare_array(count = 'preserveAttachmentCount', items = 'pPreserveAttachments')
    g.add_gen_struct(name = 'VkSwapchainCreateInfoKHR', vk_to_boost=False,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')

    #
    # Functions
    #

    g.add_gen_func(name = 'vkEnumerateDeviceExtensionProperties',
        ).declare_array(count = 'pPropertyCount', items = 'pProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(name = 'vkEnumeratePhysicalDevices',
        ).declare_array(count = 'pPhysicalDeviceCount', items = 'pPhysicalDevices',
        ).declare_output(name = 'pPhysicalDevices')
    g.add_gen_func(name = 'vkGetDeviceQueue'
        ).declare_output(name = 'pQueue')
    g.add_gen_func(name = 'vkGetPhysicalDeviceProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
        ).declare_output(name = 'pSurfaceCapabilities')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfaceSupportKHR',
        ).declare_output(name = 'pSupported')
    g.add_gen_func(name = 'vkGetPhysicalDeviceQueueFamilyProperties',
        ).declare_array(count = 'pQueueFamilyPropertyCount', items = 'pQueueFamilyProperties',
        ).declare_output(name = 'pQueueFamilyProperties')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfaceFormatsKHR',
        ).declare_array(count = 'pSurfaceFormatCount', items = 'pSurfaceFormats',
        ).declare_output(name = 'pSurfaceFormats')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfacePresentModesKHR',
        ).declare_array(count = 'pPresentModeCount', items = 'pPresentModes',
        ).declare_output(name = 'pPresentModes')
    g.add_gen_func(name = 'vkGetSwapchainImagesKHR',
        ).declare_array(count = 'pSwapchainImageCount', items = 'pSwapchainImages',
        ).declare_output(name = 'pSwapchainImages')
