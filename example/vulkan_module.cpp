#include "daScript/daScript.h"

#include "vulkan/vulkan.h"

struct VulkanHandleAnnotation : DummyTypeAnnotation {
    virtual bool isRefType() const override { return false; }
    virtual bool isLocal() const override { return true; }
    virtual bool canCopy() const override { return true; }
    virtual bool canMove() const override { return true; }
    virtual bool canClone() const override { return true; }
};

#include "vulkan_module_generated.inc"
