# META
~~~ini
description=Recursive boxed tree built and walked twice, forcing incref and decref helpers
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

Tree := [Leaf(I64), Node(Box(Tree), Box(Tree))]

build : I64 -> Tree
build = |depth|
    if depth <= 0 {
        Leaf(depth)
    } else {
        Node(Box.box(build(depth - 1)), Box.box(build(depth - 2)))
    }

sum : Tree -> I64
sum = |tree|
    match tree {
        Leaf(n) => n
        Node(left, right) => sum(Box.unbox(left)) + sum(Box.unbox(right))
    }

main : I64 -> I64
main = |depth| {
    tree = build(depth)
    sum(tree) + sum(tree)
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : I64 -> I64
main_for_host = main
~~~
# MONO
~~~roc
# platform
main_for_host = <required>

# app
build = |depth| if (depth <= 0) {
	Leaf(depth)
} else {
	Node(box(build(depth - 1)), box(build(depth - 2)))
}
sum = |tree| match tree {
	Leaf(n) => n
	Node(left, right) => sum(unbox(left)) + sum(unbox(right))
}
main = |depth| {
	tree = build(depth)
	sum(tree) + sum(tree)
}

~~~
# DEV OUTPUT
~~~ini
x64mac=d023ed0c037a0f6fa362ede95d2c2daebc073a51812965d1ae6ab208b264427d
x64win=29ccf6c7e0e977de1162aad0fb05960979c6e2aaaa71628cccda783b1c7ef237
x64mingw=29ccf6c7e0e977de1162aad0fb05960979c6e2aaaa71628cccda783b1c7ef237
x64freebsd=8b085b0da505b8910241d14b17d34a995bf36be2071c1ee08e91f4dc83d0bf30
x64openbsd=9202ee766fd0f3f7c3753fde65d1dadf39d7b7fba62e9688ed010bcc3ad6767f
x64netbsd=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64musl=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64glibc=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64linux=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64elf=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64v1mac=d023ed0c037a0f6fa362ede95d2c2daebc073a51812965d1ae6ab208b264427d
x64v1win=29ccf6c7e0e977de1162aad0fb05960979c6e2aaaa71628cccda783b1c7ef237
x64v1mingw=29ccf6c7e0e977de1162aad0fb05960979c6e2aaaa71628cccda783b1c7ef237
x64v1freebsd=8b085b0da505b8910241d14b17d34a995bf36be2071c1ee08e91f4dc83d0bf30
x64v1openbsd=9202ee766fd0f3f7c3753fde65d1dadf39d7b7fba62e9688ed010bcc3ad6767f
x64v1netbsd=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64v1musl=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64v1glibc=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64v1linux=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
x64v1elf=c0a4416ab107cc649c23b796287f85631bdd1c0abb01d48229bd122d6ac04ff9
arm64mac=6ab85d0dc97894802fb9a5b98e3725e3306729ed686b56c1eeaf8eb7ce9b544f
arm64win=3d2cab750932cc5ab0625c9884974234d21b8afc1726ddfece0c3242e401cb52
arm64mingw=3d2cab750932cc5ab0625c9884974234d21b8afc1726ddfece0c3242e401cb52
arm64linux=0c7f22ef7623a32c1a0735c88b78f023856046647c299e7d498b04a7dd6b61a5
arm64musl=0c7f22ef7623a32c1a0735c88b78f023856046647c299e7d498b04a7dd6b61a5
arm64glibc=0c7f22ef7623a32c1a0735c88b78f023856046647c299e7d498b04a7dd6b61a5
arm64v1win=3d2cab750932cc5ab0625c9884974234d21b8afc1726ddfece0c3242e401cb52
arm64v1mingw=3d2cab750932cc5ab0625c9884974234d21b8afc1726ddfece0c3242e401cb52
arm64v1linux=0c7f22ef7623a32c1a0735c88b78f023856046647c299e7d498b04a7dd6b61a5
arm64v1musl=0c7f22ef7623a32c1a0735c88b78f023856046647c299e7d498b04a7dd6b61a5
arm64v1glibc=0c7f22ef7623a32c1a0735c88b78f023856046647c299e7d498b04a7dd6b61a5
arm32linux=NOT_IMPLEMENTED
arm32musl=NOT_IMPLEMENTED
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
