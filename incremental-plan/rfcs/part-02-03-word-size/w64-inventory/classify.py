"""Classify every `.w64` site listed by w64_sites.py (LirCodeGen.zig).

Usage: python3 -I classify.py <sites.tsv>  ->  TSV: line, function, context, kind, code
Kinds: isa, word, 64, scalar, piece, chunk, size-8 (README.md defines them).
A shared site gets its kind from LINE, else from its function's default in
FN. A shared site with neither stops the script, and so does a line set
twice, so a re-run on a new base shows what moved.
"""
import collections
import sys

ISA, W, B64, SCALAR, PIECE, CHUNK, S8 = "isa", "word", "64", "scalar", "piece", "chunk", "size-8"

FN = {}
def default(kind, names):
    for name in names.split():
        assert name not in FN, name
        FN[name] = kind

default(W, """bindComponentAddress bindErasedCallableAdapterParams bindErasedRecordParams
    boxValueLocationToLayout callListSublist compileProcSpec compileRcHelperCallable
    copyResultToReturnPointer emitAddPtrImmAny emitAddUsizeImm
    emitBuiltinInternalRcHelperBoxDrop emitBuiltinInternalRcHelperBoxIncref
    emitBuiltinInternalRcHelperErasedCallableDrop emitBuiltinInternalRcHelperListDrop
    emitBuiltinInternalRcHelperListIncref emitBuiltinInternalRcHelperStr emitBytesAddress
    emitCallRcHelperFromStackSlots emitCheckBytesAvailable emitDebugAssertValidBoxLocal
    emitDebugAssertValidStrLocal emitDriveInto emitFindDelimiter
    emitHotReloadEnterForHostCallable emitLoadStrSourceShape emitOwnPendingCell
    emitProcAddressToSlot emitRawRcHelperCallFromPtrReg emitRcHelperCallAtStackOffset
    emitReserveStack emitStoreHeapStrCapture emitStoreSmallStrCapture emitStoreStrCapture
    emitStoreToMem emitTailCarry emitTargetAddress emitZstDropAt emitZstList
    emitZstListOneLonger emitZstListWithSameLen emitZstSublist ensureValueOnStackForRc
    generateBytesLiteral generateCachedComposition generateDyn generateDynCall
    generateDynElemLowLevel generateDynFrameAlloc generateEntrypointBodyCAbi
    generateErasedCall generateList generateListReverse generatePackedErasedFn
    generateSimdGetLane generateSimdLoad generateSimdShift generateSimdStore
    generateStrLiteral generateStruct generateTag generateTailCall
    loadStrDataPtrForRcFromValuePtr saveIncomingPointerArg emitLocalArray emitMovRegReg
    emitCmpReg moveOneRegToReturn scalarRetReg stabilize ensureInGeneralReg moveToReg
    ensureOnStack freezeCallArg generateStructAccess storeResultToSavedPtr
    generateBuiltinInternalRcHelperBody""")
default(B64, """bindPendingI128OverflowResult callDecBinary callI128DivRem callI128Mod
    callI128MulWithOverflow callI128Shift emitPopcount64 emitSignExtendHighReg
    generateAbsDiff128 generateBitCount128 generateI128Binop getI128Parts simdArgParts
    storeI128ToMem emitNormalizeNanBitsInReg emitSimdClmulBaseline hasherStateReg
    storeWideScalarToStackOffset emitIntMulOverflowFlag emitCheckedIntMul""")
default(SCALAR, """generateIntBinop generateIntTryConversion generateAbsDiff
    normalizeIntegerWidthInReg signExtendGeneral emitValueLoadStack emitNarrowIntRangeFlag
    generateBitCountScalar generateNumAbs generateSimdRoundedShift generateStmt
    generateDiscriminantAccess""")
default(PIECE, """bindProcParams moveToReturnRegisterWithLayout placeCallArguments
    saveCallReturnValue spillArgToStack generateCAbiCall copyFromCallerStack""")
default(CHUNK, """copyChunked copyLoop fillMem fillSmall emitCompareLiteralAtPtr""")
default(S8, """emitSizedLoadMem emitSizedLoadStack emitSizedStoreMem
    storeDiscriminantToPtr emitStoreScalarToPtr bindReturnedScalar""")
# Mixed functions: every line is listed below.
FN["generateLowLevel"] = None
FN["copyBytesToStackOffset"] = None

LINE = {}
seen = collections.Counter()
def lines(kind, *ns):
    for n in ns:
        seen[n] += 1
        LINE[n] = kind

# Shared-looking sites that run for one instruction set only.
lines(ISA, 10648)   # emitPopcount64: only when use_swar is false (x86_64 above v1)
lines(ISA, 17709)   # generateCachedComposition: `else` of `if (comptime target.toCpuArch() == .aarch64)`

