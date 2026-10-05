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
x64mac=0191601c7b2ad02b273fabe56bfa89d7009531c4f20256984087995e20dc9d91
x64win=bc23e3fa648053664361203456c32221db9f4d001c10572b9aa5e2624ad25571
x64mingw=bc23e3fa648053664361203456c32221db9f4d001c10572b9aa5e2624ad25571
x64freebsd=d314844361a5b878e852d4ab4ebb0cb0ec3235bd365b10bd53ba4f5f1366760c
x64openbsd=f680257f2e01e4c9667e4c951c13bf742a3c5fc8b56ce70f307d85e8bb8e7d36
x64netbsd=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64musl=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64glibc=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64linux=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64elf=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64v1mac=0191601c7b2ad02b273fabe56bfa89d7009531c4f20256984087995e20dc9d91
x64v1win=bc23e3fa648053664361203456c32221db9f4d001c10572b9aa5e2624ad25571
x64v1mingw=bc23e3fa648053664361203456c32221db9f4d001c10572b9aa5e2624ad25571
x64v1freebsd=d314844361a5b878e852d4ab4ebb0cb0ec3235bd365b10bd53ba4f5f1366760c
x64v1openbsd=f680257f2e01e4c9667e4c951c13bf742a3c5fc8b56ce70f307d85e8bb8e7d36
x64v1netbsd=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64v1musl=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64v1glibc=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64v1linux=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
x64v1elf=7c4de8bcd013d5ed7b11983817a87b6bc47938503f65ec05e911440d77c32d41
arm64mac=93a47e2c550a5c7c854d919c6a390c5f632bf8400a6d06ef94c9461479aa2823
arm64win=b5d5ddbac3c673e3b7dbf79fe05ea8a4b1f280f28ba1aa36f49ebb768fc77a6f
arm64mingw=b5d5ddbac3c673e3b7dbf79fe05ea8a4b1f280f28ba1aa36f49ebb768fc77a6f
arm64linux=1ca4ced27f31e4974ffa1a266ad772d5c0895f40d6458085456989f64bd94caf
arm64musl=1ca4ced27f31e4974ffa1a266ad772d5c0895f40d6458085456989f64bd94caf
arm64glibc=1ca4ced27f31e4974ffa1a266ad772d5c0895f40d6458085456989f64bd94caf
arm64v1win=b5d5ddbac3c673e3b7dbf79fe05ea8a4b1f280f28ba1aa36f49ebb768fc77a6f
arm64v1mingw=b5d5ddbac3c673e3b7dbf79fe05ea8a4b1f280f28ba1aa36f49ebb768fc77a6f
arm64v1linux=1ca4ced27f31e4974ffa1a266ad772d5c0895f40d6458085456989f64bd94caf
arm64v1musl=1ca4ced27f31e4974ffa1a266ad772d5c0895f40d6458085456989f64bd94caf
arm64v1glibc=1ca4ced27f31e4974ffa1a266ad772d5c0895f40d6458085456989f64bd94caf
arm32linux=4b49fb6b163c3205fa002335f2811265cf55899d320e84b93c2b1dd1a864890a
arm32musl=4b49fb6b163c3205fa002335f2811265cf55899d320e84b93c2b1dd1a864890a
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
