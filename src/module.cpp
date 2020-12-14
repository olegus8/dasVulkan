#include "daScript/daScript.h"

#include "headers_to_bind.h"

using namespace das;

template <typename OT>
struct VkHandleAnnotation : public ManagedValueAnnotation<OT> {
    VkHandleAnnotation(const string & n, const string & cpn = string())
    : ManagedValueAnnotation<OT>(n,cpn) {
    }
    virtual bool canClone() const {
        return true;
    }
    virtual SimNode * simulateClone ( Context & context, const LineInfo & at, SimNode * l, SimNode * r ) const override {
        return simulateCopy(context, at, l, r);
    }
};

#include "module_generated.inc"
