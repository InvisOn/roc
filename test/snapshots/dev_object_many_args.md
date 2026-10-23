# META
~~~ini
description=Eighteen mixed integer and float arguments overflow both argument register files
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

combine : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64
combine = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8| {
    ints = i0 + i1 * 2 + i2 * 3 + i3 * 4 + i4 * 5 + i5 * 6 + i6 * 7 + i7 * 8 + i8 * 9
    floats = f0 + f1 * 2.0 + f2 * 3.0 + f3 * 4.0 + f4 * 5.0 + f5 * 6.0 + f6 * 7.0 + f7 * 8.0 + f8 * 9.0
    I64.to_f64(ints) + floats
}

main : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64
main = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8|
    combine(i8, f8, i7, f7, i6, f6, i5, f5, i4, f4, i3, f3, i2, f2, i1, f1, i0, f0)
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
combine = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8| {
	ints = i0 + i1 * 2 + i2 * 3 + i3 * 4 + i4 * 5 + i5 * 6 + i6 * 7 + i7 * 8 + i8 * 9
	floats = f0 + f1 * 2 + f2 * 3 + f3 * 4 + f4 * 5 + f5 * 6 + f6 * 7 + f7 * 8 + f8 * 9
	to_f64(ints) + floats
}
main = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8| combine(i8, f8, i7, f7, i6, f6, i5, f5, i4, f4, i3, f3, i2, f2, i1, f1, i0, f0)

~~~
# DEV OUTPUT
~~~ini
x64mac=c9494828e674225f0903d3e53bd6e913d7eaed8deffa51b5e7f5eab82eda1e52
x64win=272218e027f4f84ea2a8bd21c1ec174f927961c279d906ba983e3568daead116
x64mingw=272218e027f4f84ea2a8bd21c1ec174f927961c279d906ba983e3568daead116
x64freebsd=fb4c4f6490febe969ef1210c53994b6d023c24c51a6aa2539f3ccb12b50f222a
x64openbsd=b28686a688604edb806ba2a25aa35e4132fbb12e13ac741c80472f5c1de5e8fe
x64netbsd=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64musl=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64glibc=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64linux=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64elf=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64v1mac=c9494828e674225f0903d3e53bd6e913d7eaed8deffa51b5e7f5eab82eda1e52
x64v1win=272218e027f4f84ea2a8bd21c1ec174f927961c279d906ba983e3568daead116
x64v1mingw=272218e027f4f84ea2a8bd21c1ec174f927961c279d906ba983e3568daead116
x64v1freebsd=fb4c4f6490febe969ef1210c53994b6d023c24c51a6aa2539f3ccb12b50f222a
x64v1openbsd=b28686a688604edb806ba2a25aa35e4132fbb12e13ac741c80472f5c1de5e8fe
x64v1netbsd=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64v1musl=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64v1glibc=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64v1linux=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
x64v1elf=659cb0745d6b749e5d8394d86f97463c0f067bd673ff65e666729709320eda6c
arm64mac=b5011340c93e1605308a280e287c33d183cbe9606d55683801c8c584081c8be5
arm64win=444fcc05c5c961893a99d98f3d8ae472fb545d9abe61cc5d833e273160bfb931
arm64mingw=444fcc05c5c961893a99d98f3d8ae472fb545d9abe61cc5d833e273160bfb931
arm64linux=5a3502e1c8e5ca2008794694346476a2b16487d02ce8e9f1a0a1c3b76b398570
arm64musl=5a3502e1c8e5ca2008794694346476a2b16487d02ce8e9f1a0a1c3b76b398570
arm64glibc=5a3502e1c8e5ca2008794694346476a2b16487d02ce8e9f1a0a1c3b76b398570
arm64v1win=444fcc05c5c961893a99d98f3d8ae472fb545d9abe61cc5d833e273160bfb931
arm64v1mingw=444fcc05c5c961893a99d98f3d8ae472fb545d9abe61cc5d833e273160bfb931
arm64v1linux=5a3502e1c8e5ca2008794694346476a2b16487d02ce8e9f1a0a1c3b76b398570
arm64v1musl=5a3502e1c8e5ca2008794694346476a2b16487d02ce8e9f1a0a1c3b76b398570
arm64v1glibc=5a3502e1c8e5ca2008794694346476a2b16487d02ce8e9f1a0a1c3b76b398570
arm32linux=07cda8bb5dcd97df838e27fa3656706d91d277c87f249195ee96ce9ad0e6be0b
arm32musl=07cda8bb5dcd97df838e27fa3656706d91d277c87f249195ee96ce9ad0e6be0b
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
