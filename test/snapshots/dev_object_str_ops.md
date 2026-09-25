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
x64mac=270cf2f930d1c6ec1c748d1225e8191ec2105c1f279846ac800294a28d387039
x64win=2850472fd9e0937fbb0f73ae8187debbf68100e9d8c59e18d22b168b50a489c1
x64mingw=2850472fd9e0937fbb0f73ae8187debbf68100e9d8c59e18d22b168b50a489c1
x64freebsd=4720344251dd44e3d491b515beaf37d8445048a1533b4440270ff9e0918f0f66
x64openbsd=5ced4e811c46b4fc90e0725f0a7659ff9aacb2dc96690927008c1e6cac1737fc
x64netbsd=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64musl=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64glibc=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64linux=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64elf=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64v1mac=270cf2f930d1c6ec1c748d1225e8191ec2105c1f279846ac800294a28d387039
x64v1win=2850472fd9e0937fbb0f73ae8187debbf68100e9d8c59e18d22b168b50a489c1
x64v1mingw=2850472fd9e0937fbb0f73ae8187debbf68100e9d8c59e18d22b168b50a489c1
x64v1freebsd=4720344251dd44e3d491b515beaf37d8445048a1533b4440270ff9e0918f0f66
x64v1openbsd=5ced4e811c46b4fc90e0725f0a7659ff9aacb2dc96690927008c1e6cac1737fc
x64v1netbsd=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64v1musl=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64v1glibc=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64v1linux=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
x64v1elf=608d651798546e260261eb29504a68277f2c78e68d022747186e49e3b56c63dc
arm64mac=a6361eb2914cc10cbc9077022338778d10f93f36baa5a53ba9027cb56c196c0f
arm64win=4ecf5c568c2b4e1b71d0e284f1f24283081f861f8225af2fc20c1e75f66bc283
arm64mingw=4ecf5c568c2b4e1b71d0e284f1f24283081f861f8225af2fc20c1e75f66bc283
arm64linux=68421db7b023a3121528676189f431c63a85a4591515fcbbf8ad04236d77840f
arm64musl=68421db7b023a3121528676189f431c63a85a4591515fcbbf8ad04236d77840f
arm64glibc=68421db7b023a3121528676189f431c63a85a4591515fcbbf8ad04236d77840f
arm64v1win=4ecf5c568c2b4e1b71d0e284f1f24283081f861f8225af2fc20c1e75f66bc283
arm64v1mingw=4ecf5c568c2b4e1b71d0e284f1f24283081f861f8225af2fc20c1e75f66bc283
arm64v1linux=68421db7b023a3121528676189f431c63a85a4591515fcbbf8ad04236d77840f
arm64v1musl=68421db7b023a3121528676189f431c63a85a4591515fcbbf8ad04236d77840f
arm64v1glibc=68421db7b023a3121528676189f431c63a85a4591515fcbbf8ad04236d77840f
arm32linux=737174289d0d200514ecca25dfa6b477e922ff5832eeea67d1cfd62882822f74
arm32musl=737174289d0d200514ecca25dfa6b477e922ff5832eeea67d1cfd62882822f74
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
