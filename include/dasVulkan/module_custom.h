#pragma once

#include "daScript/daScript.h"
#include "headers_to_bind.h"
#include <thread>

template <typename OT>
struct VkHandleAnnotation : public das::ManagedValueAnnotation<OT> {
    VkHandleAnnotation(const std::string & n, const std::string & cpn = std::string())
    : das::ManagedValueAnnotation<OT>(n,cpn) {
    }
    virtual bool canClone() const override {
        return true;
    }
    virtual das::SimNode * simulateClone ( das::Context & context, const das::LineInfo & at, das::SimNode * l, das::SimNode * r ) const override {
        return das::ManagedValueAnnotation<OT>::simulateCopy(context, at, l, r);
    }
};

struct DebugMsgContext {
    das::Context *     ctx = nullptr;
    das::SimFunction * cb_func = nullptr;
    das::Lambda        cb_lambda;
    std::thread::id    thread_id;
};

typedef DebugMsgContext * DebugMsgContext_DasHandle;
MAKE_EXTERNAL_TYPE_FACTORY(DebugMsgContext_DasHandle, DebugMsgContext_DasHandle)

MAKE_EXTERNAL_TYPE_FACTORY(PFN_vkDebugUtilsMessengerCallbackEXT, PFN_vkDebugUtilsMessengerCallbackEXT);

#include "module_generated.h.inc"
