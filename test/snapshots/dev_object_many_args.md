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
x64mac=a5d1e1149c66e9c5b01a3b29b6ed4b5bf56b2b4d5b5d0a6e3791630a9859324d
x64win=a926262e7be8781f7b6530982472f722e645b90bed43d4183bdcfb9acd9014f0
x64mingw=a926262e7be8781f7b6530982472f722e645b90bed43d4183bdcfb9acd9014f0
x64freebsd=f52d3e8e4d4a52da100cd78594e6d7182146ef98486935ac21291aa6be72f8f7
x64openbsd=7ec175456f16a92c081dafb13f1e8e371737fc9619af0daaaa79307ac8125ca6
x64netbsd=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64musl=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64glibc=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64linux=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64elf=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64v1mac=a5d1e1149c66e9c5b01a3b29b6ed4b5bf56b2b4d5b5d0a6e3791630a9859324d
x64v1win=a926262e7be8781f7b6530982472f722e645b90bed43d4183bdcfb9acd9014f0
x64v1mingw=a926262e7be8781f7b6530982472f722e645b90bed43d4183bdcfb9acd9014f0
x64v1freebsd=f52d3e8e4d4a52da100cd78594e6d7182146ef98486935ac21291aa6be72f8f7
x64v1openbsd=7ec175456f16a92c081dafb13f1e8e371737fc9619af0daaaa79307ac8125ca6
x64v1netbsd=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64v1musl=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64v1glibc=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64v1linux=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
x64v1elf=08fa59d6029f718272223504585561b2eb82a64d6d1e9860a3c71f8232e71c59
arm64mac=9960e45d30ec294b86572730b740a5393585d6968eada5bc2f761978914dbab7
arm64win=13af359c75b4a7c830dbfe8ad68c5cea6e6cee548c9a23785c856dc5a4a820b0
arm64mingw=13af359c75b4a7c830dbfe8ad68c5cea6e6cee548c9a23785c856dc5a4a820b0
arm64linux=0aef89829de960790f86d511596b48492b2f19f80a0460fa33b4a8d4fff40f84
arm64musl=0aef89829de960790f86d511596b48492b2f19f80a0460fa33b4a8d4fff40f84
arm64glibc=0aef89829de960790f86d511596b48492b2f19f80a0460fa33b4a8d4fff40f84
arm64v1win=13af359c75b4a7c830dbfe8ad68c5cea6e6cee548c9a23785c856dc5a4a820b0
arm64v1mingw=13af359c75b4a7c830dbfe8ad68c5cea6e6cee548c9a23785c856dc5a4a820b0
arm64v1linux=0aef89829de960790f86d511596b48492b2f19f80a0460fa33b4a8d4fff40f84
arm64v1musl=0aef89829de960790f86d511596b48492b2f19f80a0460fa33b4a8d4fff40f84
arm64v1glibc=0aef89829de960790f86d511596b48492b2f19f80a0460fa33b4a8d4fff40f84
arm32linux=7d92e0cd72a9381854649a79e34c38d4037c1e388dd7801008528c4e97981adc
arm32musl=7d92e0cd72a9381854649a79e34c38d4037c1e388dd7801008528c4e97981adc
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
