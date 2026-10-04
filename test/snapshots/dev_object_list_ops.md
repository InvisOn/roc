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
x64mac=acf9c54dced90c3fbc6ed83612f4d72ed9222dbf28f20947d47775f3b8b6175e
x64win=28f9a63c8b8ac587606257aa0b6e394a0427e263d6752db2b21c3fe52bbdcd9e
x64mingw=28f9a63c8b8ac587606257aa0b6e394a0427e263d6752db2b21c3fe52bbdcd9e
x64freebsd=7b6c36a094493020513d4358d93888dda66df78d3e3985d31eeda66f99958f54
x64openbsd=d5e26d61e90b31c3dfeeeed17a28f070d2ebd91f3f78f6936941d6d6f4ac441f
x64netbsd=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64musl=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64glibc=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64linux=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64elf=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64v1mac=acf9c54dced90c3fbc6ed83612f4d72ed9222dbf28f20947d47775f3b8b6175e
x64v1win=28f9a63c8b8ac587606257aa0b6e394a0427e263d6752db2b21c3fe52bbdcd9e
x64v1mingw=28f9a63c8b8ac587606257aa0b6e394a0427e263d6752db2b21c3fe52bbdcd9e
x64v1freebsd=7b6c36a094493020513d4358d93888dda66df78d3e3985d31eeda66f99958f54
x64v1openbsd=d5e26d61e90b31c3dfeeeed17a28f070d2ebd91f3f78f6936941d6d6f4ac441f
x64v1netbsd=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64v1musl=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64v1glibc=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64v1linux=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
x64v1elf=2e7c9ce605dd27b959042e635983e233161f1e4b48e41e815dc360335f3e8060
arm64mac=ddf08c29c9df5a0612c5f7972ec0b7601a0e72c5bc1b070c54951985f1962c80
arm64win=1f138e1815cdb67e1c7f3ef05f4b91fd5584596be77df2520e4e0048e8be45a5
arm64mingw=1f138e1815cdb67e1c7f3ef05f4b91fd5584596be77df2520e4e0048e8be45a5
arm64linux=0cf881f6c464df645692350574db9d7a54643aee21066b8d85f5c3d8ca8311e5
arm64musl=0cf881f6c464df645692350574db9d7a54643aee21066b8d85f5c3d8ca8311e5
arm64glibc=0cf881f6c464df645692350574db9d7a54643aee21066b8d85f5c3d8ca8311e5
arm64v1win=1f138e1815cdb67e1c7f3ef05f4b91fd5584596be77df2520e4e0048e8be45a5
arm64v1mingw=1f138e1815cdb67e1c7f3ef05f4b91fd5584596be77df2520e4e0048e8be45a5
arm64v1linux=0cf881f6c464df645692350574db9d7a54643aee21066b8d85f5c3d8ca8311e5
arm64v1musl=0cf881f6c464df645692350574db9d7a54643aee21066b8d85f5c3d8ca8311e5
arm64v1glibc=0cf881f6c464df645692350574db9d7a54643aee21066b8d85f5c3d8ca8311e5
arm32linux=fcdcee8c8b211c77b6160319006a951e2d889e511ee7da51fc51bf2ec3c9cbc9
arm32musl=fcdcee8c8b211c77b6160319006a951e2d889e511ee7da51fc51bf2ec3c9cbc9
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
