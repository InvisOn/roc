# META
~~~ini
description=F32/F64 arithmetic, comparisons, and F64 to I64 conversion in host-called functions
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : F64, F32, I64 -> I64
main = |x, y, n| {
    scaled = x * 2.5 - I64.to_f64(n) / 3.0
    narrowed = F32.to_f64(y * 1.5 + 0.25)
    total = if scaled > narrowed { scaled - narrowed } else { narrowed + scaled }
    F64.to_i64_wrap(total)
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : F64, F32, I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : F64, F32, I64 -> I64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |x, y, n| {
	scaled = x * 2.5 - to_f64(n) / 3
	narrowed = to_f64(y * 1.5 + 0.25)
	total = if (scaled > narrowed) {
		scaled - narrowed
	} else {
		narrowed + scaled
	}
	to_i64_wrap(total)
}

~~~
# DEV OUTPUT
~~~ini
x64mac=200bda3b60cbc02fe5d86b05de3292cf54f5793abe809edb878d247f55b4ec47
x64win=b59d80060b3252d38d661d458294663682cec18bc90db24444fcb2400f4c1ac0
x64mingw=b59d80060b3252d38d661d458294663682cec18bc90db24444fcb2400f4c1ac0
x64freebsd=a8ddc036e8fe1d6c08169f5e365d01db3063da4c54aa41b16560c61e01dffe31
x64openbsd=64dc8e4f4e2db11e95ae1c425ca0da1b7d5feed13a5ce302d14db356c52486eb
x64netbsd=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64musl=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64glibc=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64linux=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64elf=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64v1mac=200bda3b60cbc02fe5d86b05de3292cf54f5793abe809edb878d247f55b4ec47
x64v1win=b59d80060b3252d38d661d458294663682cec18bc90db24444fcb2400f4c1ac0
x64v1mingw=b59d80060b3252d38d661d458294663682cec18bc90db24444fcb2400f4c1ac0
x64v1freebsd=a8ddc036e8fe1d6c08169f5e365d01db3063da4c54aa41b16560c61e01dffe31
x64v1openbsd=64dc8e4f4e2db11e95ae1c425ca0da1b7d5feed13a5ce302d14db356c52486eb
x64v1netbsd=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64v1musl=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64v1glibc=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64v1linux=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
x64v1elf=9ae5da15918f7db9383b6fbef2ee68ff9661f87b7602b00496fd9aac50db34bc
arm64mac=faedeac9ed928b1c9c304f7a2ea8e9e3d7dcb0cc2f2951731f686f24dd4c0b9e
arm64win=485499d6e390a94def3f70db91f2980073823396a11cfc85094558ff11731707
arm64mingw=485499d6e390a94def3f70db91f2980073823396a11cfc85094558ff11731707
arm64linux=ad26b86cfc85be311f64abe4a7d3844e5c5b5265587a61a79affb312759963ba
arm64musl=ad26b86cfc85be311f64abe4a7d3844e5c5b5265587a61a79affb312759963ba
arm64glibc=ad26b86cfc85be311f64abe4a7d3844e5c5b5265587a61a79affb312759963ba
arm64v1win=485499d6e390a94def3f70db91f2980073823396a11cfc85094558ff11731707
arm64v1mingw=485499d6e390a94def3f70db91f2980073823396a11cfc85094558ff11731707
arm64v1linux=ad26b86cfc85be311f64abe4a7d3844e5c5b5265587a61a79affb312759963ba
arm64v1musl=ad26b86cfc85be311f64abe4a7d3844e5c5b5265587a61a79affb312759963ba
arm64v1glibc=ad26b86cfc85be311f64abe4a7d3844e5c5b5265587a61a79affb312759963ba
arm32linux=3aa20530bd3f1aec7cabef22b6ab20b2a2073007f3260cb5eca8359e79d025a9
arm32musl=3aa20530bd3f1aec7cabef22b6ab20b2a2073007f3260cb5eca8359e79d025a9
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
