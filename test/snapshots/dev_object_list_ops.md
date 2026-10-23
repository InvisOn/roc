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
x64mac=9a417b2e404b6b7863454ee3b659aae4e88db583986dad47e7635faea2a10e75
x64win=1e491506ac854946edd5816db9b7e972c79de78d68414b7fea0c90b48671d0f3
x64mingw=1e491506ac854946edd5816db9b7e972c79de78d68414b7fea0c90b48671d0f3
x64freebsd=590542842d3c440fc4a4a405c010d5e260563738430a2dd3aebd7347803301fe
x64openbsd=b955c4b132534b9cb12dafc402b2d2d644bfbe622537510f1ede7c86849ad3b9
x64netbsd=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64musl=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64glibc=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64linux=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64elf=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64v1mac=9a417b2e404b6b7863454ee3b659aae4e88db583986dad47e7635faea2a10e75
x64v1win=1e491506ac854946edd5816db9b7e972c79de78d68414b7fea0c90b48671d0f3
x64v1mingw=1e491506ac854946edd5816db9b7e972c79de78d68414b7fea0c90b48671d0f3
x64v1freebsd=590542842d3c440fc4a4a405c010d5e260563738430a2dd3aebd7347803301fe
x64v1openbsd=b955c4b132534b9cb12dafc402b2d2d644bfbe622537510f1ede7c86849ad3b9
x64v1netbsd=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64v1musl=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64v1glibc=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64v1linux=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
x64v1elf=bd3a740891fc534e6c8c9f8373c34aede983001eb2dacfadb50654a80f13a394
arm64mac=fe8435a4ef96efe2bba567771ebcc43bf8ce94f4723fbf7cd164ccc705d5a902
arm64win=706fdc3664f97d762a71dcaaee768de3c376cf548172658570d28e0ccc6cbf96
arm64mingw=706fdc3664f97d762a71dcaaee768de3c376cf548172658570d28e0ccc6cbf96
arm64linux=3ba87d6a1a204cb16ce4543ad188a591cfad77e51fa499bfcdedfe98e054e8b1
arm64musl=3ba87d6a1a204cb16ce4543ad188a591cfad77e51fa499bfcdedfe98e054e8b1
arm64glibc=3ba87d6a1a204cb16ce4543ad188a591cfad77e51fa499bfcdedfe98e054e8b1
arm64v1win=706fdc3664f97d762a71dcaaee768de3c376cf548172658570d28e0ccc6cbf96
arm64v1mingw=706fdc3664f97d762a71dcaaee768de3c376cf548172658570d28e0ccc6cbf96
arm64v1linux=3ba87d6a1a204cb16ce4543ad188a591cfad77e51fa499bfcdedfe98e054e8b1
arm64v1musl=3ba87d6a1a204cb16ce4543ad188a591cfad77e51fa499bfcdedfe98e054e8b1
arm64v1glibc=3ba87d6a1a204cb16ce4543ad188a591cfad77e51fa499bfcdedfe98e054e8b1
arm32linux=7e8611871f26ec77e7b7c681f38c4fd538045b88ce8fda44d89b3938657e6ce6
arm32musl=7e8611871f26ec77e7b7c681f38c4fd538045b88ce8fda44d89b3938657e6ce6
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
