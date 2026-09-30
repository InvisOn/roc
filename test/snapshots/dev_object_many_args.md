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
x64mac=2f84e391f3dcc8f0d0ea555a154f0239852d47ec3774d8aa517c377856b01984
x64win=e491ca0679b71fcd6474e7f0f1720c7d1cd67a5b47bccf3541e0102a9e0d96b5
x64mingw=e491ca0679b71fcd6474e7f0f1720c7d1cd67a5b47bccf3541e0102a9e0d96b5
x64freebsd=e147974be818138e04f72ca01f9f53982c3a2b1093506c17658ae933c6199c59
x64openbsd=4345c1ae5de743c79e96c632446c27456a383bf7e0e3271d3a7105f7a31a30da
x64netbsd=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64musl=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64glibc=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64linux=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64elf=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64v1mac=2f84e391f3dcc8f0d0ea555a154f0239852d47ec3774d8aa517c377856b01984
x64v1win=e491ca0679b71fcd6474e7f0f1720c7d1cd67a5b47bccf3541e0102a9e0d96b5
x64v1mingw=e491ca0679b71fcd6474e7f0f1720c7d1cd67a5b47bccf3541e0102a9e0d96b5
x64v1freebsd=e147974be818138e04f72ca01f9f53982c3a2b1093506c17658ae933c6199c59
x64v1openbsd=4345c1ae5de743c79e96c632446c27456a383bf7e0e3271d3a7105f7a31a30da
x64v1netbsd=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64v1musl=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64v1glibc=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64v1linux=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
x64v1elf=a0f245cf93298103c3d46de7b79f4eb6e19002ce4ec71cf07aac331a9e1df21b
arm64mac=b2eacb065ba9ceeb225c6099c518895db4e177ebd17e7c02200bb73ea226285d
arm64win=ce13f7ea5c27e1b662addc3ad2cb1b552366a73c9921ef884f9674d47bb30a83
arm64mingw=ce13f7ea5c27e1b662addc3ad2cb1b552366a73c9921ef884f9674d47bb30a83
arm64linux=8c4b604b22a9552064efcb06ba61125055de4d39248f3f29ef484944cbf3d7e2
arm64musl=8c4b604b22a9552064efcb06ba61125055de4d39248f3f29ef484944cbf3d7e2
arm64glibc=8c4b604b22a9552064efcb06ba61125055de4d39248f3f29ef484944cbf3d7e2
arm64v1win=ce13f7ea5c27e1b662addc3ad2cb1b552366a73c9921ef884f9674d47bb30a83
arm64v1mingw=ce13f7ea5c27e1b662addc3ad2cb1b552366a73c9921ef884f9674d47bb30a83
arm64v1linux=8c4b604b22a9552064efcb06ba61125055de4d39248f3f29ef484944cbf3d7e2
arm64v1musl=8c4b604b22a9552064efcb06ba61125055de4d39248f3f29ef484944cbf3d7e2
arm64v1glibc=8c4b604b22a9552064efcb06ba61125055de4d39248f3f29ef484944cbf3d7e2
arm32linux=72ba34280d0ba7ae54c8958fb461bdfc29d1eb0a2a6d34a66d13b8aae44c6856
arm32musl=72ba34280d0ba7ae54c8958fb461bdfc29d1eb0a2a6d34a66d13b8aae44c6856
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
