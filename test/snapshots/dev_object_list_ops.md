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
x64mac=42b87647e0c081a5cef655181ed960039a2791e94b1c0cba81255154fdca836c
x64win=48cf9f7b569ea794ec01336f499dd2e6592f28b9338725498ea3b3f893a1257a
x64mingw=48cf9f7b569ea794ec01336f499dd2e6592f28b9338725498ea3b3f893a1257a
x64freebsd=55f7af050ea9b37c1ca003258f4631141700c14c05abf912b5971635cc88c3ad
x64openbsd=c23cee0c62c85219d5a4d67f44118ed617e408fa108a38d6fbe415703994045b
x64netbsd=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64musl=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64glibc=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64linux=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64elf=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64v1mac=42b87647e0c081a5cef655181ed960039a2791e94b1c0cba81255154fdca836c
x64v1win=48cf9f7b569ea794ec01336f499dd2e6592f28b9338725498ea3b3f893a1257a
x64v1mingw=48cf9f7b569ea794ec01336f499dd2e6592f28b9338725498ea3b3f893a1257a
x64v1freebsd=55f7af050ea9b37c1ca003258f4631141700c14c05abf912b5971635cc88c3ad
x64v1openbsd=c23cee0c62c85219d5a4d67f44118ed617e408fa108a38d6fbe415703994045b
x64v1netbsd=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64v1musl=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64v1glibc=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64v1linux=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
x64v1elf=8335ab196fe6a1f7f51345268b2ab704577ffb262b1fdc67cf34d8fdf7f4123e
arm64mac=bf2c82a20796c44ca6768938dbfd5a16ca4b1e03e5913b6f41471cbe48feadd0
arm64win=30f1669cb4e5d988b5d4a61ab64ed63933ce59dd99399af1962407fe20574610
arm64mingw=30f1669cb4e5d988b5d4a61ab64ed63933ce59dd99399af1962407fe20574610
arm64linux=89d98c08fcac3e8d1b63e5921a4e4cf93b10dfeae6cd7ffe544c52a4de1802cf
arm64musl=89d98c08fcac3e8d1b63e5921a4e4cf93b10dfeae6cd7ffe544c52a4de1802cf
arm64glibc=89d98c08fcac3e8d1b63e5921a4e4cf93b10dfeae6cd7ffe544c52a4de1802cf
arm64v1win=30f1669cb4e5d988b5d4a61ab64ed63933ce59dd99399af1962407fe20574610
arm64v1mingw=30f1669cb4e5d988b5d4a61ab64ed63933ce59dd99399af1962407fe20574610
arm64v1linux=89d98c08fcac3e8d1b63e5921a4e4cf93b10dfeae6cd7ffe544c52a4de1802cf
arm64v1musl=89d98c08fcac3e8d1b63e5921a4e4cf93b10dfeae6cd7ffe544c52a4de1802cf
arm64v1glibc=89d98c08fcac3e8d1b63e5921a4e4cf93b10dfeae6cd7ffe544c52a4de1802cf
arm32linux=654ae16cfeb67f17a347e99bc559c6767615f810442f62dc72f957b6b3f9ae67
arm32musl=654ae16cfeb67f17a347e99bc559c6767615f810442f62dc72f957b6b3f9ae67
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
