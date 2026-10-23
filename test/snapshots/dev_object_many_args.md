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
x64mac=af0200436c068d908f26ee665fc5c44aec5fe6113b38bd1a6bc307524c1602a9
x64win=2403f4f54df41aacc48f2378a619c5f1b5a3801d21bec2b053bbbe32fedba41e
x64mingw=2403f4f54df41aacc48f2378a619c5f1b5a3801d21bec2b053bbbe32fedba41e
x64freebsd=2be0ad162f3c78711068db6b87e56a78f58788337f92e1c11d923b19b2b35902
x64openbsd=33f7e5ac0a39f3e22331bb09475e259e191943b6c3dc62515bba706073515ac5
x64netbsd=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64musl=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64glibc=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64linux=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64elf=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64v1mac=af0200436c068d908f26ee665fc5c44aec5fe6113b38bd1a6bc307524c1602a9
x64v1win=2403f4f54df41aacc48f2378a619c5f1b5a3801d21bec2b053bbbe32fedba41e
x64v1mingw=2403f4f54df41aacc48f2378a619c5f1b5a3801d21bec2b053bbbe32fedba41e
x64v1freebsd=2be0ad162f3c78711068db6b87e56a78f58788337f92e1c11d923b19b2b35902
x64v1openbsd=33f7e5ac0a39f3e22331bb09475e259e191943b6c3dc62515bba706073515ac5
x64v1netbsd=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64v1musl=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64v1glibc=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64v1linux=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
x64v1elf=e2f37b52c364b8d7c217c324a5a22d13dfe6b1f6ca9c5706b69815b9431c0ec7
arm64mac=f8e6790d80500212fa480612d26e6fa84c63be2ced8002dc40be2769d0f70140
arm64win=5e613c5316dad23abfbc71c3da85515ec3630a1bf17afdd8fd63011df3e64f16
arm64mingw=5e613c5316dad23abfbc71c3da85515ec3630a1bf17afdd8fd63011df3e64f16
arm64linux=069ff896a42acf804af490334fb86918f197a428790278ff1b89c15d6cefb2b7
arm64musl=069ff896a42acf804af490334fb86918f197a428790278ff1b89c15d6cefb2b7
arm64glibc=069ff896a42acf804af490334fb86918f197a428790278ff1b89c15d6cefb2b7
arm64v1win=5e613c5316dad23abfbc71c3da85515ec3630a1bf17afdd8fd63011df3e64f16
arm64v1mingw=5e613c5316dad23abfbc71c3da85515ec3630a1bf17afdd8fd63011df3e64f16
arm64v1linux=069ff896a42acf804af490334fb86918f197a428790278ff1b89c15d6cefb2b7
arm64v1musl=069ff896a42acf804af490334fb86918f197a428790278ff1b89c15d6cefb2b7
arm64v1glibc=069ff896a42acf804af490334fb86918f197a428790278ff1b89c15d6cefb2b7
arm32linux=5d926f9e04a9629fbc9f580dc7b4d2f3dee8ffbad0e74e13b497972b9d14cb24
arm32musl=5d926f9e04a9629fbc9f580dc7b4d2f3dee8ffbad0e74e13b497972b9d14cb24
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
