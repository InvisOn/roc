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
x64mac=72cce701ce7b6735df672689d9315e8c679ddf792b894a8bdd9a869e6d4b81e4
x64win=bfa5db0632bf751b72b5095a263c5829497919649916231b99191a6e109a42df
x64mingw=bfa5db0632bf751b72b5095a263c5829497919649916231b99191a6e109a42df
x64freebsd=3e385917fd567ea7b4c5591e77a8282221390368de2995b4594f5dbf0868ee2e
x64openbsd=5d54f37730266b73c31e40a9eb8d1c1de74e61063af1819a8d092b81693967b0
x64netbsd=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64musl=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64glibc=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64linux=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64elf=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64v1mac=72cce701ce7b6735df672689d9315e8c679ddf792b894a8bdd9a869e6d4b81e4
x64v1win=bfa5db0632bf751b72b5095a263c5829497919649916231b99191a6e109a42df
x64v1mingw=bfa5db0632bf751b72b5095a263c5829497919649916231b99191a6e109a42df
x64v1freebsd=3e385917fd567ea7b4c5591e77a8282221390368de2995b4594f5dbf0868ee2e
x64v1openbsd=5d54f37730266b73c31e40a9eb8d1c1de74e61063af1819a8d092b81693967b0
x64v1netbsd=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64v1musl=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64v1glibc=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64v1linux=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
x64v1elf=aca0e2a20d4a08b212436ec112519157d307e31c39032c166cacd29b08d9151e
arm64mac=2cd0afec3ff1b6ff722a91cd43be13b23e60af2b17f926af5340171dcda35033
arm64win=d62f1862eefddd34343a89f5d2377c227204530c78da2a89be934862904543ca
arm64mingw=d62f1862eefddd34343a89f5d2377c227204530c78da2a89be934862904543ca
arm64linux=aa9658d3d04ca5c7088dbeba6a96b9b8ed5262b4ecdd83445fe5d6aeb5549e98
arm64musl=aa9658d3d04ca5c7088dbeba6a96b9b8ed5262b4ecdd83445fe5d6aeb5549e98
arm64glibc=aa9658d3d04ca5c7088dbeba6a96b9b8ed5262b4ecdd83445fe5d6aeb5549e98
arm64v1win=d62f1862eefddd34343a89f5d2377c227204530c78da2a89be934862904543ca
arm64v1mingw=d62f1862eefddd34343a89f5d2377c227204530c78da2a89be934862904543ca
arm64v1linux=aa9658d3d04ca5c7088dbeba6a96b9b8ed5262b4ecdd83445fe5d6aeb5549e98
arm64v1musl=aa9658d3d04ca5c7088dbeba6a96b9b8ed5262b4ecdd83445fe5d6aeb5549e98
arm64v1glibc=aa9658d3d04ca5c7088dbeba6a96b9b8ed5262b4ecdd83445fe5d6aeb5549e98
arm32linux=f307406575bfda46883e60d0638f75f68b689b93317868b775c6fe4f343463f1
arm32musl=f307406575bfda46883e60d0638f75f68b689b93317868b775c6fe4f343463f1
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
