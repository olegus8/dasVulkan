options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr

require vulkan
require window
require math
require strings

//
// Helpers
//

typedef
    VkDeviceAddress = uint64

def with_view(
    var boost_struct : auto(BOOST_T);
    b : block<(vk_struct : auto(VK_T))>
)
    var vk_struct : VK_T
    unsafe
        vk_struct <- boost_struct |> vk_view_create_unsafe()
    b |> invoke(vk_struct)
    boost_struct |> vk_view_destroy()

def boost_value_to_vk(b : auto(T)[]) : T[]
    return b

def boost_value_to_vk(b : auto(T)) : T
    return b

//FIXME: temporary hack. need to adjust generator accordingly
def boost_value_to_vk(b : VkClearColorValue) : VkClearColorValue
    var clone := b
    return clone

def vk_value_to_boost(v : auto(T)[]) : T[]
    return v

def vk_value_to_boost(v : auto(T)) : T
    return v

def vk_value_to_boost(v : int8[]) : string
    unsafe
        return <- clone_string(reinterpret<string>(addr(v[0])))

def vk_value_to_boost(v : string) : string
    unsafe
        return <- clone_string(v)

def copy_to_array(src : string; var dst : int8[] &)
    for s, d in src, dst
        unsafe
            d = reinterpret<int8>(uint8(s))

def array_addr_unsafe(var ar : array<auto(T)>) : T?
    unsafe
        return length(ar) > 0 ? addr(ar[0]) : [[T ?]]

//TODO: refactor into clone() and disable can_copy on boost handles.
//  after that transfer ownership with move, and create weak copies via clone.
//  OR disable can_copy and can_clone, and only allow move and weak_copy.
def weak_copy(b : auto(T)) : T -const
    static_if typeinfo(has_field<_needs_delete> b)
        var bc : T = b
        bc._needs_delete = false
        return <- bc
    else
        concept_assert(0, "can't weak copy this type")

def weak_copy_first(dsets : DescriptorSets) : DescriptorSet
    return <- weak_copy(dsets.descriptor_sets[0])

//
// Surface
//

struct SurfaceKHR
    surface_khr : VkSurfaceKHR
    _instance : VkInstance
    _needs_delete : bool

def boost_value_to_vk(b : SurfaceKHR) : VkSurfaceKHR
    return b.surface_khr

def create_window_surface(
    instance : Instance = [[ Instance ]];
    window : Window = [[ Window ]];
    var result : VkResult? = [[VkResult?]]
) : SurfaceKHR

    var surface <- [[SurfaceKHR
        _instance = instance.instance,
        _needs_delete = true]]
    var result_ = VkResult VK_SUCCESS
    result ?? result_ = glfwCreateWindowSurface(
        instance.instance,
        window.window,
        null,
        safe_addr(surface.surface_khr)
    )
    assert(result_ == VkResult VK_SUCCESS)
    return <- surface

def finalize(var surface : SurfaceKHR explicit)
    if surface._needs_delete
        vkDestroySurfaceKHR(
            surface._instance,
            surface.surface_khr,
            null
        )
    memzero(surface)

//
// CommandBuffers
//

struct CommandBuffers
    command_buffers : array<CommandBuffer>
    _device : Device
    _command_pool : CommandPool
    _needs_delete : bool

def allocate_command_buffers(
    device : Device;
    var allocate_info : CommandBufferAllocateInfo;
    var result : VkResult? = [[VkResult?]]
) : CommandBuffers
    var buffers <- [[ CommandBuffers
        _needs_delete = true,
        _device = weak_copy(device),
        _command_pool = weak_copy(allocate_info.command_pool)
    ]]
    buffers.command_buffers <- allocate_command_buffers__inner([
        device = device, allocate_info = allocate_info, result = result])
    return <- buffers

def finalize(var bufs : CommandBuffers explicit)
    if bufs._needs_delete
        bufs._device |> free_command_buffers(bufs._command_pool,
            bufs.command_buffers)
    delete bufs.command_buffers
    memzero(bufs)

//
// DescriptorSets
//

struct DescriptorSets
    descriptor_sets : array<DescriptorSet>
    _device : Device
    _descriptor_pool : DescriptorPool
    _needs_delete : bool

def allocate_descriptor_sets(
    device : Device;
    var allocate_info : DescriptorSetAllocateInfo;
    var result : VkResult? = [[VkResult?]]
) : DescriptorSets
    var sets <- [[ DescriptorSets
        _needs_delete = true,
        _device = weak_copy(device),
        _descriptor_pool = weak_copy(allocate_info.descriptor_pool)
    ]]
    sets.descriptor_sets <- allocate_descriptor_sets__inner([
        device = device, allocate_info = allocate_info, result = result])
    return <- sets

def finalize(var sets : DescriptorSets explicit)
    if sets._needs_delete
        sets._device |> free_descriptor_sets(sets._descriptor_pool,
            sets.descriptor_sets)
    delete sets.descriptor_sets
    memzero(sets)
