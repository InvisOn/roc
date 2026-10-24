# META
~~~ini
description=Dec, I128 and U128 arithmetic with 16-byte arguments and a tuple return
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : Dec, I128, U128 -> (Dec, I128, U128)
main = |d, i, u| {
    dec = d * 1.5 + d / 3.0 - 0.25
    wide = i * i - i // 7 + 5
    unsigned = u * 3 + u % 11 - u // 13
    (dec, wide, unsigned)
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : Dec, I128, U128 -> (Dec, I128, U128) }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : Dec, I128, U128 -> (Dec, I128, U128)
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |d, i, u| {
	dec = d * 1.5 + d / 3 - 0.25
	wide = i * i - i // 7 + 5
	unsigned = u * 3 + u % 11 - u // 13
	(dec, wide, unsigned)
}

~~~
# DEV OUTPUT
~~~ini
x64mac=a6cced1a4bf1a6c8ef14bd2f9ad012460e899a56e474e024d7ff1922d352f73d
x64win=2d463d989e3d3add0b5a504f0ca880c3ad8fc3b62ab56634a23a58bb3d3c8c6a
x64mingw=2d463d989e3d3add0b5a504f0ca880c3ad8fc3b62ab56634a23a58bb3d3c8c6a
x64freebsd=1dccb64ffbdee5e655b6ce93d6f36b38e7b0d879643319e738c9277b4e62d943
x64openbsd=d2ffd4c3320e3aed4df8d39a128684745983a3e02646923061f9ba51b6964cb2
x64netbsd=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64musl=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64glibc=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64linux=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64elf=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64v1mac=a6cced1a4bf1a6c8ef14bd2f9ad012460e899a56e474e024d7ff1922d352f73d
x64v1win=2d463d989e3d3add0b5a504f0ca880c3ad8fc3b62ab56634a23a58bb3d3c8c6a
x64v1mingw=2d463d989e3d3add0b5a504f0ca880c3ad8fc3b62ab56634a23a58bb3d3c8c6a
x64v1freebsd=1dccb64ffbdee5e655b6ce93d6f36b38e7b0d879643319e738c9277b4e62d943
x64v1openbsd=d2ffd4c3320e3aed4df8d39a128684745983a3e02646923061f9ba51b6964cb2
x64v1netbsd=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64v1musl=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64v1glibc=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64v1linux=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
x64v1elf=fdc13c1615c52466658396c6f8408a82752ba9bd63cfa2a35459048e479cc48e
arm64mac=ede2c36729946d4423962569eac97798e61f1aca9431780599a6017d770ccba7
arm64win=b0add2e9424e2d0e8d10547533167a084226a517358b9752f4de1e945fc72bd2
arm64mingw=b0add2e9424e2d0e8d10547533167a084226a517358b9752f4de1e945fc72bd2
arm64linux=5b79f51c394c95737e3b5243fe9222327ad725ff872aff84b5cde39dda9f92e2
arm64musl=5b79f51c394c95737e3b5243fe9222327ad725ff872aff84b5cde39dda9f92e2
arm64glibc=5b79f51c394c95737e3b5243fe9222327ad725ff872aff84b5cde39dda9f92e2
arm64v1win=b0add2e9424e2d0e8d10547533167a084226a517358b9752f4de1e945fc72bd2
arm64v1mingw=b0add2e9424e2d0e8d10547533167a084226a517358b9752f4de1e945fc72bd2
arm64v1linux=5b79f51c394c95737e3b5243fe9222327ad725ff872aff84b5cde39dda9f92e2
arm64v1musl=5b79f51c394c95737e3b5243fe9222327ad725ff872aff84b5cde39dda9f92e2
arm64v1glibc=5b79f51c394c95737e3b5243fe9222327ad725ff872aff84b5cde39dda9f92e2
arm32linux=07a6c5e588796d7d2c66ad8ce370fccb602f4292a0fddf3730477f2a41c94018
arm32musl=07a6c5e588796d7d2c66ad8ce370fccb602f4292a0fddf3730477f2a41c94018
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
