# META
~~~ini
description=Eighteen mixed integer and float arguments overflow both argument register files
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

combine : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64
combine = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8| {
    ints = i0 + i1 * 2 + i2 * 3 + i3 * 4 + i4 * 5 + i5 * 6 + i6 * 7 + i7 * 8 + i8 * 9
    floats = f0 + f1 * 2.0 + f2 * 3.0 + f3 * 4.0 + f4 * 5.0 + f5 * 6.0 + f6 * 7.0 + f7 * 8.0 + f8 * 9.0
    I64.to_f64(ints) + floats
}

main : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64
main = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8|
    combine(i8, f8, i7, f7, i6, f6, i5, f5, i4, f4, i3, f3, i2, f2, i1, f1, i0, f0)
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64, I64, F64 -> F64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
combine = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8| {
	ints = i0 + i1 * 2 + i2 * 3 + i3 * 4 + i4 * 5 + i5 * 6 + i6 * 7 + i7 * 8 + i8 * 9
	floats = f0 + f1 * 2 + f2 * 3 + f3 * 4 + f4 * 5 + f5 * 6 + f6 * 7 + f7 * 8 + f8 * 9
	to_f64(ints) + floats
}
main = |i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5, i6, f6, i7, f7, i8, f8| combine(i8, f8, i7, f7, i6, f6, i5, f5, i4, f4, i3, f3, i2, f2, i1, f1, i0, f0)

~~~
# DEV OUTPUT
~~~ini
x64mac=5aa9f9a6614a1ef9e1942aa24723b695a8899f44a116331f4e5e7d1c889d3479
x64win=eddd5c28c4ab7ca0f28982fbc9fc7c75332089e90600fc4a86d828491067c3ff
x64mingw=eddd5c28c4ab7ca0f28982fbc9fc7c75332089e90600fc4a86d828491067c3ff
x64freebsd=c817fd933654ca8241f642676fbb21467352bd62100b9aaf5e3dc5b70264f733
x64openbsd=84051c02f29b5a52d6e0bb1f9c803155a509f82de508382436edf8bc06666208
x64netbsd=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64musl=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64glibc=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64linux=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64elf=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64v1mac=5aa9f9a6614a1ef9e1942aa24723b695a8899f44a116331f4e5e7d1c889d3479
x64v1win=eddd5c28c4ab7ca0f28982fbc9fc7c75332089e90600fc4a86d828491067c3ff
x64v1mingw=eddd5c28c4ab7ca0f28982fbc9fc7c75332089e90600fc4a86d828491067c3ff
x64v1freebsd=c817fd933654ca8241f642676fbb21467352bd62100b9aaf5e3dc5b70264f733
x64v1openbsd=84051c02f29b5a52d6e0bb1f9c803155a509f82de508382436edf8bc06666208
x64v1netbsd=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64v1musl=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64v1glibc=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64v1linux=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
x64v1elf=70e430be0486d0d293cdcebc823f1a78502d4d679e703eb1f1ea81b9c4d9ae01
arm64mac=59a9e717e2d848198b34498e1f91aa5098dcea31528595e5fa4d806827bd9f58
arm64win=844e7e5daad47791ce5c0160c5de809f2ed3e78187ad06d5ae0483e0502f3466
arm64mingw=844e7e5daad47791ce5c0160c5de809f2ed3e78187ad06d5ae0483e0502f3466
arm64linux=b00b5e378d8472acc3db4694e5c50440401cb7c0f7346aa0da7cd1740b760341
arm64musl=b00b5e378d8472acc3db4694e5c50440401cb7c0f7346aa0da7cd1740b760341
arm64glibc=b00b5e378d8472acc3db4694e5c50440401cb7c0f7346aa0da7cd1740b760341
arm64v1win=844e7e5daad47791ce5c0160c5de809f2ed3e78187ad06d5ae0483e0502f3466
arm64v1mingw=844e7e5daad47791ce5c0160c5de809f2ed3e78187ad06d5ae0483e0502f3466
arm64v1linux=b00b5e378d8472acc3db4694e5c50440401cb7c0f7346aa0da7cd1740b760341
arm64v1musl=b00b5e378d8472acc3db4694e5c50440401cb7c0f7346aa0da7cd1740b760341
arm64v1glibc=b00b5e378d8472acc3db4694e5c50440401cb7c0f7346aa0da7cd1740b760341
arm32linux=8d95a23ddd66ffe076522d49297764d464c759586f755e8633efd104e328f198
arm32musl=8d95a23ddd66ffe076522d49297764d464c759586f755e8633efd104e328f198
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
