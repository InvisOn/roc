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
x64mac=6c501d69529032871359762ab091b3096134e169386ebed93df49849c8fe6af2
x64win=d9715a3e6bfa4970b92efc16fc43e37eaa61ca6cac1bd3dd3a5e15004ad4c89b
x64mingw=d9715a3e6bfa4970b92efc16fc43e37eaa61ca6cac1bd3dd3a5e15004ad4c89b
x64freebsd=b1a20b0862c0f5fc71078d175e8ae38cd14515b40b44dcdaf9a2182ba0c90696
x64openbsd=cbcb8664b0c94c4d3f9f1193e80d0e276b636f37701d5ca7ee0ac208a6564c22
x64netbsd=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64musl=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64glibc=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64linux=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64elf=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64v1mac=6c501d69529032871359762ab091b3096134e169386ebed93df49849c8fe6af2
x64v1win=d9715a3e6bfa4970b92efc16fc43e37eaa61ca6cac1bd3dd3a5e15004ad4c89b
x64v1mingw=d9715a3e6bfa4970b92efc16fc43e37eaa61ca6cac1bd3dd3a5e15004ad4c89b
x64v1freebsd=b1a20b0862c0f5fc71078d175e8ae38cd14515b40b44dcdaf9a2182ba0c90696
x64v1openbsd=cbcb8664b0c94c4d3f9f1193e80d0e276b636f37701d5ca7ee0ac208a6564c22
x64v1netbsd=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64v1musl=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64v1glibc=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64v1linux=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
x64v1elf=c28d1586fb30fcc3d6774dbcbdad89e4adff2426355fd3d05f47117a35f802c5
arm64mac=dd91ee943d5632e433ff151aa3598b073f7efbdee8acf298f7c4549b9e1e3ded
arm64win=a6008c63fdb70bc122c690848cdd0d41c2867ddf2c77ba8bcbab95e25a9a4380
arm64mingw=a6008c63fdb70bc122c690848cdd0d41c2867ddf2c77ba8bcbab95e25a9a4380
arm64linux=4c7a98fcbd709c7c83256ba3303038a3b127fbcdb29131289897684d98d02187
arm64musl=4c7a98fcbd709c7c83256ba3303038a3b127fbcdb29131289897684d98d02187
arm64glibc=4c7a98fcbd709c7c83256ba3303038a3b127fbcdb29131289897684d98d02187
arm64v1win=a6008c63fdb70bc122c690848cdd0d41c2867ddf2c77ba8bcbab95e25a9a4380
arm64v1mingw=a6008c63fdb70bc122c690848cdd0d41c2867ddf2c77ba8bcbab95e25a9a4380
arm64v1linux=4c7a98fcbd709c7c83256ba3303038a3b127fbcdb29131289897684d98d02187
arm64v1musl=4c7a98fcbd709c7c83256ba3303038a3b127fbcdb29131289897684d98d02187
arm64v1glibc=4c7a98fcbd709c7c83256ba3303038a3b127fbcdb29131289897684d98d02187
arm32linux=41dfcc7d91412dce0aa35ec39ecb5c1cca397cc5f463bed93dd8736b403be71f
arm32musl=41dfcc7d91412dce0aa35ec39ecb5c1cca397cc5f463bed93dd8736b403be71f
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
