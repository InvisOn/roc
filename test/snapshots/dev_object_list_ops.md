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
x64mac=b69730bcffdf745dca66f354c27edc6af113a4da366375a4d5481d0e6bddbad3
x64win=2d6e3ac296ddabe973f509e0124ca226b9aeaab49eb19e8172e5178535f0c5a0
x64mingw=2d6e3ac296ddabe973f509e0124ca226b9aeaab49eb19e8172e5178535f0c5a0
x64freebsd=da276024fa3f941033206b98e00194520794b4ecd11f9171d9a2932ad43ca0f1
x64openbsd=f980aacc2840b13cf38f6ad1204d4ef8d282eab4336efa540e325570d48f3dc1
x64netbsd=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64musl=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64glibc=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64linux=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64elf=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64v1mac=b69730bcffdf745dca66f354c27edc6af113a4da366375a4d5481d0e6bddbad3
x64v1win=2d6e3ac296ddabe973f509e0124ca226b9aeaab49eb19e8172e5178535f0c5a0
x64v1mingw=2d6e3ac296ddabe973f509e0124ca226b9aeaab49eb19e8172e5178535f0c5a0
x64v1freebsd=da276024fa3f941033206b98e00194520794b4ecd11f9171d9a2932ad43ca0f1
x64v1openbsd=f980aacc2840b13cf38f6ad1204d4ef8d282eab4336efa540e325570d48f3dc1
x64v1netbsd=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64v1musl=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64v1glibc=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64v1linux=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
x64v1elf=f46a5d8073f3a5aa11fcc43aa7e299b5d232429d70f5bac75722a52ee9f6e227
arm64mac=94953625f9f5b959c41d23c183993d308ab85f008b551e842a8bbf39a5dff5be
arm64win=b408129551800f600a43effb4649bf128591a48757e4ad8c4f585d72692d9afc
arm64mingw=b408129551800f600a43effb4649bf128591a48757e4ad8c4f585d72692d9afc
arm64linux=639ed409cab1a434fe74a4afd8458eb048b6d6ee0bd4702c40b1557d1cb12b10
arm64musl=639ed409cab1a434fe74a4afd8458eb048b6d6ee0bd4702c40b1557d1cb12b10
arm64glibc=639ed409cab1a434fe74a4afd8458eb048b6d6ee0bd4702c40b1557d1cb12b10
arm64v1win=b408129551800f600a43effb4649bf128591a48757e4ad8c4f585d72692d9afc
arm64v1mingw=b408129551800f600a43effb4649bf128591a48757e4ad8c4f585d72692d9afc
arm64v1linux=639ed409cab1a434fe74a4afd8458eb048b6d6ee0bd4702c40b1557d1cb12b10
arm64v1musl=639ed409cab1a434fe74a4afd8458eb048b6d6ee0bd4702c40b1557d1cb12b10
arm64v1glibc=639ed409cab1a434fe74a4afd8458eb048b6d6ee0bd4702c40b1557d1cb12b10
arm32linux=a70c2ca4cd4726705ec5f97bde265b6fc9b5860aaf9b3ff2d7cf49ea77d05449
arm32musl=a70c2ca4cd4726705ec5f97bde265b6fc9b5860aaf9b3ff2d7cf49ea77d05449
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
