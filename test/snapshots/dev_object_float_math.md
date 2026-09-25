# META
~~~ini
description=F32/F64 arithmetic, comparisons, and F64 to I64 conversion in host-called functions
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : F64, F32, I64 -> I64
main = |x, y, n| {
    scaled = x * 2.5 - I64.to_f64(n) / 3.0
    narrowed = F32.to_f64(y * 1.5 + 0.25)
    total = if scaled > narrowed { scaled - narrowed } else { narrowed + scaled }
    F64.to_i64_wrap(total)
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : F64, F32, I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : F64, F32, I64 -> I64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |x, y, n| {
	scaled = x * 2.5 - to_f64(n) / 3
	narrowed = to_f64(y * 1.5 + 0.25)
	total = if (scaled > narrowed) {
		scaled - narrowed
	} else {
		narrowed + scaled
	}
	to_i64_wrap(total)
}

~~~
# DEV OUTPUT
~~~ini
x64mac=22e6eab1f07f52ac937bbdedd39b5d3a53a4baf77e1fb0bb1a77007a7b2418ba
x64win=634ffa1585b0f96dd9f2d790ead5fb7dd90cf6fd4e5b2aa95d12ade6d6d37cc8
x64mingw=634ffa1585b0f96dd9f2d790ead5fb7dd90cf6fd4e5b2aa95d12ade6d6d37cc8
x64freebsd=69af23878446a2a0dde15d5a6f28f62d48dd3a303331c14ab3ac5a450e906669
x64openbsd=974c69b768fd27ba883e577d395222fef7b7cb5b199f462932679b02a3975f43
x64netbsd=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64musl=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64glibc=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64linux=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64elf=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64v1mac=22e6eab1f07f52ac937bbdedd39b5d3a53a4baf77e1fb0bb1a77007a7b2418ba
x64v1win=634ffa1585b0f96dd9f2d790ead5fb7dd90cf6fd4e5b2aa95d12ade6d6d37cc8
x64v1mingw=634ffa1585b0f96dd9f2d790ead5fb7dd90cf6fd4e5b2aa95d12ade6d6d37cc8
x64v1freebsd=69af23878446a2a0dde15d5a6f28f62d48dd3a303331c14ab3ac5a450e906669
x64v1openbsd=974c69b768fd27ba883e577d395222fef7b7cb5b199f462932679b02a3975f43
x64v1netbsd=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64v1musl=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64v1glibc=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64v1linux=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
x64v1elf=e860344c36daf081986af9e408ddfecfd33fd1b4cf14e7d7c0cff71367843cd6
arm64mac=f0d82ce9f9aa4ca8de782d3257a50b3c995815a649113ab43627b92ae9819dc0
arm64win=82f66c1c5c7f38aaa2ea43edcff11d4ded8d8cf413fdaf0e2b955279c690a610
arm64mingw=82f66c1c5c7f38aaa2ea43edcff11d4ded8d8cf413fdaf0e2b955279c690a610
arm64linux=924666b613a9925794dbdf58449510f48e5db3e2b1a0ec3ba55cfc37f306cae6
arm64musl=924666b613a9925794dbdf58449510f48e5db3e2b1a0ec3ba55cfc37f306cae6
arm64glibc=924666b613a9925794dbdf58449510f48e5db3e2b1a0ec3ba55cfc37f306cae6
arm64v1win=82f66c1c5c7f38aaa2ea43edcff11d4ded8d8cf413fdaf0e2b955279c690a610
arm64v1mingw=82f66c1c5c7f38aaa2ea43edcff11d4ded8d8cf413fdaf0e2b955279c690a610
arm64v1linux=924666b613a9925794dbdf58449510f48e5db3e2b1a0ec3ba55cfc37f306cae6
arm64v1musl=924666b613a9925794dbdf58449510f48e5db3e2b1a0ec3ba55cfc37f306cae6
arm64v1glibc=924666b613a9925794dbdf58449510f48e5db3e2b1a0ec3ba55cfc37f306cae6
arm32linux=4a29156847b446625b34a10c19e66c25a26636a7cce2a8816c70f5b31e8d1156
arm32musl=4a29156847b446625b34a10c19e66c25a26636a7cce2a8816c70f5b31e8d1156
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
