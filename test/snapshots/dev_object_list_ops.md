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
x64mac=5d1378fa43b3306d1c913a01ebbabc35969f5af4795206f631038d978f774050
x64win=b423ab8c2005df381e66f2583311732649253a7060e5782eb85adbce4616d936
x64mingw=b423ab8c2005df381e66f2583311732649253a7060e5782eb85adbce4616d936
x64freebsd=284552bdd6f13552603ab9b558be7ca6afcd046f63b3694444544af3028a9fd7
x64openbsd=b00b8dfaad3ad78483f92d97b31d18376743338464ac2745d1603cdfa6ae89b3
x64netbsd=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64musl=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64glibc=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64linux=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64elf=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64v1mac=5d1378fa43b3306d1c913a01ebbabc35969f5af4795206f631038d978f774050
x64v1win=b423ab8c2005df381e66f2583311732649253a7060e5782eb85adbce4616d936
x64v1mingw=b423ab8c2005df381e66f2583311732649253a7060e5782eb85adbce4616d936
x64v1freebsd=284552bdd6f13552603ab9b558be7ca6afcd046f63b3694444544af3028a9fd7
x64v1openbsd=b00b8dfaad3ad78483f92d97b31d18376743338464ac2745d1603cdfa6ae89b3
x64v1netbsd=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64v1musl=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64v1glibc=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64v1linux=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
x64v1elf=1997f8659ad1fae0e71aaac7b68bae0ed644aa4edfc9404574429767fc660f14
arm64mac=8e31b1d2cb4a39d1abca446cb80caac6b1b1474cc5d01bc469c729ebeaddc118
arm64win=a5ca4a573b2e449865c831582398610993bf29278942527731afca9881ac81c6
arm64mingw=a5ca4a573b2e449865c831582398610993bf29278942527731afca9881ac81c6
arm64linux=e474182ab3cd0655b9c687953608da23d1d1640babc8854725c8f9645d4f9367
arm64musl=e474182ab3cd0655b9c687953608da23d1d1640babc8854725c8f9645d4f9367
arm64glibc=e474182ab3cd0655b9c687953608da23d1d1640babc8854725c8f9645d4f9367
arm64v1win=a5ca4a573b2e449865c831582398610993bf29278942527731afca9881ac81c6
arm64v1mingw=a5ca4a573b2e449865c831582398610993bf29278942527731afca9881ac81c6
arm64v1linux=e474182ab3cd0655b9c687953608da23d1d1640babc8854725c8f9645d4f9367
arm64v1musl=e474182ab3cd0655b9c687953608da23d1d1640babc8854725c8f9645d4f9367
arm64v1glibc=e474182ab3cd0655b9c687953608da23d1d1640babc8854725c8f9645d4f9367
arm32linux=bd67b1db5b506b81d55e197ca6de3e4877d958836eed444280535c46bda6d8f0
arm32musl=bd67b1db5b506b81d55e197ca6de3e4877d958836eed444280535c46bda6d8f0
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
