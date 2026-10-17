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
x64mac=0be05fba2a8bf4de467dc543ff23520020dc5026c013f3d75e53122eff2d49be
x64win=8b20230de6164faa28fe87529fecf2cbfaaf3bfc73158a85f1e4ee30317be1e3
x64mingw=8b20230de6164faa28fe87529fecf2cbfaaf3bfc73158a85f1e4ee30317be1e3
x64freebsd=91cdf2b1b3eb174e66bc4282699b6b44412044219802caf33d5ba33fdb9504e3
x64openbsd=d0b824da7c3db61176d27987ad238385ab4c4df9c73bc8afd3e46795e3fd42c9
x64netbsd=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64musl=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64glibc=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64linux=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64elf=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64v1mac=0be05fba2a8bf4de467dc543ff23520020dc5026c013f3d75e53122eff2d49be
x64v1win=8b20230de6164faa28fe87529fecf2cbfaaf3bfc73158a85f1e4ee30317be1e3
x64v1mingw=8b20230de6164faa28fe87529fecf2cbfaaf3bfc73158a85f1e4ee30317be1e3
x64v1freebsd=91cdf2b1b3eb174e66bc4282699b6b44412044219802caf33d5ba33fdb9504e3
x64v1openbsd=d0b824da7c3db61176d27987ad238385ab4c4df9c73bc8afd3e46795e3fd42c9
x64v1netbsd=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64v1musl=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64v1glibc=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64v1linux=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
x64v1elf=0e933cf54434f32c36076c6ce92f588dc6963a278b5a2df71da6d23fb2661161
arm64mac=6a3251606597bc634ac6c9d92a7c778af03ba115245007a43d95d76b9d0203ff
arm64win=bddd2762b2a72c4052d81cd39b46f5a33be4436045f5301263c24cb772c657a9
arm64mingw=bddd2762b2a72c4052d81cd39b46f5a33be4436045f5301263c24cb772c657a9
arm64linux=3df7f560c5ee30b9ba96d8552c662dbd2c0f9f8c1857388dbfc9fed3e2821e8b
arm64musl=3df7f560c5ee30b9ba96d8552c662dbd2c0f9f8c1857388dbfc9fed3e2821e8b
arm64glibc=3df7f560c5ee30b9ba96d8552c662dbd2c0f9f8c1857388dbfc9fed3e2821e8b
arm64v1win=bddd2762b2a72c4052d81cd39b46f5a33be4436045f5301263c24cb772c657a9
arm64v1mingw=bddd2762b2a72c4052d81cd39b46f5a33be4436045f5301263c24cb772c657a9
arm64v1linux=3df7f560c5ee30b9ba96d8552c662dbd2c0f9f8c1857388dbfc9fed3e2821e8b
arm64v1musl=3df7f560c5ee30b9ba96d8552c662dbd2c0f9f8c1857388dbfc9fed3e2821e8b
arm64v1glibc=3df7f560c5ee30b9ba96d8552c662dbd2c0f9f8c1857388dbfc9fed3e2821e8b
arm32linux=97a42c4975e9f158cd5bc04522d70c557a56b7135fb967df13ffc00d0787f51a
arm32musl=97a42c4975e9f158cd5bc04522d70c557a56b7135fb967df13ffc00d0787f51a
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
