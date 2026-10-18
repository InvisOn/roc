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
x64mac=186aa851602886ef0dd3a504e9eb2c1e399ddd4f5d640f40d9290e6aac483537
x64win=9e3e3b1ed90e3600915b6e655cc62bacbb892bd92e1ab840ebf9a3ec0ca68ee2
x64mingw=9e3e3b1ed90e3600915b6e655cc62bacbb892bd92e1ab840ebf9a3ec0ca68ee2
x64freebsd=b76d279f45cac022974737c27c061686705aa708fa36ac8339d79ca380bba1c4
x64openbsd=3596f4385fe8a80da33601a3499f971c98d84b34bb9f1667f05150c8e95e5584
x64netbsd=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64musl=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64glibc=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64linux=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64elf=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64v1mac=186aa851602886ef0dd3a504e9eb2c1e399ddd4f5d640f40d9290e6aac483537
x64v1win=9e3e3b1ed90e3600915b6e655cc62bacbb892bd92e1ab840ebf9a3ec0ca68ee2
x64v1mingw=9e3e3b1ed90e3600915b6e655cc62bacbb892bd92e1ab840ebf9a3ec0ca68ee2
x64v1freebsd=b76d279f45cac022974737c27c061686705aa708fa36ac8339d79ca380bba1c4
x64v1openbsd=3596f4385fe8a80da33601a3499f971c98d84b34bb9f1667f05150c8e95e5584
x64v1netbsd=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64v1musl=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64v1glibc=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64v1linux=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
x64v1elf=76c2636fbf706e33d154c2b101560fb3c25a15a9fa15b12bdabfd4f540562158
arm64mac=fb2f7890804a494cd5244d0703faf139a152afb83ef7d2b7b528efc9763a5025
arm64win=24e716ec156b68a6f0a674add76e6d492988dfc4a32d630b6dfb4209c3924273
arm64mingw=24e716ec156b68a6f0a674add76e6d492988dfc4a32d630b6dfb4209c3924273
arm64linux=3322fa53b6edaef71b941bce4995590228e10836a94c93162bd321b202f1f984
arm64musl=3322fa53b6edaef71b941bce4995590228e10836a94c93162bd321b202f1f984
arm64glibc=3322fa53b6edaef71b941bce4995590228e10836a94c93162bd321b202f1f984
arm64v1win=24e716ec156b68a6f0a674add76e6d492988dfc4a32d630b6dfb4209c3924273
arm64v1mingw=24e716ec156b68a6f0a674add76e6d492988dfc4a32d630b6dfb4209c3924273
arm64v1linux=3322fa53b6edaef71b941bce4995590228e10836a94c93162bd321b202f1f984
arm64v1musl=3322fa53b6edaef71b941bce4995590228e10836a94c93162bd321b202f1f984
arm64v1glibc=3322fa53b6edaef71b941bce4995590228e10836a94c93162bd321b202f1f984
arm32linux=1523dcceae3c752e5d712d179c713c30342b502367911b354eea544f721357c7
arm32musl=1523dcceae3c752e5d712d179c713c30342b502367911b354eea544f721357c7
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
