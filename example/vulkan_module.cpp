#include "daScript/daScript.h"

#include "vulkan/vulkan.h"

using namespace das;

template <typename VK_TYPE>
struct VulkanHandleAnnotation : ManagedValueAnnotation<VK_TYPE> {
    VulkanHandleAnnotation(const string & name, const string & cppName)
        : ManagedValueAnnotation<VK_TYPE>(name, cppName) {
    }
    virtual bool canNew() const override { return true; }
    virtual bool canDelete() const override { return true; }
    virtual SimNode * simulateGetNew ( Context & context, const LineInfo & at ) const override {
        return context.code->makeNode<SimNode_NewHandle<VK_TYPE,false>>(at);
    }
    virtual SimNode * simulateDeletePtr ( Context & context, const LineInfo & at, SimNode * sube, uint32_t count ) const override {
        return context.code->makeNode<SimNode_DeleteHandlePtr<VK_TYPE,false>>(at,sube,count);
    }
};

#include "vulkan_module_generated.inc"
