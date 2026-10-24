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
x64mac=224bcf82896ab55f686f44ed4e2654f60e209e3100bf83f521bfda488bfd67ff
x64win=e43a1bacc227d0057e07cc2b1db90a403d01984a72eca5a0c1ec9d73f26888a2
x64mingw=e43a1bacc227d0057e07cc2b1db90a403d01984a72eca5a0c1ec9d73f26888a2
x64freebsd=a899a24446245ebecff06010f7228300b07818427ed746dd0c4f80940188ed22
x64openbsd=dfbb451de43fea4675bd0a9051af5330fec12a1c00a6db25ac24b24adf13b7e2
x64netbsd=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64musl=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64glibc=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64linux=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64elf=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64v1mac=224bcf82896ab55f686f44ed4e2654f60e209e3100bf83f521bfda488bfd67ff
x64v1win=e43a1bacc227d0057e07cc2b1db90a403d01984a72eca5a0c1ec9d73f26888a2
x64v1mingw=e43a1bacc227d0057e07cc2b1db90a403d01984a72eca5a0c1ec9d73f26888a2
x64v1freebsd=a899a24446245ebecff06010f7228300b07818427ed746dd0c4f80940188ed22
x64v1openbsd=dfbb451de43fea4675bd0a9051af5330fec12a1c00a6db25ac24b24adf13b7e2
x64v1netbsd=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64v1musl=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64v1glibc=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64v1linux=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
x64v1elf=1d724aa967f3d9af36d95796178e7dff318838ca9260c5ec8251df53018539ed
arm64mac=e5b148bcd2bcd1eeedb1955e2923db5119fd8ee8f1d6348a6194694c79aefc54
arm64win=aafd6a533372f6f7de5551cf6bcc2b9592483884fee8e0065f136129e2003971
arm64mingw=aafd6a533372f6f7de5551cf6bcc2b9592483884fee8e0065f136129e2003971
arm64linux=f34fcf32a361af1bd533bb121888e0c7e16892f3a7f2444ed294823649c208fa
arm64musl=f34fcf32a361af1bd533bb121888e0c7e16892f3a7f2444ed294823649c208fa
arm64glibc=f34fcf32a361af1bd533bb121888e0c7e16892f3a7f2444ed294823649c208fa
arm64v1win=aafd6a533372f6f7de5551cf6bcc2b9592483884fee8e0065f136129e2003971
arm64v1mingw=aafd6a533372f6f7de5551cf6bcc2b9592483884fee8e0065f136129e2003971
arm64v1linux=f34fcf32a361af1bd533bb121888e0c7e16892f3a7f2444ed294823649c208fa
arm64v1musl=f34fcf32a361af1bd533bb121888e0c7e16892f3a7f2444ed294823649c208fa
arm64v1glibc=f34fcf32a361af1bd533bb121888e0c7e16892f3a7f2444ed294823649c208fa
arm32linux=d0fce32c7106f05212a9a197531a116bea08c99f354277564084f7e84cc32e02
arm32musl=d0fce32c7106f05212a9a197531a116bea08c99f354277564084f7e84cc32e02
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
