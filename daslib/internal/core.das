options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan
require fio
require strings


def to_string(bytes : void?)
    unsafe
        return reinterpret<string>(bytes)


//TODO: need this for heap
def safe_addr_plain(x : auto(T)) : T ? #
    unsafe
        return reinterpret<T?#>(addr(x))


//TODO: need this for heap
def safe_addr_val(var x : auto(T)&) : T-& ? #
    unsafe
        return reinterpret<T-&?#>(addr(x))


def read_file_to_array(file_path : string) : array<uint8>
    var data : array<uint8>
    fopen(file_path, "rb") <| $(f : FILE const ?)
        data |> resize(int((f |> fstat()).size))
        f |> fmap() <| $(fdata : string const #)
            data |> lock() <| $(tdata)
                for dst, i in tdata, range(INT_MAX)
                    unsafe
                        dst = uint8(fdata |> character_uat(i))
    return <- data
