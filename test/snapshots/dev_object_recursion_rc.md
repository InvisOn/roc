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
x64mac=187ea267b84c498b3294278f2b5716fb4855e2e28771dae85b756963a9faa2e6
x64win=85cdbd3626e7661f1dc4389e99cd31598f4c9b2e071f613c390e7f2d6fc1a0b7
x64mingw=85cdbd3626e7661f1dc4389e99cd31598f4c9b2e071f613c390e7f2d6fc1a0b7
x64freebsd=04f2c1d4faf2d72c2f2836d901a5e8ee1820c2d65a77644a9fe6b5c3c44da2ac
x64openbsd=2b2280429a7802a1a858c17c90f79c1f181cf6ff6ec0d1c9190a09a804734090
x64netbsd=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64musl=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64glibc=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64linux=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64elf=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64v1mac=187ea267b84c498b3294278f2b5716fb4855e2e28771dae85b756963a9faa2e6
x64v1win=85cdbd3626e7661f1dc4389e99cd31598f4c9b2e071f613c390e7f2d6fc1a0b7
x64v1mingw=85cdbd3626e7661f1dc4389e99cd31598f4c9b2e071f613c390e7f2d6fc1a0b7
x64v1freebsd=04f2c1d4faf2d72c2f2836d901a5e8ee1820c2d65a77644a9fe6b5c3c44da2ac
x64v1openbsd=2b2280429a7802a1a858c17c90f79c1f181cf6ff6ec0d1c9190a09a804734090
x64v1netbsd=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64v1musl=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64v1glibc=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64v1linux=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
x64v1elf=73ce2391655bdb823f713427cc497377fc0b866329c102712e6bc28ded6874cc
arm64mac=f692141256936f6c5a46c15f052cc02d6ed4612684982a37b4ecbcb65d312018
arm64win=b1aa7958453704e93c0f39a65bea8a4ce021ee938d19e7b18f93eda8c3d8c2e2
arm64mingw=b1aa7958453704e93c0f39a65bea8a4ce021ee938d19e7b18f93eda8c3d8c2e2
arm64linux=ae297f59677bbe787c8bb64d5a9d6e3fa26dc26b99cca6fbd16146c8b5a0dab7
arm64musl=ae297f59677bbe787c8bb64d5a9d6e3fa26dc26b99cca6fbd16146c8b5a0dab7
arm64glibc=ae297f59677bbe787c8bb64d5a9d6e3fa26dc26b99cca6fbd16146c8b5a0dab7
arm64v1win=b1aa7958453704e93c0f39a65bea8a4ce021ee938d19e7b18f93eda8c3d8c2e2
arm64v1mingw=b1aa7958453704e93c0f39a65bea8a4ce021ee938d19e7b18f93eda8c3d8c2e2
arm64v1linux=ae297f59677bbe787c8bb64d5a9d6e3fa26dc26b99cca6fbd16146c8b5a0dab7
arm64v1musl=ae297f59677bbe787c8bb64d5a9d6e3fa26dc26b99cca6fbd16146c8b5a0dab7
arm64v1glibc=ae297f59677bbe787c8bb64d5a9d6e3fa26dc26b99cca6fbd16146c8b5a0dab7
arm32linux=0857d06ed0ffb7409e492abb2314a637d74ae1c34cf0a51ca958f1d3285f4df6
arm32musl=0857d06ed0ffb7409e492abb2314a637d74ae1c34cf0a51ca958f1d3285f4df6
wasm32=NOT_IMPLEMENTED
wasm32v1=NOT_IMPLEMENTED
~~~
