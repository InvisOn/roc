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
x64mac=acef9f9598dd9817d723bc3f9b98350d5509e0556083b3da4a1a4374510b1e60
x64win=0aa727b9541ed66d36430ea76cd3adf88c4b99c56c5b87754560fe6ed74c9d5c
x64mingw=0aa727b9541ed66d36430ea76cd3adf88c4b99c56c5b87754560fe6ed74c9d5c
x64freebsd=4ce4fe0a1c828143aea32616aeede7d8c633ba2080f897906c29cf1676e1cc75
x64openbsd=9d28d2811d62299b5a266ee6cff2dc1f44a142ac80f39c348e34ee467b6c11a7
x64netbsd=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64musl=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64glibc=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64linux=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64elf=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64v1mac=acef9f9598dd9817d723bc3f9b98350d5509e0556083b3da4a1a4374510b1e60
x64v1win=0aa727b9541ed66d36430ea76cd3adf88c4b99c56c5b87754560fe6ed74c9d5c
x64v1mingw=0aa727b9541ed66d36430ea76cd3adf88c4b99c56c5b87754560fe6ed74c9d5c
x64v1freebsd=4ce4fe0a1c828143aea32616aeede7d8c633ba2080f897906c29cf1676e1cc75
x64v1openbsd=9d28d2811d62299b5a266ee6cff2dc1f44a142ac80f39c348e34ee467b6c11a7
x64v1netbsd=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64v1musl=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64v1glibc=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64v1linux=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
x64v1elf=9d928a742183c68a63ec9e431bb749ff242a400d0f4b608ff26c10bb0ffc0398
arm64mac=36da9ee2a3dddb6ea5daeb74776aceba9007e91faf3e54a08d99db96aa5fc73a
arm64win=15bf6523f2c92a9774caac30e8d98016a1c28e472a44e5f9d48f39975a743519
arm64mingw=15bf6523f2c92a9774caac30e8d98016a1c28e472a44e5f9d48f39975a743519
arm64linux=5f06b58b0d26ec1d2a9324b04392a75f75fb3db332de5e28b1652b0e93c41178
arm64musl=5f06b58b0d26ec1d2a9324b04392a75f75fb3db332de5e28b1652b0e93c41178
arm64glibc=5f06b58b0d26ec1d2a9324b04392a75f75fb3db332de5e28b1652b0e93c41178
arm64v1win=15bf6523f2c92a9774caac30e8d98016a1c28e472a44e5f9d48f39975a743519
arm64v1mingw=15bf6523f2c92a9774caac30e8d98016a1c28e472a44e5f9d48f39975a743519
arm64v1linux=5f06b58b0d26ec1d2a9324b04392a75f75fb3db332de5e28b1652b0e93c41178
arm64v1musl=5f06b58b0d26ec1d2a9324b04392a75f75fb3db332de5e28b1652b0e93c41178
arm64v1glibc=5f06b58b0d26ec1d2a9324b04392a75f75fb3db332de5e28b1652b0e93c41178
arm32linux=ffde9863c0f28c58bdd219a881cbf68c7c806f2b90a0bd4fb6872d65e1c7adb8
arm32musl=ffde9863c0f28c58bdd219a881cbf68c7c806f2b90a0bd4fb6872d65e1c7adb8
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
