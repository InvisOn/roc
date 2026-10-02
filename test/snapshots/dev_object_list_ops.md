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
x64mac=64463b839d352ff962eeef5b1d8d96125f8c3be9ad09e473a955817a989315b2
x64win=94a1e8eefb5b921e31ba4cb8fa3e22fbac1a02e370967855e1505de3e89410d9
x64mingw=94a1e8eefb5b921e31ba4cb8fa3e22fbac1a02e370967855e1505de3e89410d9
x64freebsd=73a328e1251ba175a140bf9f4b6d1f25a9e94599cf9e6f27192f4b855958f471
x64openbsd=d4b541b3b8caf1e490c56276314eee116f42c4fc85ff39e53ae0afb37eb24528
x64netbsd=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64musl=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64glibc=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64linux=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64elf=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64v1mac=64463b839d352ff962eeef5b1d8d96125f8c3be9ad09e473a955817a989315b2
x64v1win=94a1e8eefb5b921e31ba4cb8fa3e22fbac1a02e370967855e1505de3e89410d9
x64v1mingw=94a1e8eefb5b921e31ba4cb8fa3e22fbac1a02e370967855e1505de3e89410d9
x64v1freebsd=73a328e1251ba175a140bf9f4b6d1f25a9e94599cf9e6f27192f4b855958f471
x64v1openbsd=d4b541b3b8caf1e490c56276314eee116f42c4fc85ff39e53ae0afb37eb24528
x64v1netbsd=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64v1musl=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64v1glibc=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64v1linux=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
x64v1elf=40e158a6ea890bab255835cea432893d71d6e079fdb92abbef92e27e56640e69
arm64mac=9dedc81f40c299870773113835cebfe6b729c43c8dfd10e58cbd3b41085f0485
arm64win=1c58bf52018c64833749d9359f1298b3b7e3818cca8ed9f13c1ea831561d2352
arm64mingw=1c58bf52018c64833749d9359f1298b3b7e3818cca8ed9f13c1ea831561d2352
arm64linux=ee54927dfba0f963b080c6b941498f7c496bf2179d65166f94489c67cc8fded1
arm64musl=ee54927dfba0f963b080c6b941498f7c496bf2179d65166f94489c67cc8fded1
arm64glibc=ee54927dfba0f963b080c6b941498f7c496bf2179d65166f94489c67cc8fded1
arm64v1win=1c58bf52018c64833749d9359f1298b3b7e3818cca8ed9f13c1ea831561d2352
arm64v1mingw=1c58bf52018c64833749d9359f1298b3b7e3818cca8ed9f13c1ea831561d2352
arm64v1linux=ee54927dfba0f963b080c6b941498f7c496bf2179d65166f94489c67cc8fded1
arm64v1musl=ee54927dfba0f963b080c6b941498f7c496bf2179d65166f94489c67cc8fded1
arm64v1glibc=ee54927dfba0f963b080c6b941498f7c496bf2179d65166f94489c67cc8fded1
arm32linux=a38397f46416633cd6e93fafb1b2300bc4f344b0a396c1fa49ae8a44fd5587f6
arm32musl=a38397f46416633cd6e93fafb1b2300bc4f344b0a396c1fa49ae8a44fd5587f6
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
