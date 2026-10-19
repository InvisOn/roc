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
x64mac=c9e3c04b1a87462437cdba36dcf882453bf7f2fead969b753cf246c84804c029
x64win=c11d5bbd0d2d1c50478149dbf7140a83610e7a3f256aa5d1d7cf7a059dc4b812
x64mingw=c11d5bbd0d2d1c50478149dbf7140a83610e7a3f256aa5d1d7cf7a059dc4b812
x64freebsd=1e8fd510154bab197f88e3531a84ff3133178324c031a22dd1aa961c86b5e049
x64openbsd=d991d7c15127e3611aedc037b83ba84f33f2ac5fb85897cf9600705fe963d0c7
x64netbsd=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64musl=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64glibc=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64linux=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64elf=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64v1mac=c9e3c04b1a87462437cdba36dcf882453bf7f2fead969b753cf246c84804c029
x64v1win=c11d5bbd0d2d1c50478149dbf7140a83610e7a3f256aa5d1d7cf7a059dc4b812
x64v1mingw=c11d5bbd0d2d1c50478149dbf7140a83610e7a3f256aa5d1d7cf7a059dc4b812
x64v1freebsd=1e8fd510154bab197f88e3531a84ff3133178324c031a22dd1aa961c86b5e049
x64v1openbsd=d991d7c15127e3611aedc037b83ba84f33f2ac5fb85897cf9600705fe963d0c7
x64v1netbsd=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64v1musl=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64v1glibc=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64v1linux=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
x64v1elf=f56f8b841fdcd22c6664a1a8f0b30e5437b67870c30f66bee965270e5c4d951c
arm64mac=149d409f0d62d5b354a789a7f8983af03eca1d8e28acdba37254578b60133fe6
arm64win=6c725c6134b6f3d7dfeac2f16b19a10facf7c545f8c1cec8126e8a79a856adb5
arm64mingw=6c725c6134b6f3d7dfeac2f16b19a10facf7c545f8c1cec8126e8a79a856adb5
arm64linux=6bd7774746cc6d5723194cc1f2e3679af56841640c61983d2bc51ad28e370981
arm64musl=6bd7774746cc6d5723194cc1f2e3679af56841640c61983d2bc51ad28e370981
arm64glibc=6bd7774746cc6d5723194cc1f2e3679af56841640c61983d2bc51ad28e370981
arm64v1win=6c725c6134b6f3d7dfeac2f16b19a10facf7c545f8c1cec8126e8a79a856adb5
arm64v1mingw=6c725c6134b6f3d7dfeac2f16b19a10facf7c545f8c1cec8126e8a79a856adb5
arm64v1linux=6bd7774746cc6d5723194cc1f2e3679af56841640c61983d2bc51ad28e370981
arm64v1musl=6bd7774746cc6d5723194cc1f2e3679af56841640c61983d2bc51ad28e370981
arm64v1glibc=6bd7774746cc6d5723194cc1f2e3679af56841640c61983d2bc51ad28e370981
arm32linux=c63243d2b3a7a6a70f632196a2061e1211a9e5f9b5708acadda4002b9d4c3e9f
arm32musl=c63243d2b3a7a6a70f632196a2061e1211a9e5f9b5708acadda4002b9d4c3e9f
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
