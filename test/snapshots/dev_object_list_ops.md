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
x64mac=f9546328e1a319905e241db92b8cbab6d29a283d85afacb38223e363ce58357d
x64win=dbc1a66a416ade3a84d2c71854f62bb9474f173820ed733e5ec4f61cfd53ab32
x64mingw=dbc1a66a416ade3a84d2c71854f62bb9474f173820ed733e5ec4f61cfd53ab32
x64freebsd=9032338cf5bc50be1c13d5fe23ac5d22e4bc79c71a402d8d1a9907bab07f123c
x64openbsd=b680063bf0cf52561a08778c8dad00c598da6fb04d5c142c3ec2aacad5a41c2b
x64netbsd=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64musl=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64glibc=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64linux=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64elf=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64v1mac=f9546328e1a319905e241db92b8cbab6d29a283d85afacb38223e363ce58357d
x64v1win=dbc1a66a416ade3a84d2c71854f62bb9474f173820ed733e5ec4f61cfd53ab32
x64v1mingw=dbc1a66a416ade3a84d2c71854f62bb9474f173820ed733e5ec4f61cfd53ab32
x64v1freebsd=9032338cf5bc50be1c13d5fe23ac5d22e4bc79c71a402d8d1a9907bab07f123c
x64v1openbsd=b680063bf0cf52561a08778c8dad00c598da6fb04d5c142c3ec2aacad5a41c2b
x64v1netbsd=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64v1musl=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64v1glibc=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64v1linux=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
x64v1elf=be5ed046d2e333be7b7bb166d0dc06617048cd283f539bb2d53f2e719115eda5
arm64mac=a6b32bc7fd72ed369a38908a1bbddc4bfc6103f18f7255969596db06057ed138
arm64win=e988f683bcf81d37337eaa9fbdf60930c64d7d96515204af1802a6281a932b3d
arm64mingw=e988f683bcf81d37337eaa9fbdf60930c64d7d96515204af1802a6281a932b3d
arm64linux=e13b4997336c304c3337e7440b99edc0e9cbc5718d46169470a01039529b552a
arm64musl=e13b4997336c304c3337e7440b99edc0e9cbc5718d46169470a01039529b552a
arm64glibc=e13b4997336c304c3337e7440b99edc0e9cbc5718d46169470a01039529b552a
arm64v1win=e988f683bcf81d37337eaa9fbdf60930c64d7d96515204af1802a6281a932b3d
arm64v1mingw=e988f683bcf81d37337eaa9fbdf60930c64d7d96515204af1802a6281a932b3d
arm64v1linux=e13b4997336c304c3337e7440b99edc0e9cbc5718d46169470a01039529b552a
arm64v1musl=e13b4997336c304c3337e7440b99edc0e9cbc5718d46169470a01039529b552a
arm64v1glibc=e13b4997336c304c3337e7440b99edc0e9cbc5718d46169470a01039529b552a
arm32linux=7ed57aa6c57bf08728e25e9c9542d61cbcea7d97acc980d1f42ef0f5d2880a31
arm32musl=7ed57aa6c57bf08728e25e9c9542d61cbcea7d97acc980d1f42ef0f5d2880a31
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
