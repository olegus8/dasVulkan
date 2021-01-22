#include "module.h"

typedef DebugMsgContext * DebugMsgContext_DasHandle;
MAKE_TYPE_FACTORY(DebugMsgContext_DasHandle, DebugMsgContext_DasHandle)

typedef DebugMsgContext * (pfn_create_debug_msg_context)(Lambda callback, Context * ctx);

pfn_create_debug_msg_context g_p_create_debug_msg_context{};

DebugMsgContext * create_debug_msg_context(Lambda callback, Context * ctx) {
    auto debug_ctx = new DebugMsgContext();
    debug_ctx->ctx = ctx;
    debug_ctx->thread_id = this_thread::get_id();
    int32_t * fn_index = (int32_t *) callback.capture;
    if ( ! fn_index ) {
        delete debug_ctx;
        ctx->throw_error("null callback lambda");
        return nullptr;
    }
    debug_ctx->cb_func = ctx->getFunction(*fn_index-1);
    if ( ! debug_ctx->cb_func ) {
        delete debug_ctx;
        ctx->throw_error("callback function not found");
        return nullptr;
    }
    debug_ctx->cb_lambda = callback;
    return debug_ctx;
}

void destroy_debug_msg_context(DebugMsgContext * debug_ctx, Context * ctx) {
    if ( debug_ctx == nullptr ) {
        ctx->throw_error("debug_ctx must not be null");
    }
    if ( debug_ctx->ctx != ctx ) {
        ctx->throw_error("must call from same context as was created");
    }
    delete debug_ctx;
}

void addVulkanCustomBeforeGenerated(Module & module, ModuleLibrary & lib) {

    g_p_create_debug_msg_context = &create_debug_msg_context;

    module.addAnnotation(make_smart<VkHandleAnnotation<
        DebugMsgContext_DasHandle> >(
            "DebugMsgContext_DasHandle",
            "DebugMsgContext_DasHandle"
    ));
    addExtern<DAS_BIND_FUN((*g_p_create_debug_msg_context))>(
        module, lib, "create_debug_msg_context",
        SideEffects::worstDefault, "create_debug_msg_context");
    addExtern<DAS_BIND_FUN(destroy_debug_msg_context)>(
        module, lib, "destroy_debug_msg_context",
        SideEffects::worstDefault, "destroy_debug_msg_context");
}

void addVulkanCustomAfterGenerated(Module &, ModuleLibrary &) {
}
