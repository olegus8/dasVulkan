#include "daScript/daScript.h"

using namespace das;

struct SmartObject : public das::ptr_ref_count {
};

MAKE_TYPE_FACTORY(SmartObject, SmartObject)

struct SmartObjectAnnotation : ManagedStructureAnnotation <SmartObject> {
    SmartObjectAnnotation(ModuleLibrary & ml) : ManagedStructureAnnotation ("SmartObject", ml) {
    }
    virtual bool isLocal() const override { return false; }
    virtual bool canMove() const override { return false; }
    virtual bool canCopy() const override { return false; }
};

class Module_app : public Module {
public:
    Module_app() : Module("app") {
        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();
        addAnnotation(make_smart<SmartObjectAnnotation>(lib));
    }
};

REGISTER_MODULE(Module_app);
