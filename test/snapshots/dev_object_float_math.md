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
x64mac=e7bd37f0ba748c34a0399ffd36caae8ff245263c62874abe1064c87ec51e1017
x64win=cbd041ee0373bf2e83dc0f87c9a6435ba8e8384afa292883163f45e54d6bf3f3
x64mingw=cbd041ee0373bf2e83dc0f87c9a6435ba8e8384afa292883163f45e54d6bf3f3
x64freebsd=328fdcaf8d8d9f1bb39fccf03da8e9b3519544761f6cb4b59b12f6377b684531
x64openbsd=42b5a1970d9651e2ba0fd39afd0bac56cc5c3c77ae76c31bdba043fbe07619b3
x64netbsd=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64musl=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64glibc=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64linux=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64elf=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64v1mac=e7bd37f0ba748c34a0399ffd36caae8ff245263c62874abe1064c87ec51e1017
x64v1win=cbd041ee0373bf2e83dc0f87c9a6435ba8e8384afa292883163f45e54d6bf3f3
x64v1mingw=cbd041ee0373bf2e83dc0f87c9a6435ba8e8384afa292883163f45e54d6bf3f3
x64v1freebsd=328fdcaf8d8d9f1bb39fccf03da8e9b3519544761f6cb4b59b12f6377b684531
x64v1openbsd=42b5a1970d9651e2ba0fd39afd0bac56cc5c3c77ae76c31bdba043fbe07619b3
x64v1netbsd=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64v1musl=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64v1glibc=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64v1linux=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
x64v1elf=7d8d7d24e59459eb2f182dae8677cc8d386bbf6a36719f546598ab0c884ba8ff
arm64mac=d05efdf0e5dc1157651d7b1a1d4f753e57283822de97e20bc55ee41f547ec9ed
arm64win=bae70804ff50338d9790e666a6c8bf8b2a84ccbf09115eadb131ae1d5372aad1
arm64mingw=bae70804ff50338d9790e666a6c8bf8b2a84ccbf09115eadb131ae1d5372aad1
arm64linux=517842a16e35240b2f52d7eb8d92de37681f5b19e87db9bf0408a342bd3c5248
arm64musl=517842a16e35240b2f52d7eb8d92de37681f5b19e87db9bf0408a342bd3c5248
arm64glibc=517842a16e35240b2f52d7eb8d92de37681f5b19e87db9bf0408a342bd3c5248
arm64v1win=bae70804ff50338d9790e666a6c8bf8b2a84ccbf09115eadb131ae1d5372aad1
arm64v1mingw=bae70804ff50338d9790e666a6c8bf8b2a84ccbf09115eadb131ae1d5372aad1
arm64v1linux=517842a16e35240b2f52d7eb8d92de37681f5b19e87db9bf0408a342bd3c5248
arm64v1musl=517842a16e35240b2f52d7eb8d92de37681f5b19e87db9bf0408a342bd3c5248
arm64v1glibc=517842a16e35240b2f52d7eb8d92de37681f5b19e87db9bf0408a342bd3c5248
arm32linux=d333767ef7c6cd19d50aaf73a913889554107c98d21a8763da12dff8875dee8f
arm32musl=d333767ef7c6cd19d50aaf73a913889554107c98d21a8763da12dff8875dee8f
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