# generateLowLevel
lines(W, 1918, 1944, 1945, 1946, 1949, 2073, 2074, 2075, 2148, 2149, 2265, 2269,
      2275, 2280, 2339, 2340, 2367, 2370, 2375, 2378, 2398, 2399, 2408, 2413, 2417,
      2418, 2435, 2436, 2459, 2460, 2461, 2463, 2464, 2465, 3734, 3735, 3766, 3767,
      4542, 4549, 4796, 4799)
lines(B64, 2133, 2249)          # U64 index operand (num_from_le_bytes, List.get)
lines(B64, 2326)                # list_item_size_at_most's U64 bound
lines(SCALAR, 2673, 2674, 2698, 2699, 2750, 2751, 2777, 2778, 2819, 2820, 3060,
      3061, 3063, 3064, 3141, 3142, 3163, 3164, 3184, 3185, 3231, 3232, 4185, 4215,
      4499, 4500)
lines(B64, 2973, 3070, 3074, 3075, 3078, 3131, 3132, 3222, 3223, 4176, 4177, 4200,
      4201, 4206, 4207)
lines(PIECE, 3527, 3528)        # RocStr words at a hard-coded `word * 8`

# copyBytesToStackOffset: immediates by destination size
lines(S8, 16723, 16757, 16812)
lines(B64, 16725, 16728, 16751, 16753)
lines(W, 16732, 16733, 16734)

# U64 operands (start, length, index, ListOpRequest.n) in otherwise word functions
lines(B64, 7891, 7892, 7899, 7900)              # callListSublist start and length
lines(B64, 15723, 15724)                        # emitZstSublist start and length
lines(B64, 15739)                               # emitZstDropAt index
lines(B64, 18350, 18351, 18361, 18362, 18363, 18364)  # generateDynElemLowLevel: n
lines(B64, 18092, 18093)                        # generateDyn: hasher seed
lines(B64, 18282)                               # List.len result (U64) stored to its slot
lines(SCALAR, 18307)                            # map_can_reuse result (Bool)

# Exceptions inside otherwise one-kind functions
lines(W, 6692)                                  # emitSimdClmulBaseline: loop count
lines(B64, 11334, 11335)                        # generateNumAbs: i128 halves
lines(SCALAR, 10851, 10855)                     # getI128Parts: the value before widening
lines(SCALAR, 13051, 13059)                     # rc helper: discriminant read wide, masked
lines(B64, 13579)                               # discriminant whose layout is u64
lines(SCALAR, 14243)                            # generateTailCall: value loaded at its size
lines(PIECE, 14285)                             # generateTailCall: argument registers
lines(B64, 15354, 15373)                        # moveToReg: i128 low half, F64 bits
lines(SCALAR, 15350)                            # moveToReg: stack value
lines(SCALAR, 16027)                            # ensureOnStack: immediate
lines(B64, 16039, 16041)                        # ensureOnStack: i128 immediate
lines(B64, 16076, 16101)                        # ensureInGeneralReg: i128 low half, F64 bits
lines(SCALAR, 18518)                            # ensureValueOnStackForRc: immediate
lines(B64, 19512, 19514, 19675)                 # freezeCallArg: i128 immediate, F64 bits
lines(SCALAR, 19670, 19679)                     # freezeCallArg: immediate, stack value
lines(B64, 19825, 19826)                        # placeCallArguments: i128 halves
lines(W, 19835, 19836, 19837)                   # placeCallArguments: RocStr/RocList words
lines(B64, 19318, 19319)                        # saveCallReturnValue: i128/Dec return
lines(W, 19339, 19340, 19341, 19354, 19355, 19356, 19395)
lines(W, 20166)                                 # bindProcParams: pointer argument
lines(W, 20264, 20265, 20266, 20289, 20290, 20291)    # RocList/RocStr return words
lines(B64, 20299, 20300, 20303, 20304, 20410, 20411, 20414, 20415, 20453, 20454,
      20468, 20469)                             # i128/Dec return halves
lines(SCALAR, 15538, 15563)                     # spillArgToStack: immediate, other value
lines(B64, 15545, 15547)                        # spillArgToStack: i128 immediate
lines(W, 15517, 15550, 15556)                   # spillArgToStack: one whole register
lines(PIECE, 22874, 22953)                      # C ABI integer pieces

twice = [n for n, c in seen.items() if c > 1]
if twice:
    sys.exit(f"lines set twice: {sorted(twice)}")

out = []
for row in open(sys.argv[1], encoding="utf-8"):
    line, fn, helper, ctx, code = row.rstrip("\n").split("\t")
    n = int(line)
    if ctx != "shared":
        kind = ISA
    elif n in LINE:
        kind = LINE[n]
    elif FN.get(fn):
        kind = FN[fn]
    else:
        sys.exit(f"unclassified: {line} {fn}: {code}")
    out.append("\t".join([line, fn, ctx, kind, code]))
used = {int(r.split("\t")[0]) for r in out}
unused = sorted(set(LINE) - used)
if unused:
    sys.exit(f"LINE entries that match no site: {unused}")
print("\n".join(out))
