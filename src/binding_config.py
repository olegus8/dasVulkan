from das_binder.config import ConfigBase
from boost_generator import BoostGenerator


class Config(ConfigBase):

    def __init__(self, **kwargs):
        super(Config, self).__init__()
        self.__title = None

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def save_ast(self):
        return True

    @property
    def c_headers_to_extract_macro_consts_from(self):
        return ['vulkan/vulkan_core.h']

    @property
    def title(self):
        return self.__title

    def custom_pass(self, context):
        generator = BoostGenerator(context)
        add_boost_content(generator)
        generator.write()
        self.__title = generator.title

    def configure_macro_const(self, macro_const):
        if '"' in macro_const.value:
            macro_const.ignore()
            return
        for prefix in [
            'VK_',
        ]:
            if macro_const.name.startswith(prefix):
                return
        macro_const.ignore()

    def configure_opaque_struct(self, struct):
        struct.set_annotation_type('VkHandleAnnotation')
        if struct.name.endswith('_T'):
            struct.set_das_type(struct.name[:-2])

    def configure_struct_field(self, field):
        # whitelist
        if (field.struct.name == 'VkDebugUtilsMessengerCreateInfoEXT'
        and field.name == 'pfnUserCallback'
        ):
          return

        # These structs have function pointers, but we can probably
        # live without them for a time being.
        if field.name.startswith('pfn'):
            field.ignore()

    def configure_function(self, func):
        # whitelist
        if func.name in [
            'vkAcquireNextImageKHR',
            'vkCreateDebugUtilsMessengerEXT',
            'vkCreateSwapchainKHR',
            'vkDestroyDebugUtilsMessengerEXT',
            'vkDestroySurfaceKHR',
            'vkDestroySwapchainKHR',
            'vkGetAccelerationStructureBuildSizesKHR',
            'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
            'vkGetPhysicalDeviceSurfaceFormatsKHR',
            'vkGetPhysicalDeviceSurfacePresentModesKHR',
            'vkGetPhysicalDeviceSurfaceSupportKHR',
            'vkGetSwapchainImagesKHR',
            'vkQueuePresentKHR',
            'vkSetDebugUtilsObjectNameEXT',
        ]:
            return

        #TODO: make these work
        if ('PFN_' in func.type
        or  func.name.endswith('KHR')
        or  func.name.endswith('EXT')
        or  func.name.endswith('INTEL')
        or  func.name.endswith('AMD')
        or  func.name.endswith('GOOGLE')
        or  func.name.endswith('NV')
        or  func.name.endswith('NVX')
        ):
            func.ignore()


