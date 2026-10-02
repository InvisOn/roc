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
x64mac=905a13904c1ae1de53fa7459190d92760fa628e373280aff48a00996bf1259be
x64win=55696b5a5d5a8c740e7fa558c7fa9f6139032b184b1dc4b5f1e9157813644d30
x64mingw=55696b5a5d5a8c740e7fa558c7fa9f6139032b184b1dc4b5f1e9157813644d30
x64freebsd=0c42ba67687e76bf99c246ba5ac33c5dc882bff14d89f7323f3040dafb20f487
x64openbsd=6a261abd3ccc049ab6f88badc840cefc6a0a95a1b1f224c9e7b086c826937287
x64netbsd=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64musl=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64glibc=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64linux=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64elf=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64v1mac=905a13904c1ae1de53fa7459190d92760fa628e373280aff48a00996bf1259be
x64v1win=55696b5a5d5a8c740e7fa558c7fa9f6139032b184b1dc4b5f1e9157813644d30
x64v1mingw=55696b5a5d5a8c740e7fa558c7fa9f6139032b184b1dc4b5f1e9157813644d30
x64v1freebsd=0c42ba67687e76bf99c246ba5ac33c5dc882bff14d89f7323f3040dafb20f487
x64v1openbsd=6a261abd3ccc049ab6f88badc840cefc6a0a95a1b1f224c9e7b086c826937287
x64v1netbsd=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64v1musl=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64v1glibc=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64v1linux=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
x64v1elf=d3256ad7e2ab5b330fdf61a0ead44a36e5aa2db9f202a1c4841523d8a3f1f324
arm64mac=878c078b4b3358d5bd9c7cfe5ef32107a9b392a1c6897fc334bf54f61d49b4a5
arm64win=ee8690fd4354843b31dcf04aa13fcebaddecd766d258257708e28c1350e014dd
arm64mingw=ee8690fd4354843b31dcf04aa13fcebaddecd766d258257708e28c1350e014dd
arm64linux=3d300e502f3ddd5db3c3413db70d7517e91ebff2fc0882717745f43d81a14ae5
arm64musl=3d300e502f3ddd5db3c3413db70d7517e91ebff2fc0882717745f43d81a14ae5
arm64glibc=3d300e502f3ddd5db3c3413db70d7517e91ebff2fc0882717745f43d81a14ae5
arm64v1win=ee8690fd4354843b31dcf04aa13fcebaddecd766d258257708e28c1350e014dd
arm64v1mingw=ee8690fd4354843b31dcf04aa13fcebaddecd766d258257708e28c1350e014dd
arm64v1linux=3d300e502f3ddd5db3c3413db70d7517e91ebff2fc0882717745f43d81a14ae5
arm64v1musl=3d300e502f3ddd5db3c3413db70d7517e91ebff2fc0882717745f43d81a14ae5
arm64v1glibc=3d300e502f3ddd5db3c3413db70d7517e91ebff2fc0882717745f43d81a14ae5
arm32linux=75f6a3f7e578e8063a5c6849c01fb8c66e96dc800351016ecb33aa869b71c25b
arm32musl=75f6a3f7e578e8063a5c6849c01fb8c66e96dc800351016ecb33aa869b71c25b
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
