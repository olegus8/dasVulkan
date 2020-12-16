#include "daScript/daScript.h"

using namespace das;

void my_cpp_func(Context * context) {
    auto fx = ctx->findFunction("my_das_func");
    if (!fx) {
        ctx->throw_error("function not found");
        return;
    }
    ctx->eval(fx, nullptr);
}

void addVulkanCustom(Module & module, ModuleLibrary & lib) {
    addExtern<DAS_BIND_FUN(my_cpp_func)>(module, lib, "my_cpp_func",
        SideEffects::worstDefault, "my_cpp_func");
}
