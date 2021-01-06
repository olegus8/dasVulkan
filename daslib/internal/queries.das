options indenting = 4
options no_aot = true

require daslib/defer
require generated
require vulkan


struct TimestampQueryPool
    timestamps : array<uint64>
    _query_pool : QueryPool
    _device : Device


def create_timestamp_query_pool(device : Device; query_count : int
) : TimestampQueryPool
    var pool <- [[ TimestampQueryPool
        _device <- weak_copy(device),
        _query_pool <- device |> create_query_pool([[QueryPoolCreateInfo
            query_type = VkQueryType VK_QUERY_TYPE_TIMESTAMP,
            query_count = uint(query_count)
        ]])
    ]]
    pool.timestamps |> resize <| query_count
    return <- pool

def reset(var pool : TimestampQueryPool)
    pool._device |> reset_query_pool(
        pool._query_pool, 0u, uint(pool.timestamps |> length()))
    let query_count = pool.timestamps |> length()
    pool.timestamps |> clear
    pool.timestamps |> resize <| query_count
