#include "daScript/daScript.h"

#include "vulkan/vulkan.h"

using namespace das;

struct VulkanHandleAnnotation : DummyTypeAnnotation {
    VulkanHandleAnnotation(const string & name, const string & cppName, size_t sz, size_t al)
        : DummyTypeAnnotation(name, cppName, sz, al) {
    }
    virtual bool isRefType() const override { return false; }
    virtual bool isLocal() const override { return true; }
    virtual bool canCopy() const override { return true; }
    virtual bool canMove() const override { return true; }
    virtual bool canClone() const override { return true; }
};

#include "vulkan_module_generated.inc"
