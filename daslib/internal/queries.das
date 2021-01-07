options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct TimestampQueryPool
    queries : array<TimestampQuery>
    _query_pool : QueryPool
    _device : Device


struct TimestampQuery
    ns : uint64
    available : bool
    _index : uint
    _device : Device
    _query_pool : QueryPool


[private]
struct TimestampQueryResult
    value : uint64
    available : uint64


def create_timestamp_query_pool(device : Device; query_count : int
) : TimestampQueryPool
    var pool <- [[ TimestampQueryPool
        _device <- weak_copy(device),
        _query_pool <- device |> create_query_pool([[QueryPoolCreateInfo
            query_type = VkQueryType VK_QUERY_TYPE_TIMESTAMP,
            query_count = uint(query_count)
        ]])
    ]]
    pool.queries |> reserve <| query_count
    for i in range(query_count)
        pool.queries.emplace([[TimestampQuery
            _index = uint(i),
            _query_pool = weak_copy(pool._query_pool._query_pool),
            _device = weak_copy(device)
        ]])
    return <- pool


def reset(var pool : TimestampQueryPool)
    pool._device |> reset_query_pool(
        pool._query_pool, 0u, uint(pool.queries |> length()))
    for query in pool.queries
        query.ns = uint64(0)
        query.available = false


def update(var pool : TimestampQueryPool)
    var data : array<TimestampQueryResult>
    defer() <| { delete data; }
    data |> resize <| length(pool.queries)

    var pdata : void ?
    unsafe
        pdata = addr(data[0])

    assert(intptr(pdata) % uint64(8) == uint64(0))

    let result = vkGetQueryPoolResults(
        pool._device.device,
        pool._query_pool.query_pool,
        0u,
        uint(pool.timestamps |> length()),
        uint64(typeinfo(sizeof type<TimestampQueryResult>)*length(data)),
        pdata,
        uint64(typeinfo(sizeof type<TimestampQueryResult>)),
        uint(VkQueryResultFlagBits VK_QUERY_RESULT_64_BIT) |
        uint(VkQueryResultFlagBits VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)
    )
    assert(result == VkResult VK_SUCCESS || result == VkResult VK_NOT_READY)

    //TODO: fill available timestamp data, convert to nanoseconds
