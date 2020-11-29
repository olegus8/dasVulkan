options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Instance
    instance : VkInstance


def finalize(var instance : Instance)
    vkDestroyInstance(instance.instance, null)
    memzero(instance)
