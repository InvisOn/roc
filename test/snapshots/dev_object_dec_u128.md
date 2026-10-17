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
x64mac=c16fc87b346bbe4220948bcf0fae63ba9713ae3948dccf787d17cd9822e44582
x64win=47dd2fd9144cfbd879b9c5cdde3a6666370c38f560aa052ba99ad2320dfdf7b2
x64mingw=47dd2fd9144cfbd879b9c5cdde3a6666370c38f560aa052ba99ad2320dfdf7b2
x64freebsd=dde90e5ef632de12b160fa2487db55159861ff25242665cdb01ca1fc77f42da3
x64openbsd=c1a876bff55d92212354df438e1a07c8470dd98be3b51657bc1fea78a95f5330
x64netbsd=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64musl=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64glibc=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64linux=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64elf=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64v1mac=c16fc87b346bbe4220948bcf0fae63ba9713ae3948dccf787d17cd9822e44582
x64v1win=47dd2fd9144cfbd879b9c5cdde3a6666370c38f560aa052ba99ad2320dfdf7b2
x64v1mingw=47dd2fd9144cfbd879b9c5cdde3a6666370c38f560aa052ba99ad2320dfdf7b2
x64v1freebsd=dde90e5ef632de12b160fa2487db55159861ff25242665cdb01ca1fc77f42da3
x64v1openbsd=c1a876bff55d92212354df438e1a07c8470dd98be3b51657bc1fea78a95f5330
x64v1netbsd=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64v1musl=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64v1glibc=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64v1linux=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
x64v1elf=af40b026c4e5de3f327707c94167ee0bc202e68625964556370ed498789c51cd
arm64mac=84fd155afb67a48b90e637d7702002519b7c19cfb1b39326380c531e01634d0d
arm64win=37e7765fe44093df859c7542a774c0f8a35087f1d4288b5134f3a779bc1bc747
arm64mingw=37e7765fe44093df859c7542a774c0f8a35087f1d4288b5134f3a779bc1bc747
arm64linux=b1dd8d9b24e9d9909d4a75a8d8659e0d7e8e3b631fb7c192d61e2943f882d5b2
arm64musl=b1dd8d9b24e9d9909d4a75a8d8659e0d7e8e3b631fb7c192d61e2943f882d5b2
arm64glibc=b1dd8d9b24e9d9909d4a75a8d8659e0d7e8e3b631fb7c192d61e2943f882d5b2
arm64v1win=37e7765fe44093df859c7542a774c0f8a35087f1d4288b5134f3a779bc1bc747
arm64v1mingw=37e7765fe44093df859c7542a774c0f8a35087f1d4288b5134f3a779bc1bc747
arm64v1linux=b1dd8d9b24e9d9909d4a75a8d8659e0d7e8e3b631fb7c192d61e2943f882d5b2
arm64v1musl=b1dd8d9b24e9d9909d4a75a8d8659e0d7e8e3b631fb7c192d61e2943f882d5b2
arm64v1glibc=b1dd8d9b24e9d9909d4a75a8d8659e0d7e8e3b631fb7c192d61e2943f882d5b2
arm32linux=b0a81852d80b2dcafa009ccc7efd62a092d5fd89c242e729a60082ecb2d32a48
arm32musl=b0a81852d80b2dcafa009ccc7efd62a092d5fd89c242e729a60082ecb2d32a48
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
