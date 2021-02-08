options indenting = 4
options no_aot = true

require daslib/defer
require generated
require vulkan


def reset_fence(
    device : Device;
    fence : Fence;
    var result : VkResult? = [[VkResult?]]
)
    var fences <- [{ auto[] weak_copy(fence) }]
    defer() <| ${ delete fences; }
    device |> reset_fences(fences, result)


def wait_for_fence(
    device : Device;
    fence : Fence;
    timeout : uint64 = [[ uint64 ]];
    var result : VkResult? = [[VkResult?]]
)
    var fences <- [{ auto[] weak_copy(fence) }]
    defer() <| ${ delete fences; }
    wait_for_fences([
        device=device, fences=fences, timeout=timeout, result=result])


def fence_signalled(device : Device; fence : Fence) : bool
    var result : VkResult
    var p_result : VkResult ?
    unsafe
        p_result = addr(result)
    device |> wait_for_fence(fence, uint64(0), p_result)
    return result == VkResult VK_SUCCESS
