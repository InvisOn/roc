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
x64mac=b5b411be7361e3872b09f01d866d83e391798c1b6efee74e67044d1fb73ab775
x64win=8f0d5f3ab46b11a6883d129d0f72785fe511db739343285ec2503883b8771930
x64mingw=8f0d5f3ab46b11a6883d129d0f72785fe511db739343285ec2503883b8771930
x64freebsd=2d44a610228e5c47600a19eddf6d4b5ce004fb8b82ffc42bdee310221ab61dea
x64openbsd=0e85d2e73b48ff75c607af98579a90f4891ca2de0f6f16d9a15e130057643b73
x64netbsd=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64musl=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64glibc=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64linux=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64elf=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64v1mac=b5b411be7361e3872b09f01d866d83e391798c1b6efee74e67044d1fb73ab775
x64v1win=8f0d5f3ab46b11a6883d129d0f72785fe511db739343285ec2503883b8771930
x64v1mingw=8f0d5f3ab46b11a6883d129d0f72785fe511db739343285ec2503883b8771930
x64v1freebsd=2d44a610228e5c47600a19eddf6d4b5ce004fb8b82ffc42bdee310221ab61dea
x64v1openbsd=0e85d2e73b48ff75c607af98579a90f4891ca2de0f6f16d9a15e130057643b73
x64v1netbsd=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64v1musl=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64v1glibc=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64v1linux=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
x64v1elf=1a2107c5335b4562024c2caec674b9e93a9ec6fca062fc20cdc4d2a87a3d268a
arm64mac=0b0629dc362107e4d647da580bb0a92e94833ce9bac7ba361f2a2a84a859a7c1
arm64win=d208d812ddbbb47d8147eac2fc19f6bfca02c788e0cbdad4b2fffe78d1a847ee
arm64mingw=d208d812ddbbb47d8147eac2fc19f6bfca02c788e0cbdad4b2fffe78d1a847ee
arm64linux=2c1f5437f0ea03b023e92e2aae0b7f49fb9e5cd27fd40cc0142d3104beb9eedb
arm64musl=2c1f5437f0ea03b023e92e2aae0b7f49fb9e5cd27fd40cc0142d3104beb9eedb
arm64glibc=2c1f5437f0ea03b023e92e2aae0b7f49fb9e5cd27fd40cc0142d3104beb9eedb
arm64v1win=d208d812ddbbb47d8147eac2fc19f6bfca02c788e0cbdad4b2fffe78d1a847ee
arm64v1mingw=d208d812ddbbb47d8147eac2fc19f6bfca02c788e0cbdad4b2fffe78d1a847ee
arm64v1linux=2c1f5437f0ea03b023e92e2aae0b7f49fb9e5cd27fd40cc0142d3104beb9eedb
arm64v1musl=2c1f5437f0ea03b023e92e2aae0b7f49fb9e5cd27fd40cc0142d3104beb9eedb
arm64v1glibc=2c1f5437f0ea03b023e92e2aae0b7f49fb9e5cd27fd40cc0142d3104beb9eedb
arm32linux=NOT_IMPLEMENTED
arm32musl=NOT_IMPLEMENTED
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
