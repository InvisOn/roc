# META
~~~ini
description=List append, get, len and map with a closure capturing two locals
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : List(I64), I64, I64 -> I64
main = |xs, a, b| {
    scale = a * 2
    offset = b - 1
    ys = List.map(List.append(xs, a), |x| x * scale + offset)
    first =
        match List.get(ys, 0) {
            Ok(v) => v
            Err(_) => -1
        }
    first + U64.to_i64_wrap(List.len(ys))
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : List(I64), I64, I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : List(I64), I64, I64 -> I64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |xs, a, b| {
	scale = a * 2
	offset = b - 1
	ys = map(append(xs, a), |x| x * scale + offset)
	first = match get(ys, 0) {
		Ok(v) => v
		Err(_) => -1
	}
	first + to_i64_wrap(len(ys))
}

~~~
# DEV OUTPUT
~~~ini
x64mac=775670a5f1d3e021528d34835b4c4e24094f7151ceed3c8de4269fe5d470658a
x64win=7250c4d69f4cb33bd71d0783734a8ae2c3e3ca62ed601235ee3088063004df40
x64mingw=7250c4d69f4cb33bd71d0783734a8ae2c3e3ca62ed601235ee3088063004df40
x64freebsd=ba0631628d6d9ee5e9ddb156fca27ebb17baaf66d30011d1a6a32cc0bbd3abc9
x64openbsd=6e25405b8b9aadbe6cf430acbac3847ddfdba2bf572a545f55b4672a5755686f
x64netbsd=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64musl=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64glibc=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64linux=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64elf=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64v1mac=775670a5f1d3e021528d34835b4c4e24094f7151ceed3c8de4269fe5d470658a
x64v1win=7250c4d69f4cb33bd71d0783734a8ae2c3e3ca62ed601235ee3088063004df40
x64v1mingw=7250c4d69f4cb33bd71d0783734a8ae2c3e3ca62ed601235ee3088063004df40
x64v1freebsd=ba0631628d6d9ee5e9ddb156fca27ebb17baaf66d30011d1a6a32cc0bbd3abc9
x64v1openbsd=6e25405b8b9aadbe6cf430acbac3847ddfdba2bf572a545f55b4672a5755686f
x64v1netbsd=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64v1musl=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64v1glibc=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64v1linux=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
x64v1elf=4f88c6ab7e23d4de02cddbae69d4e346c8b384a1898b67e94c30282e304cd96b
arm64mac=c61ce979896868005235ebd7a765604d9571b4cd3c39e2e04fa60df86ddff402
arm64win=471e6bb865365f99bc866847c91ad8a0b426aa30e44b20a4beb7eadf2f659648
arm64mingw=471e6bb865365f99bc866847c91ad8a0b426aa30e44b20a4beb7eadf2f659648
arm64linux=25cb0e44ab416d552bfd473fc3bb17a647c8343ebe51c22d9676b5ac4e1620ce
arm64musl=25cb0e44ab416d552bfd473fc3bb17a647c8343ebe51c22d9676b5ac4e1620ce
arm64glibc=25cb0e44ab416d552bfd473fc3bb17a647c8343ebe51c22d9676b5ac4e1620ce
arm64v1win=471e6bb865365f99bc866847c91ad8a0b426aa30e44b20a4beb7eadf2f659648
arm64v1mingw=471e6bb865365f99bc866847c91ad8a0b426aa30e44b20a4beb7eadf2f659648
arm64v1linux=25cb0e44ab416d552bfd473fc3bb17a647c8343ebe51c22d9676b5ac4e1620ce
arm64v1musl=25cb0e44ab416d552bfd473fc3bb17a647c8343ebe51c22d9676b5ac4e1620ce
arm64v1glibc=25cb0e44ab416d552bfd473fc3bb17a647c8343ebe51c22d9676b5ac4e1620ce
arm32linux=2fce97afaae3bf0b1da1b5edf8886358c194e06796de188367502dd7d4125671
arm32musl=2fce97afaae3bf0b1da1b5edf8886358c194e06796de188367502dd7d4125671
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
