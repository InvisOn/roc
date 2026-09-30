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
x64mac=d4103cce070695fa4c3fafe3e209621589711bdf920fbfd3f87e7c456b9ef1db
x64win=5d6f6978d905eeb75d7cf6a360d676b6d780b50a06cff69fca8569a249842e1e
x64mingw=5d6f6978d905eeb75d7cf6a360d676b6d780b50a06cff69fca8569a249842e1e
x64freebsd=554148e8154ab4060503f5318333027e1c19eb4b1f3cb1046cd5b35ad4970262
x64openbsd=0d50614bbabe1c14fe79c751aea61d3fb183243d1e30c945907a53aaa25f61f2
x64netbsd=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64musl=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64glibc=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64linux=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64elf=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64v1mac=d4103cce070695fa4c3fafe3e209621589711bdf920fbfd3f87e7c456b9ef1db
x64v1win=5d6f6978d905eeb75d7cf6a360d676b6d780b50a06cff69fca8569a249842e1e
x64v1mingw=5d6f6978d905eeb75d7cf6a360d676b6d780b50a06cff69fca8569a249842e1e
x64v1freebsd=554148e8154ab4060503f5318333027e1c19eb4b1f3cb1046cd5b35ad4970262
x64v1openbsd=0d50614bbabe1c14fe79c751aea61d3fb183243d1e30c945907a53aaa25f61f2
x64v1netbsd=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64v1musl=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64v1glibc=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64v1linux=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
x64v1elf=3ba1f37c607ca18f44674ccec9bd70da983df5eb97468665208a77662df22a3f
arm64mac=f2236e01225cbcc860031cd184feb46358e05ac445b5dafd90a468a9d1d50069
arm64win=84de09b7bc444fc0939658a1faaf2a79740f2c11f9c3bc168b31578cb6b6782a
arm64mingw=84de09b7bc444fc0939658a1faaf2a79740f2c11f9c3bc168b31578cb6b6782a
arm64linux=436047502d098c47339a968065e1d60acf7ac4bdcd0b8c68154470afb79fc111
arm64musl=436047502d098c47339a968065e1d60acf7ac4bdcd0b8c68154470afb79fc111
arm64glibc=436047502d098c47339a968065e1d60acf7ac4bdcd0b8c68154470afb79fc111
arm64v1win=84de09b7bc444fc0939658a1faaf2a79740f2c11f9c3bc168b31578cb6b6782a
arm64v1mingw=84de09b7bc444fc0939658a1faaf2a79740f2c11f9c3bc168b31578cb6b6782a
arm64v1linux=436047502d098c47339a968065e1d60acf7ac4bdcd0b8c68154470afb79fc111
arm64v1musl=436047502d098c47339a968065e1d60acf7ac4bdcd0b8c68154470afb79fc111
arm64v1glibc=436047502d098c47339a968065e1d60acf7ac4bdcd0b8c68154470afb79fc111
arm32linux=66a27fb3393815283f595af805cc1da0bbba851b513b12ac6a343a1a49a7a627
arm32musl=66a27fb3393815283f595af805cc1da0bbba851b513b12ac6a343a1a49a7a627
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
