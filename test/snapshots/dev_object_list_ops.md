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
x64mac=0aeb20ec51cfe07dcd71ead9abac3f0083423f10ba5de6475b797c947c3cac0b
x64win=e3369809b54c4ca6e3796552df48d39cdc2e53dd51a0693091f957bb8d98e707
x64mingw=e3369809b54c4ca6e3796552df48d39cdc2e53dd51a0693091f957bb8d98e707
x64freebsd=abe497a3b0c12c017bfbf0ee55c14e892fe746db5ed5a116fac16501843b5398
x64openbsd=ad5519543337df6e0be6c2e61f872ad15b0169fb40fde0d598b7d94e21aed682
x64netbsd=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64musl=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64glibc=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64linux=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64elf=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64v1mac=0aeb20ec51cfe07dcd71ead9abac3f0083423f10ba5de6475b797c947c3cac0b
x64v1win=e3369809b54c4ca6e3796552df48d39cdc2e53dd51a0693091f957bb8d98e707
x64v1mingw=e3369809b54c4ca6e3796552df48d39cdc2e53dd51a0693091f957bb8d98e707
x64v1freebsd=abe497a3b0c12c017bfbf0ee55c14e892fe746db5ed5a116fac16501843b5398
x64v1openbsd=ad5519543337df6e0be6c2e61f872ad15b0169fb40fde0d598b7d94e21aed682
x64v1netbsd=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64v1musl=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64v1glibc=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64v1linux=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
x64v1elf=9a9173d6247eed6f6c668533febe846b4f507aaab911e4e06d0742fe657cbd37
arm64mac=ed6aa31f76ab5d2d37ea2ada95043ccd7c31a9426122629ef68b8ba6782bcf7e
arm64win=6fa530473bd6e2a0c9d0400d7a172606910fc19d25dd3ec6c5e95ba6852d74e3
arm64mingw=6fa530473bd6e2a0c9d0400d7a172606910fc19d25dd3ec6c5e95ba6852d74e3
arm64linux=e57e19a01862eea1c45fb75ddc26178dca219eeeb91b96e1d0ca8ea033df8a54
arm64musl=e57e19a01862eea1c45fb75ddc26178dca219eeeb91b96e1d0ca8ea033df8a54
arm64glibc=e57e19a01862eea1c45fb75ddc26178dca219eeeb91b96e1d0ca8ea033df8a54
arm64v1win=6fa530473bd6e2a0c9d0400d7a172606910fc19d25dd3ec6c5e95ba6852d74e3
arm64v1mingw=6fa530473bd6e2a0c9d0400d7a172606910fc19d25dd3ec6c5e95ba6852d74e3
arm64v1linux=e57e19a01862eea1c45fb75ddc26178dca219eeeb91b96e1d0ca8ea033df8a54
arm64v1musl=e57e19a01862eea1c45fb75ddc26178dca219eeeb91b96e1d0ca8ea033df8a54
arm64v1glibc=e57e19a01862eea1c45fb75ddc26178dca219eeeb91b96e1d0ca8ea033df8a54
arm32linux=1269c0ba9892e0dd73d08b1408b3d8e2ff49d8276699c9e2718e72e330e52b10
arm32musl=1269c0ba9892e0dd73d08b1408b3d8e2ff49d8276699c9e2718e72e330e52b10
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
