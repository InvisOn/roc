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
x64mac=2a97d1669cdc1ced38960bdfa01d49f24d0ea9cd283c0c2a8c1667c2f312341f
x64win=090496d9c6151e975806896272fe09455c92eaffa1335bd0e0e83c52bb8cfece
x64mingw=090496d9c6151e975806896272fe09455c92eaffa1335bd0e0e83c52bb8cfece
x64freebsd=c4114fde6b4f143819b1085ca786ce7cb6d8813e6a3aadfdbc8b4002bffd7f31
x64openbsd=e6c4a613eeb404eab708aee93dd864ea23dd5c5ab7ab43f0696f06cb70b7ba84
x64netbsd=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64musl=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64glibc=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64linux=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64elf=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64v1mac=2a97d1669cdc1ced38960bdfa01d49f24d0ea9cd283c0c2a8c1667c2f312341f
x64v1win=090496d9c6151e975806896272fe09455c92eaffa1335bd0e0e83c52bb8cfece
x64v1mingw=090496d9c6151e975806896272fe09455c92eaffa1335bd0e0e83c52bb8cfece
x64v1freebsd=c4114fde6b4f143819b1085ca786ce7cb6d8813e6a3aadfdbc8b4002bffd7f31
x64v1openbsd=e6c4a613eeb404eab708aee93dd864ea23dd5c5ab7ab43f0696f06cb70b7ba84
x64v1netbsd=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64v1musl=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64v1glibc=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64v1linux=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
x64v1elf=303a29f249dadfadb05ccea631d287fb41ebaa73d0ae0ad70bf4bb118237dc56
arm64mac=641c6de1c849ad3c01f5e52f55e887a4fb44a7eb710d83dc7b868f1af3264fef
arm64win=674a803215978de9af311c286c6b4ddab9d24562b3d838906e81de67a31e8efe
arm64mingw=674a803215978de9af311c286c6b4ddab9d24562b3d838906e81de67a31e8efe
arm64linux=01b2909561dbb251d60f85a76ec944e29081192c4ead4969dd8db6e64dc11379
arm64musl=01b2909561dbb251d60f85a76ec944e29081192c4ead4969dd8db6e64dc11379
arm64glibc=01b2909561dbb251d60f85a76ec944e29081192c4ead4969dd8db6e64dc11379
arm64v1win=674a803215978de9af311c286c6b4ddab9d24562b3d838906e81de67a31e8efe
arm64v1mingw=674a803215978de9af311c286c6b4ddab9d24562b3d838906e81de67a31e8efe
arm64v1linux=01b2909561dbb251d60f85a76ec944e29081192c4ead4969dd8db6e64dc11379
arm64v1musl=01b2909561dbb251d60f85a76ec944e29081192c4ead4969dd8db6e64dc11379
arm64v1glibc=01b2909561dbb251d60f85a76ec944e29081192c4ead4969dd8db6e64dc11379
arm32linux=75066abfc9696a3b4f55dc440f01efb873fc2ded92e62797f8e5629235eef36f
arm32musl=75066abfc9696a3b4f55dc440f01efb873fc2ded92e62797f8e5629235eef36f
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