def add_boost_content(g):

    #
    # Handles
    #

    for name in [
        'VkAccelerationStructureKHR',
        'VkBuffer',
        'VkBufferView',
        'VkCommandBuffer',
        'VkCommandPool',
        'VkDebugUtilsMessengerEXT',
        'VkDescriptorPool',
        'VkDescriptorSet',
        'VkDescriptorSetLayout',
        'VkDevice',
        'VkFence',
        'VkFramebuffer',
        'VkImage',
        'VkImageView',
        'VkInstance',
        'VkPhysicalDevice',
        'VkPipelineCache',
        'VkPipelineLayout',
        'VkQueryPool',
        'VkQueue',
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

    h = g.add_gen_handle(name = 'VkDeviceMemory')
    h.declare_ctor(name = 'vkAllocateMemory')
    h.declare_dtor(name = 'vkFreeMemory')

    #
    # Structs
    #

    for name in [
        'VkAccelerationStructureBuildSizesInfoKHR',
        'VkApplicationInfo',
        'VkAttachmentDescription',
        'VkAttachmentReference',
        'VkComponentMapping',
        'VkDebugUtilsLabelEXT',
        'VkDebugUtilsObjectNameInfoEXT',
        'VkDispatchIndirectCommand',
        'VkDrawIndexedIndirectCommand',
        'VkExtensionProperties',
        'VkExtent2D',
        'VkExtent3D',
        'VkFormatProperties',
        'VkImageSubresourceRange',
        'VkLayerProperties',
        'VkMappedMemoryRange',
        'VkMemoryHeap',
        'VkMemoryRequirements',
        'VkMemoryType',
        'VkOffset2D',
        'VkOffset3D',
        'VkPhysicalDeviceFeatures',
        'VkPhysicalDeviceLimits',
        'VkPhysicalDeviceProperties',
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
        'VkAccelerationStructureCreateInfoKHR',
        'VkAccelerationStructureGeometryAabbsDataKHR',
        'VkAccelerationStructureGeometryInstancesDataKHR',
        'VkAccelerationStructureGeometryKHR',
        'VkAccelerationStructureGeometryTrianglesDataKHR',
        'VkBufferCopy',
        'VkBufferImageCopy',
        'VkBufferMemoryBarrier',
        'VkBufferViewCreateInfo',
        'VkClearDepthStencilValue',
        'VkCommandBufferAllocateInfo',
        'VkCommandBufferBeginInfo',
        'VkCommandBufferInheritanceInfo',
        'VkCommandPoolCreateInfo',
        'VkComputePipelineCreateInfo',
        'VkCopyDescriptorSet',
        'VkDescriptorBufferInfo',
        'VkDescriptorImageInfo',
        'VkDescriptorPoolSize',
        'VkDeviceOrHostAddressConstKHR',
        'VkFenceCreateInfo',
        'VkImageMemoryBarrier',
        'VkImageSubresourceLayers',
        'VkImageViewCreateInfo',
        'VkMemoryAllocateInfo',
        'VkMemoryBarrier',
        'VkPipelineColorBlendAttachmentState',
        'VkPipelineDepthStencilStateCreateInfo',
        'VkPipelineInputAssemblyStateCreateInfo',
        'VkPipelineMultisampleStateCreateInfo',
        'VkPipelineRasterizationStateCreateInfo',
        'VkPipelineShaderStageCreateInfo',
        'VkPipelineTessellationStateCreateInfo',
        'VkQueryPoolCreateInfo',
        'VkSamplerCreateInfo',
        'VkSemaphoreCreateInfo',
        'VkSpecializationMapEntry',
        'VkStencilOpState',
        'VkVertexInputAttributeDescription',
        'VkVertexInputBindingDescription',
    ]:
        g.add_gen_struct(name=name, vk_to_boost=False)

    debug_validation_features = g.add_gen_struct(
            name='VkValidationFeaturesEXT', vk_to_boost=False
        ).declare_array(count='enabledValidationFeatureCount', items = 'pEnabledValidationFeatures'
        ).declare_array(count='disabledValidationFeatureCount', items = 'pDisabledValidationFeatures')

    debug_msg_create_info = g.add_gen_struct(
        name='VkDebugUtilsMessengerCreateInfoEXT', vk_to_boost=False,
        next_in_chain = debug_validation_features)

    g.add_gen_struct(name = 'VkAccelerationStructureBuildGeometryInfoKHR', vk_to_boost=False,
        ).ignore_field(name = 'ppGeometries')
    g.add_gen_struct(name = 'VkBufferCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(name = 'VkDebugUtilsMessengerCallbackDataEXT',
        ).declare_array(count = 'queueLabelCount', items = 'pQueueLabels'
        ).declare_array(count = 'cmdBufLabelCount', items = 'pCmdBufLabels'
        ).declare_array(count = 'objectCount', items = 'pObjects')
    g.add_gen_struct(name = 'VkDescriptorPoolCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'poolSizeCount', items = 'pPoolSizes')
    g.add_gen_struct(name = 'VkDescriptorSetAllocateInfo', vk_to_boost=False,
        ).declare_array(count = 'descriptorSetCount', items = 'pSetLayouts')
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
        ).declare_array(count = 'stageCount', items = 'pStages',
        ).declare_mandatory_ptr(name = 'pVertexInputState'
        ).declare_mandatory_ptr(name = 'pInputAssemblyState'
        ).declare_mandatory_ptr(name = 'pTessellationState'
        ).declare_mandatory_ptr(name = 'pViewportState'
        ).declare_mandatory_ptr(name = 'pRasterizationState'
        ).declare_mandatory_ptr(name = 'pMultisampleState'
        ).declare_mandatory_ptr(name = 'pDepthStencilState'
        ).declare_mandatory_ptr(name = 'pColorBlendState')
    g.add_gen_struct(name = 'VkImageCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(name = 'VkInstanceCreateInfo', vk_to_boost=False,
        next_in_chain = debug_msg_create_info
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(name = 'VkPhysicalDeviceMemoryProperties',
        ).declare_array(count = 'memoryTypeCount', items = 'memoryTypes',
        ).declare_array(count = 'memoryHeapCount', items = 'memoryHeaps')
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
    g.add_gen_struct(name = 'VkPresentInfoKHR', vk_to_boost=False,
        ).declare_array(count = 'waitSemaphoreCount', items = 'pWaitSemaphores',
        ).declare_array(count = 'swapchainCount', items = 'pSwapchains',
        ).declare_array(count = 'swapchainCount', items = 'pImageIndices',
        ).declare_array(count = 'swapchainCount', items = 'pResults', optional=True)
    g.add_gen_struct(name = 'VkRenderPassCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'attachmentCount', items = 'pAttachments',
        ).declare_array(count = 'subpassCount', items = 'pSubpasses',
        ).declare_array(count = 'dependencyCount', items = 'pDependencies')
    g.add_gen_struct(name = 'VkShaderModuleCreateInfo', vk_to_boost=False,
        ).declare_array(count = 'codeSize', items = 'pCode', force_item_type = 'uint8')
    g.add_gen_struct(name = 'VkSpecializationInfo', vk_to_boost=False,
        ).declare_array(count = 'mapEntryCount', items = 'pMapEntries',
        ).declare_array(count = 'dataSize', items = 'pData', force_item_type = 'uint8')
    g.add_gen_struct(name = 'VkSubmitInfo', vk_to_boost=False,
        ).declare_array(count = 'waitSemaphoreCount', items = 'pWaitSemaphores',
        ).declare_array(count = 'waitSemaphoreCount', items = 'pWaitDstStageMask',
        ).declare_array(count = 'commandBufferCount', items = 'pCommandBuffers',
        ).declare_array(count = 'signalSemaphoreCount', items = 'pSignalSemaphores')
    g.add_gen_struct(name = 'VkSubpassDescription', vk_to_boost=False,
        ).declare_array(count = 'inputAttachmentCount', items = 'pInputAttachments',
        ).declare_array(count = 'colorAttachmentCount', items = 'pColorAttachments',
        ).declare_array(count = 'colorAttachmentCount', items = 'pResolveAttachments', optional=True,
        ).declare_array(count = 'preserveAttachmentCount', items = 'pPreserveAttachments')
    g.add_gen_struct(name = 'VkSwapchainCreateInfoKHR', vk_to_boost=False,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(name = 'VkRenderPassBeginInfo', vk_to_boost=False,
        ).declare_array(count = 'clearValueCount', items = 'pClearValues')
    g.add_gen_struct(name = 'VkWriteDescriptorSet', vk_to_boost=False,
        ).declare_array(count = 'descriptorCount', items = 'pImageInfo', optional=True,
        ).declare_array(count = 'descriptorCount', items = 'pBufferInfo', optional=True,
        ).declare_array(count = 'descriptorCount', items = 'pTexelBufferView', optional=True)

    g.add_gen_struct(
        name = 'VkPhysicalDeviceFeatures2',
        next_in_chain = g.add_gen_struct(
            name = 'VkPhysicalDeviceVulkan11Features'))

    #
    # Functions
    #

    g.add_gen_func(name = 'vkAcquireNextImageKHR'
        ).declare_output(name = 'pImageIndex')
    g.add_gen_func(name = 'vkAllocateCommandBuffers', boost_name = 'allocate_command_buffers__inner', private = True,
        ).declare_array(count_expr = 'allocate_info.command_buffer_count', items = 'pCommandBuffers',
        ).declare_output(name = 'pCommandBuffers')
    g.add_gen_func(name = 'vkAllocateDescriptorSets', boost_name = 'allocate_descriptor_sets__inner', private = True,
        ).declare_array(count_expr = 'length(allocate_info.set_layouts)', items = 'pDescriptorSets',
        ).declare_output(name = 'pDescriptorSets')
    g.add_gen_func(name = 'vkBeginCommandBuffer')
    g.add_gen_func(name = 'vkBindBufferMemory')
    g.add_gen_func(name = 'vkBindImageMemory')
    g.add_gen_func(name = 'vkCmdBeginRenderPass')
    g.add_gen_func(name = 'vkCmdBindDescriptorSets',
        ).declare_array(count = 'descriptorSetCount', items = 'pDescriptorSets',
        ).declare_array(count = 'dynamicOffsetCount', items = 'pDynamicOffsets')
    g.add_gen_func(name = 'vkCmdBindIndexBuffer')
    g.add_gen_func(name = 'vkCmdBindPipeline')
    g.add_gen_func(name = 'vkCmdBindVertexBuffers',
        ).declare_array(count = 'bindingCount', items = 'pBuffers',
        ).declare_array(count = 'bindingCount', items = 'pOffsets')
    g.add_gen_func(name = 'vkCmdCopyBuffer',
        ).declare_array(count = 'regionCount', items = 'pRegions')
    g.add_gen_func(name = 'vkCmdCopyBufferToImage',
        ).declare_array(count = 'regionCount', items = 'pRegions')
    g.add_gen_func(name = 'vkCmdDispatch')
    g.add_gen_func(name = 'vkCmdDispatchIndirect')
    g.add_gen_func(name = 'vkCmdDraw')
    g.add_gen_func(name = 'vkCmdDrawIndexed')
    g.add_gen_func(name = 'vkCmdDrawIndexedIndirect')
    g.add_gen_func(name = 'vkCmdEndRenderPass')
    g.add_gen_func(name = 'vkCmdPipelineBarrier',
        ).declare_array(count = 'memoryBarrierCount', items = 'pMemoryBarriers',
        ).declare_array(count = 'bufferMemoryBarrierCount', items = 'pBufferMemoryBarriers',
        ).declare_array(count = 'imageMemoryBarrierCount', items = 'pImageMemoryBarriers')
    g.add_gen_func(name = 'vkCmdResetQueryPool')
    g.add_gen_func(name = 'vkDeviceWaitIdle')
    g.add_gen_func(name = 'vkEndCommandBuffer')
    g.add_gen_func(name = 'vkEnumerateDeviceExtensionProperties',
        ).declare_array(count = 'pPropertyCount', items = 'pProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(name = 'vkEnumerateInstanceLayerProperties',
        ).declare_array(count = 'pPropertyCount', items = 'pProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(name = 'vkEnumeratePhysicalDevices',
        ).declare_array(count = 'pPhysicalDeviceCount', items = 'pPhysicalDevices',
        ).declare_output(name = 'pPhysicalDevices')
    g.add_gen_func(name = 'vkFlushMappedMemoryRanges',
        ).declare_array(count = 'memoryRangeCount', items = 'pMemoryRanges')
    g.add_gen_func(name = 'vkFreeCommandBuffers', private = True,
        ).declare_array(count = 'commandBufferCount', items = 'pCommandBuffers')
    g.add_gen_func(name = 'vkFreeDescriptorSets', private = True,
        ).declare_array(count = 'descriptorSetCount', items = 'pDescriptorSets')
    g.add_gen_func(name = 'vkGetAccelerationStructureBuildSizesKHR'
        ).declare_array(count_expr = 'build_info.geometry_count', items = 'pMaxPrimitiveCounts',
        ).declare_output(name = 'pSizeInfo')
    g.add_gen_func(name = 'vkGetDeviceQueue'
        ).declare_output(name = 'pQueue')
    g.add_gen_func(name = 'vkGetBufferMemoryRequirements'
        ).declare_output(name = 'pMemoryRequirements')
    g.add_gen_func(name = 'vkGetImageMemoryRequirements',
        ).declare_output(name = 'pMemoryRequirements')
    g.add_gen_func(name = 'vkGetPhysicalDeviceFeatures',
        ).declare_output(name = 'pFeatures')
    g.add_gen_func(name = 'vkGetPhysicalDeviceFeatures2',
        ).declare_output(name = 'pFeatures')
    g.add_gen_func(name = 'vkGetPhysicalDeviceFormatProperties',
        ).declare_output(name = 'pFormatProperties')
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
    g.add_gen_func(name = 'vkGetPhysicalDeviceMemoryProperties',
        ).declare_output(name = 'pMemoryProperties')
    g.add_gen_func(name = 'vkGetSwapchainImagesKHR',
        ).declare_array(count = 'pSwapchainImageCount', items = 'pSwapchainImages',
        ).declare_output(name = 'pSwapchainImages')
    g.add_gen_func(name = 'vkMapMemory'
        ).declare_output(name = 'ppData')
    g.add_gen_func(name = 'vkQueuePresentKHR')
    g.add_gen_func(name = 'vkQueueSubmit',
        ).declare_array(count = 'submitCount', items = 'pSubmits')
    g.add_gen_func(name = 'vkQueueWaitIdle')
    g.add_gen_func(name = 'vkResetCommandBuffer')
    g.add_gen_func(name = 'vkResetFences',
        ).declare_array(count = 'fenceCount', items = 'pFences')
    g.add_gen_func(name = 'vkResetQueryPool')
    g.add_gen_func(name = 'vkSetDebugUtilsObjectNameEXT')
    g.add_gen_func(name = 'vkUnmapMemory')
    g.add_gen_func(name = 'vkUpdateDescriptorSets',
        ).declare_array(count = 'descriptorWriteCount', items = 'pDescriptorWrites',
        ).declare_array(count = 'descriptorCopyCount', items = 'pDescriptorCopies')
    g.add_gen_func(name = 'vkWaitForFences',
        ).declare_array(count = 'fenceCount', items = 'pFences')
