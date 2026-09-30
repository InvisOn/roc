# META
~~~ini
description=Str concat, split and interpolation over a string beyond the small-string limit
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : Str, Str -> Str
main = |a, b| {
    big = Str.concat(a, " is followed by a long literal that is well beyond the small string limit")
    parts = Str.split_on(big, " ")
    count = List.len(parts)
    "${b}: ${Str.inspect(count)} parts in ${big}"
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : Str, Str -> Str }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : Str, Str -> Str
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
main = |a, b| {
	big = concat(a, " is followed by a long literal that is well beyond the small string limit")
	parts = split_on(big, " ")
	count = len(parts)
	{
		cinterp_0 = b
		cinterp_1 = inspect(count)
		cinterp_2 = big
		<interpolation>("", [cinterp_0, ": ", cinterp_1, " parts in ", cinterp_2, ""])
	}
}

~~~
# DEV OUTPUT
~~~ini
x64mac=db551297b3a06caa389939694009eb4604e8605b76a4344acf7d76141b28438f
x64win=ff35016aa75efe004abbc353dec519bfe8317ed56164d4335ff8d5a6376416db
x64mingw=ff35016aa75efe004abbc353dec519bfe8317ed56164d4335ff8d5a6376416db
x64freebsd=b44e318e5ce93d52e646d68ad4d7e3106c74318c95216a45546a88abd927cb84
x64openbsd=00bef48ce963af2c1261a685fdb2a7f89ec4e5460dca5e3866ee7b922ed2376c
x64netbsd=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64musl=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64glibc=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64linux=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64elf=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64v1mac=db551297b3a06caa389939694009eb4604e8605b76a4344acf7d76141b28438f
x64v1win=ff35016aa75efe004abbc353dec519bfe8317ed56164d4335ff8d5a6376416db
x64v1mingw=ff35016aa75efe004abbc353dec519bfe8317ed56164d4335ff8d5a6376416db
x64v1freebsd=b44e318e5ce93d52e646d68ad4d7e3106c74318c95216a45546a88abd927cb84
x64v1openbsd=00bef48ce963af2c1261a685fdb2a7f89ec4e5460dca5e3866ee7b922ed2376c
x64v1netbsd=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64v1musl=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64v1glibc=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64v1linux=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
x64v1elf=6256861e8e012197b97d583292a348469f70d97bac4fe50e9c354389df5bcea0
arm64mac=326a8ea66de5939fff6031202b732f97f2e39be79efb20cd2397ca432f5047d9
arm64win=0c8f4f604a6984badb6b8f83a2fcbd87f9ffbbe4552eae148759308fe90608f1
arm64mingw=0c8f4f604a6984badb6b8f83a2fcbd87f9ffbbe4552eae148759308fe90608f1
arm64linux=4087309b917a689963d88a044e26418895b0e869987dae6a26b76fea36316b01
arm64musl=4087309b917a689963d88a044e26418895b0e869987dae6a26b76fea36316b01
arm64glibc=4087309b917a689963d88a044e26418895b0e869987dae6a26b76fea36316b01
arm64v1win=0c8f4f604a6984badb6b8f83a2fcbd87f9ffbbe4552eae148759308fe90608f1
arm64v1mingw=0c8f4f604a6984badb6b8f83a2fcbd87f9ffbbe4552eae148759308fe90608f1
arm64v1linux=4087309b917a689963d88a044e26418895b0e869987dae6a26b76fea36316b01
arm64v1musl=4087309b917a689963d88a044e26418895b0e869987dae6a26b76fea36316b01
arm64v1glibc=4087309b917a689963d88a044e26418895b0e869987dae6a26b76fea36316b01
arm32linux=9dca8ea8734bd4bf3ca29fbc6879a232d10cd3c536b78ee06238aa587406fbd2
arm32musl=9dca8ea8734bd4bf3ca29fbc6879a232d10cd3c536b78ee06238aa587406fbd2
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
