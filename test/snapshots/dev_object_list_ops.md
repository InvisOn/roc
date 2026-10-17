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
x64mac=61776e497bbec254cfb8d5cb34aa141ec86d99998c795c0622f1fb060b8bf1b1
x64win=ea852114b7aaacbf87a10e2f0892d953d5c366a757e0edf1709d838cc59645a0
x64mingw=ea852114b7aaacbf87a10e2f0892d953d5c366a757e0edf1709d838cc59645a0
x64freebsd=7c453a5989b7abd3bc09c7f33cd636f68ce58a3f9d5908f13538fe5ff820e1ed
x64openbsd=1c3b5a3578e4fc833ae43b8d1360bd5d5593f60a07e5dc6f653a786c91d2e12e
x64netbsd=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64musl=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64glibc=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64linux=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64elf=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64v1mac=61776e497bbec254cfb8d5cb34aa141ec86d99998c795c0622f1fb060b8bf1b1
x64v1win=ea852114b7aaacbf87a10e2f0892d953d5c366a757e0edf1709d838cc59645a0
x64v1mingw=ea852114b7aaacbf87a10e2f0892d953d5c366a757e0edf1709d838cc59645a0
x64v1freebsd=7c453a5989b7abd3bc09c7f33cd636f68ce58a3f9d5908f13538fe5ff820e1ed
x64v1openbsd=1c3b5a3578e4fc833ae43b8d1360bd5d5593f60a07e5dc6f653a786c91d2e12e
x64v1netbsd=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64v1musl=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64v1glibc=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64v1linux=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
x64v1elf=3df803a0599f7051d28538be93703feceae8a55739d5d6d80a0083dff41da11c
arm64mac=97d6cae583058404eabecd250b4265ec2828da2cd21bbde7ce4eeab84a2afd56
arm64win=1e27c71563c895a34aed62b0b1667330f4911101ce18335816838e65855e373f
arm64mingw=1e27c71563c895a34aed62b0b1667330f4911101ce18335816838e65855e373f
arm64linux=7e461dc1d2bf96b946c7c7d3c897a00429efc594c1d11c5d59b36e8cd2d257d2
arm64musl=7e461dc1d2bf96b946c7c7d3c897a00429efc594c1d11c5d59b36e8cd2d257d2
arm64glibc=7e461dc1d2bf96b946c7c7d3c897a00429efc594c1d11c5d59b36e8cd2d257d2
arm64v1win=1e27c71563c895a34aed62b0b1667330f4911101ce18335816838e65855e373f
arm64v1mingw=1e27c71563c895a34aed62b0b1667330f4911101ce18335816838e65855e373f
arm64v1linux=7e461dc1d2bf96b946c7c7d3c897a00429efc594c1d11c5d59b36e8cd2d257d2
arm64v1musl=7e461dc1d2bf96b946c7c7d3c897a00429efc594c1d11c5d59b36e8cd2d257d2
arm64v1glibc=7e461dc1d2bf96b946c7c7d3c897a00429efc594c1d11c5d59b36e8cd2d257d2
arm32linux=3d8fbe5b9e8474f3156ac6addf9c541d04dfd2b45bf61a189a2ede037abfd10e
arm32musl=3d8fbe5b9e8474f3156ac6addf9c541d04dfd2b45bf61a189a2ede037abfd10e
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
