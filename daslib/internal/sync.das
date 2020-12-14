options indenting = 4
options no_aot = true

require daslib/defer
require generated


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
    wait_for_fence([
        device=device, fences=fences, timeout=timeout, result=result])
