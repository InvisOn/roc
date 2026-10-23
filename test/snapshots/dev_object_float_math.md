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
x64mac=6ba3ec2b2c1aa47f8234ea382e4de5e7d92ca5a8ee70b490f01e84a1159e4827
x64win=05922182f77a697e57b42fcf76bfa6c89cb1ce7cc6706044c80e596d27938d2e
x64mingw=05922182f77a697e57b42fcf76bfa6c89cb1ce7cc6706044c80e596d27938d2e
x64freebsd=4699481e0db5f3742594dbf18fc93d865f472668769dd3e899694224e9d9e67a
x64openbsd=6eb879bd27a51d9fa0e1d67f70df4fb5919e747da28dfab1af75c155bc4b0d2f
x64netbsd=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64musl=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64glibc=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64linux=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64elf=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64v1mac=6ba3ec2b2c1aa47f8234ea382e4de5e7d92ca5a8ee70b490f01e84a1159e4827
x64v1win=05922182f77a697e57b42fcf76bfa6c89cb1ce7cc6706044c80e596d27938d2e
x64v1mingw=05922182f77a697e57b42fcf76bfa6c89cb1ce7cc6706044c80e596d27938d2e
x64v1freebsd=4699481e0db5f3742594dbf18fc93d865f472668769dd3e899694224e9d9e67a
x64v1openbsd=6eb879bd27a51d9fa0e1d67f70df4fb5919e747da28dfab1af75c155bc4b0d2f
x64v1netbsd=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64v1musl=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64v1glibc=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64v1linux=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
x64v1elf=a8fb33a61381e3564d8c418838dffe178f9aee8f9e5d852855f75c19d5fee81d
arm64mac=d430a98a1473621a6d926159a5fa88e0f8db6768e14085e7ef0cabe4c062d15c
arm64win=5e04b4052d5be4b37cb46246b7bf4862b35e754c0b52e97b8ff0bf079a455619
arm64mingw=5e04b4052d5be4b37cb46246b7bf4862b35e754c0b52e97b8ff0bf079a455619
arm64linux=5d909eabffced5dc358ad608c477598b0ec5319497c24cd20ac2981a53448f98
arm64musl=5d909eabffced5dc358ad608c477598b0ec5319497c24cd20ac2981a53448f98
arm64glibc=5d909eabffced5dc358ad608c477598b0ec5319497c24cd20ac2981a53448f98
arm64v1win=5e04b4052d5be4b37cb46246b7bf4862b35e754c0b52e97b8ff0bf079a455619
arm64v1mingw=5e04b4052d5be4b37cb46246b7bf4862b35e754c0b52e97b8ff0bf079a455619
arm64v1linux=5d909eabffced5dc358ad608c477598b0ec5319497c24cd20ac2981a53448f98
arm64v1musl=5d909eabffced5dc358ad608c477598b0ec5319497c24cd20ac2981a53448f98
arm64v1glibc=5d909eabffced5dc358ad608c477598b0ec5319497c24cd20ac2981a53448f98
arm32linux=c5922c14365d24929e850d898d79efb4e47a394922b08d8bc6cc0b13445438b8
arm32musl=c5922c14365d24929e850d898d79efb4e47a394922b08d8bc6cc0b13445438b8
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
