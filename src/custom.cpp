#include "daScript/daScript.h"

using namespace das;

int get_num(Context * context) {return 123;}

void addVulkanCustom(Module & module, ModuleLibrary & lib) {
    addExtern<DAS_BIND_FUN(get_num)>(module, lib, "get_num",
        SideEffects::worstDefault, "get_num");
}
