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
x64mac=983c16f326e89d978dcb797e4c3c5e7fe48f3bcd775f85c7f02dc6588e6b5590
x64win=e15b4baa3a14fd030d7443a06b6280c112741f603840b36d6ee5095add429c7b
x64mingw=e15b4baa3a14fd030d7443a06b6280c112741f603840b36d6ee5095add429c7b
x64freebsd=ca1cc139aaaa678e3d9c371ed80126248f6762e704c547cbc31f0681c02d8566
x64openbsd=0c76c573647e3379919e22b5beda098ee1b2a0ed232f234a5e6ac1a05adb34cb
x64netbsd=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64musl=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64glibc=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64linux=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64elf=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64v1mac=983c16f326e89d978dcb797e4c3c5e7fe48f3bcd775f85c7f02dc6588e6b5590
x64v1win=e15b4baa3a14fd030d7443a06b6280c112741f603840b36d6ee5095add429c7b
x64v1mingw=e15b4baa3a14fd030d7443a06b6280c112741f603840b36d6ee5095add429c7b
x64v1freebsd=ca1cc139aaaa678e3d9c371ed80126248f6762e704c547cbc31f0681c02d8566
x64v1openbsd=0c76c573647e3379919e22b5beda098ee1b2a0ed232f234a5e6ac1a05adb34cb
x64v1netbsd=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64v1musl=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64v1glibc=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64v1linux=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
x64v1elf=2501bfb2304b4ce2d8cb428baad0d4323681a7912dc7986c66e61b612d366be7
arm64mac=a5a59545da59316711ca45c26b6c51566e5b577d0b17e316cb995ffc6f1aa7ce
arm64win=fed8a5872c5c97a5b5350a2d677d85700b78bdf228f2e9b09de64d4c47a1067a
arm64mingw=fed8a5872c5c97a5b5350a2d677d85700b78bdf228f2e9b09de64d4c47a1067a
arm64linux=08fa083835d9416d9174b95d17b67d05788d66fef0f5305aa4432c41d047dafa
arm64musl=08fa083835d9416d9174b95d17b67d05788d66fef0f5305aa4432c41d047dafa
arm64glibc=08fa083835d9416d9174b95d17b67d05788d66fef0f5305aa4432c41d047dafa
arm64v1win=fed8a5872c5c97a5b5350a2d677d85700b78bdf228f2e9b09de64d4c47a1067a
arm64v1mingw=fed8a5872c5c97a5b5350a2d677d85700b78bdf228f2e9b09de64d4c47a1067a
arm64v1linux=08fa083835d9416d9174b95d17b67d05788d66fef0f5305aa4432c41d047dafa
arm64v1musl=08fa083835d9416d9174b95d17b67d05788d66fef0f5305aa4432c41d047dafa
arm64v1glibc=08fa083835d9416d9174b95d17b67d05788d66fef0f5305aa4432c41d047dafa
arm32linux=1455865c1d4e42abc28bb68c9ad54a8fa1d9a41f3064321358d157ad0b7e1901
arm32musl=1455865c1d4e42abc28bb68c9ad54a8fa1d9a41f3064321358d157ad0b7e1901
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
