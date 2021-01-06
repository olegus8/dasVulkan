options indenting = 4
options no_aot = true

require daslib/defer
require generated
require vulkan


struct TimestampQueryPool
    query_count : uint
    _query_pool : QueryPool
    _device : Device


def create_timestamp_query_pool(device : Device; query_count : uint
) : TimestampQueryPool
    return <- [[ TimestampQueryPool
        query_count = query_count,
        _device <- weak_copy(device),
        _query_pool <- device |> create_query_pool([[QueryPoolCreateInfo
            query_type = VkQueryType VK_QUERY_TYPE_TIMESTAMP,
            query_count = query_count
        ]])
    ]]

def reset(var query_pool : TimestampQueryPool)
    query_pool._device |> reset_query_pool(
        query_pool._query_pool, 0u, query_pool.query_count)
