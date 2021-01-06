options indenting = 4
options no_aot = true

require daslib/defer
require generated
require vulkan


def create_and_reset_query_pool(
    device : Device;
    var create_info : QueryPoolCreateInfo = [[ QueryPoolCreateInfo ]]
) : QueryPool
    var pool <- device |> create_query_pool <| create_info
    device |> reset_query_pool(pool, 0u, create_info.query_count)
    return <- pool


def create_timestamp_query_pool(device : Device; count: int) : QueryPool
    return <- device |> create_and_reset_query_pool([[QueryPoolCreateInfo
        query_type = VkQueryType VK_QUERY_TYPE_TIMESTAMP,
        query_count = uint(count)
    ]])
