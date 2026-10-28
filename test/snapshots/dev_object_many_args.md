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
x64mac=ee6029e43873e115e7567514493a88b4e896d7af5b0da89c8dd8bcd1c75efb38
x64win=a988216ff697891f795d2c7a44b2464f7627219314bd1b7065e78e7250c25b03
x64mingw=a988216ff697891f795d2c7a44b2464f7627219314bd1b7065e78e7250c25b03
x64freebsd=7b3b561af2d0bc65bdaad7a4eb2ae480680f27db2f687c97a17b0ad5c8160d92
x64openbsd=8fd268f5c40d1189c2cf0d2155dedddd95668f3d764c7faf6964c220f2da121f
x64netbsd=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64musl=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64glibc=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64linux=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64elf=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64v1mac=ee6029e43873e115e7567514493a88b4e896d7af5b0da89c8dd8bcd1c75efb38
x64v1win=a988216ff697891f795d2c7a44b2464f7627219314bd1b7065e78e7250c25b03
x64v1mingw=a988216ff697891f795d2c7a44b2464f7627219314bd1b7065e78e7250c25b03
x64v1freebsd=7b3b561af2d0bc65bdaad7a4eb2ae480680f27db2f687c97a17b0ad5c8160d92
x64v1openbsd=8fd268f5c40d1189c2cf0d2155dedddd95668f3d764c7faf6964c220f2da121f
x64v1netbsd=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64v1musl=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64v1glibc=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64v1linux=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
x64v1elf=a5368c37959952ea9325f19abc39c7df4b8eb1c750d60c5f2b68c9f19fdc8ffa
arm64mac=c624fef2bc76d6f59972d7dd3406c377b4d3d714e4ba84530fa5ec7b8f74a50f
arm64win=42006545627fe34baa9c479648e5d7e9a3be7f69897729307ac16f21ff3ee2a0
arm64mingw=42006545627fe34baa9c479648e5d7e9a3be7f69897729307ac16f21ff3ee2a0
arm64linux=dc1d0280187f9b3689ab77d78eb52ea62f9e0c4d790d969dae8d41b5fb1cf182
arm64musl=dc1d0280187f9b3689ab77d78eb52ea62f9e0c4d790d969dae8d41b5fb1cf182
arm64glibc=dc1d0280187f9b3689ab77d78eb52ea62f9e0c4d790d969dae8d41b5fb1cf182
arm64v1win=42006545627fe34baa9c479648e5d7e9a3be7f69897729307ac16f21ff3ee2a0
arm64v1mingw=42006545627fe34baa9c479648e5d7e9a3be7f69897729307ac16f21ff3ee2a0
arm64v1linux=dc1d0280187f9b3689ab77d78eb52ea62f9e0c4d790d969dae8d41b5fb1cf182
arm64v1musl=dc1d0280187f9b3689ab77d78eb52ea62f9e0c4d790d969dae8d41b5fb1cf182
arm64v1glibc=dc1d0280187f9b3689ab77d78eb52ea62f9e0c4d790d969dae8d41b5fb1cf182
arm32linux=14998b9a42088490438aa550e036d85e9f54c73ec3e1c522f12ed649280aa878
arm32musl=14998b9a42088490438aa550e036d85e9f54c73ec3e1c522f12ed649280aa878
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
