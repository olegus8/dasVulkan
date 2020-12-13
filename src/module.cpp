#include "daScript/daScript.h"

#include "headers_to_bind.h"

using namespace das;

template <typename OT>
struct VkManagedValueAnnotation : ManagedValueAnnotation<OT> {
};

#include "module_generated.inc"
