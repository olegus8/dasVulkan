#include "daScript/daScript.h"

#include "headers_to_bind.h"

using namespace das;

template <typename OT>
struct VkHandleAnnotation : ManagedValueAnnotation<OT> {
};

#include "module_generated.inc"
