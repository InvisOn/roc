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
x64mac=23b155bb873713688f96f3174463a19050d1652ce0ac058a1a41c92d27bce1c4
x64win=746ad437b719c2a568558760cddc0cc02055e56df809562b549a82ea6d6e88e6
x64mingw=746ad437b719c2a568558760cddc0cc02055e56df809562b549a82ea6d6e88e6
x64freebsd=44718ea284ccb2c95ab85b862a401bab95051ec6f73af980700317bc7ca2569e
x64openbsd=cd1d065fcfc7d1f8c8e2bce48a6da3caa50bf7f64352baf040f6b030c1ccc248
x64netbsd=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64musl=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64glibc=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64linux=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64elf=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64v1mac=23b155bb873713688f96f3174463a19050d1652ce0ac058a1a41c92d27bce1c4
x64v1win=746ad437b719c2a568558760cddc0cc02055e56df809562b549a82ea6d6e88e6
x64v1mingw=746ad437b719c2a568558760cddc0cc02055e56df809562b549a82ea6d6e88e6
x64v1freebsd=44718ea284ccb2c95ab85b862a401bab95051ec6f73af980700317bc7ca2569e
x64v1openbsd=cd1d065fcfc7d1f8c8e2bce48a6da3caa50bf7f64352baf040f6b030c1ccc248
x64v1netbsd=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64v1musl=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64v1glibc=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64v1linux=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
x64v1elf=fb2a4ea9b63925d27d3448693e36478e592d68b81f24f7b0372ebfc32ea13385
arm64mac=37e6aa7e981eea1d77954d48973be71503304d73e03034904cfc92f031ff20a6
arm64win=7a024425e669499201fc4d2a034f6c1126d9775f2e6dcdb5d909f23ac58c6ec9
arm64mingw=7a024425e669499201fc4d2a034f6c1126d9775f2e6dcdb5d909f23ac58c6ec9
arm64linux=981c91a0ee13f0bf154a5951f9290fdc9b0acbefe5a61167bb303fe569f712ee
arm64musl=981c91a0ee13f0bf154a5951f9290fdc9b0acbefe5a61167bb303fe569f712ee
arm64glibc=981c91a0ee13f0bf154a5951f9290fdc9b0acbefe5a61167bb303fe569f712ee
arm64v1win=7a024425e669499201fc4d2a034f6c1126d9775f2e6dcdb5d909f23ac58c6ec9
arm64v1mingw=7a024425e669499201fc4d2a034f6c1126d9775f2e6dcdb5d909f23ac58c6ec9
arm64v1linux=981c91a0ee13f0bf154a5951f9290fdc9b0acbefe5a61167bb303fe569f712ee
arm64v1musl=981c91a0ee13f0bf154a5951f9290fdc9b0acbefe5a61167bb303fe569f712ee
arm64v1glibc=981c91a0ee13f0bf154a5951f9290fdc9b0acbefe5a61167bb303fe569f712ee
arm32linux=90c1409bca1db96a24c4682e5b3acdc2871eb5a542822eb52077f04b0184c0af
arm32musl=90c1409bca1db96a24c4682e5b3acdc2871eb5a542822eb52077f04b0184c0af
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
