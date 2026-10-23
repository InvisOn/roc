# META
~~~ini
description=Dec, I128 and U128 arithmetic with 16-byte arguments and a tuple return
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : Dec, I128, U128 -> (Dec, I128, U128)
main = |d, i, u| {
    dec = d * 1.5 + d / 3.0 - 0.25
    wide = i * i - i // 7 + 5
    unsigned = u * 3 + u % 11 - u // 13
    (dec, wide, unsigned)
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : Dec, I128, U128 -> (Dec, I128, U128) }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : Dec, I128, U128 -> (Dec, I128, U128)
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |d, i, u| {
	dec = d * 1.5 + d / 3 - 0.25
	wide = i * i - i // 7 + 5
	unsigned = u * 3 + u % 11 - u // 13
	(dec, wide, unsigned)
}

~~~
# DEV OUTPUT
~~~ini
x64mac=ca9712eb6b313b48c0ee5721ff0852629560a22e321ee7ee90fa4341c23aee1e
x64win=f881a0bb890ac632659bde14ce7214ee92d5f6517f385373a42a602f9d48a4b2
x64mingw=f881a0bb890ac632659bde14ce7214ee92d5f6517f385373a42a602f9d48a4b2
x64freebsd=5abf62fd6977b9f825c9c5c661b8f91398cfc33315627ed7142e9b590e27ce00
x64openbsd=61ffc29461c82ee170b491da477a35b7f769e0cd924d3e3a7ff150810cf3f2a8
x64netbsd=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64musl=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64glibc=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64linux=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64elf=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64v1mac=ca9712eb6b313b48c0ee5721ff0852629560a22e321ee7ee90fa4341c23aee1e
x64v1win=f881a0bb890ac632659bde14ce7214ee92d5f6517f385373a42a602f9d48a4b2
x64v1mingw=f881a0bb890ac632659bde14ce7214ee92d5f6517f385373a42a602f9d48a4b2
x64v1freebsd=5abf62fd6977b9f825c9c5c661b8f91398cfc33315627ed7142e9b590e27ce00
x64v1openbsd=61ffc29461c82ee170b491da477a35b7f769e0cd924d3e3a7ff150810cf3f2a8
x64v1netbsd=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64v1musl=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64v1glibc=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64v1linux=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
x64v1elf=6302eb6ac030fd5f0d325009f946436a68f676d0f5d7bdf0f25e5025a1ca2acd
arm64mac=0959b6f3da98f0e15c844bfc673602f94861081d34c756a894fe061bb3687e65
arm64win=c3c642103ff2f2410310877fb1699bcfb6efdd88d6b9d53857e44280b523ff17
arm64mingw=c3c642103ff2f2410310877fb1699bcfb6efdd88d6b9d53857e44280b523ff17
arm64linux=d4afe7df388e64e2574494acd6446d8a38fd2ce2530957dd64397ebf67f8dffd
arm64musl=d4afe7df388e64e2574494acd6446d8a38fd2ce2530957dd64397ebf67f8dffd
arm64glibc=d4afe7df388e64e2574494acd6446d8a38fd2ce2530957dd64397ebf67f8dffd
arm64v1win=c3c642103ff2f2410310877fb1699bcfb6efdd88d6b9d53857e44280b523ff17
arm64v1mingw=c3c642103ff2f2410310877fb1699bcfb6efdd88d6b9d53857e44280b523ff17
arm64v1linux=d4afe7df388e64e2574494acd6446d8a38fd2ce2530957dd64397ebf67f8dffd
arm64v1musl=d4afe7df388e64e2574494acd6446d8a38fd2ce2530957dd64397ebf67f8dffd
arm64v1glibc=d4afe7df388e64e2574494acd6446d8a38fd2ce2530957dd64397ebf67f8dffd
arm32linux=bc74321ee8d6f50ffd318175d476d38551d66c1dce0374b9c85cad2324e25aa4
arm32musl=bc74321ee8d6f50ffd318175d476d38551d66c1dce0374b9c85cad2324e25aa4
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
