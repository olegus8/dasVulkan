#include "daScript/daScript.h"

#include "headers_to_bind.h"

using namespace das;

template <typename OT>
struct VkHandleAnnotation : public ManagedValueAnnotation<OT> {
    VkHandleAnnotation(const string & n, const string & cpn = string())
    : ManagedValueAnnotation<OT>(n,cpn) {
    }
    virtual bool canClone() const override {
        return true;
    }
    virtual SimNode * simulateClone ( Context & context, const LineInfo & at, SimNode * l, SimNode * r ) const override {
        return ManagedValueAnnotation<OT>::simulateCopy(context, at, l, r);
    }
};

#include "module_generated.inc"

class Module_vulkan : public GeneratedModule_vulkan {
public:
    Module_vulkan() : GeneratedModule_vulkan() {
        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();
        add_generated(lib);
    }
};

REGISTER_MODULE(Module_vulkan);
