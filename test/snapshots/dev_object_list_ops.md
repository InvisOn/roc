# META
~~~ini
description=List append, get, len and map with a closure capturing two locals
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : List(I64), I64, I64 -> I64
main = |xs, a, b| {
    scale = a * 2
    offset = b - 1
    ys = List.map(List.append(xs, a), |x| x * scale + offset)
    first =
        match List.get(ys, 0) {
            Ok(v) => v
            Err(_) => -1
        }
    first + U64.to_i64_wrap(List.len(ys))
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : List(I64), I64, I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : List(I64), I64, I64 -> I64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |xs, a, b| {
	scale = a * 2
	offset = b - 1
	ys = map(append(xs, a), |x| x * scale + offset)
	first = match get(ys, 0) {
		Ok(v) => v
		Err(_) => -1
	}
	first + to_i64_wrap(len(ys))
}

~~~
# DEV OUTPUT
~~~ini
x64mac=6a70fec5e274b4073e55bbf68db2a3fc3eb0dbd6206366a8ef5e05a0b2c51cd3
x64win=2ee03ace70df58ac3c77d6e7365c109f0565e26c3a2ec7406ae2b11c9af8f60a
x64mingw=2ee03ace70df58ac3c77d6e7365c109f0565e26c3a2ec7406ae2b11c9af8f60a
x64freebsd=3ddeb43dbd35287baee80f68599d7908e04ffe863c846c13d74d495b0df2195d
x64openbsd=363e6fb4b181ba7dfff2dec00f67029046ec81af26cccf0629c098741ad83d2a
x64netbsd=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64musl=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64glibc=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64linux=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64elf=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64v1mac=6a70fec5e274b4073e55bbf68db2a3fc3eb0dbd6206366a8ef5e05a0b2c51cd3
x64v1win=2ee03ace70df58ac3c77d6e7365c109f0565e26c3a2ec7406ae2b11c9af8f60a
x64v1mingw=2ee03ace70df58ac3c77d6e7365c109f0565e26c3a2ec7406ae2b11c9af8f60a
x64v1freebsd=3ddeb43dbd35287baee80f68599d7908e04ffe863c846c13d74d495b0df2195d
x64v1openbsd=363e6fb4b181ba7dfff2dec00f67029046ec81af26cccf0629c098741ad83d2a
x64v1netbsd=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64v1musl=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64v1glibc=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64v1linux=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
x64v1elf=7ec9a0cffe03996a7e890db1a86c4c07f609aa741ee87724a14f2483cf7e92d2
arm64mac=6bfd87d8554d2d52f010cb7decb776c5fe7420e9366f71446faa9db9b04391d0
arm64win=851455a3d9fc30b94eca62156dead3cfbf6e65849c6570e451bfbb23c6450ecd
arm64mingw=851455a3d9fc30b94eca62156dead3cfbf6e65849c6570e451bfbb23c6450ecd
arm64linux=46f20fae7f1c5f1feadc43096f629fa23c7e429bc592188263bd1f172fdde0f6
arm64musl=46f20fae7f1c5f1feadc43096f629fa23c7e429bc592188263bd1f172fdde0f6
arm64glibc=46f20fae7f1c5f1feadc43096f629fa23c7e429bc592188263bd1f172fdde0f6
arm64v1win=851455a3d9fc30b94eca62156dead3cfbf6e65849c6570e451bfbb23c6450ecd
arm64v1mingw=851455a3d9fc30b94eca62156dead3cfbf6e65849c6570e451bfbb23c6450ecd
arm64v1linux=46f20fae7f1c5f1feadc43096f629fa23c7e429bc592188263bd1f172fdde0f6
arm64v1musl=46f20fae7f1c5f1feadc43096f629fa23c7e429bc592188263bd1f172fdde0f6
arm64v1glibc=46f20fae7f1c5f1feadc43096f629fa23c7e429bc592188263bd1f172fdde0f6
arm32linux=7463b947b96207fabd01390ff28d7f4c38f38608bd641bb6dc2d38f13993d4aa
arm32musl=7463b947b96207fabd01390ff28d7f4c38f38608bd641bb6dc2d38f13993d4aa
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
