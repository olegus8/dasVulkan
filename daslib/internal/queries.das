options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct TimestampQueryPool
    timestamps : array<uint64>  // nanoseconds
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


def update(var pool : TimestampQueryPool)
    var data : array<uint64>
    defer() <| { delete data; }
    data |> resize <| length(pool.timestamps)

    var pdata : void ?
    unsafe
        pdata = addr(data[0])

    assert(intptr(pdata) % uint64(8) == uint64(0))

    verify(VkResult VK_SUCCESS == vkGetQueryPoolResults(
        pool._device.device,
        pool._query_pool.query_pool,
        0u,
        uint(pool.timestamps |> length()),
        uint64(typeinfo(sizeof type<uint64>)*length(data)),
        pdata,
        uint64(typeinfo(sizeof type<uint64>)),
        uint(VkQueryResultFlagBits VK_QUERY_RESULT_64_BIT)
    ))

    //TODO: fill available timestamp data, convert to nanoseconds
