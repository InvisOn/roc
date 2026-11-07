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
lines(ISA, 10649)   # emitPopcount64: only when use_swar is false (x86_64 above v1)
lines(ISA, 17710)   # generateCachedComposition: `else` of `if (comptime target.toCpuArch() == .aarch64)`

# generateLowLevel
lines(W, 1919, 1945, 1946, 1947, 1950, 2074, 2075, 2076, 2149, 2150, 2266, 2270,
      2276, 2281, 2340, 2341, 2368, 2371, 2376, 2379, 2399, 2400, 2409, 2414, 2418,
      2419, 2436, 2437, 2460, 2461, 2462, 2464, 2465, 2466, 3735, 3736, 3767, 3768,
      4543, 4550, 4797, 4800)
lines(B64, 2134, 2250)          # U64 index operand (num_from_le_bytes, List.get)
lines(B64, 2327)                # list_item_size_at_most's U64 bound
lines(SCALAR, 2674, 2675, 2699, 2700, 2751, 2752, 2778, 2779, 2820, 2821, 3061,
      3062, 3064, 3065, 3142, 3143, 3164, 3165, 3185, 3186, 3232, 3233, 4186, 4216,
      4500, 4501)
lines(B64, 2974, 3071, 3075, 3076, 3079, 3132, 3133, 3223, 3224, 4177, 4178, 4201,
      4202, 4207, 4208)
lines(PIECE, 3528, 3529)        # RocStr words at a hard-coded `word * 8`

# copyBytesToStackOffset: immediates by destination size
lines(S8, 16724, 16758, 16813)
lines(B64, 16726, 16729, 16752, 16754)
lines(W, 16733, 16734, 16735)

# U64 operands (start, length, index, ListOpRequest.n) in otherwise word functions
lines(B64, 7892, 7893, 7900, 7901)              # callListSublist start and length
lines(B64, 15724, 15725)                        # emitZstSublist start and length
lines(B64, 15740)                               # emitZstDropAt index
lines(B64, 18351, 18352, 18362, 18363, 18364, 18365)  # generateDynElemLowLevel: n
lines(B64, 18093, 18094)                        # generateDyn: hasher seed
lines(B64, 18283)                               # List.len result (U64) stored to its slot
lines(SCALAR, 18308)                            # map_can_reuse result (Bool)

# Exceptions inside otherwise one-kind functions
lines(W, 6693)                                  # emitSimdClmulBaseline: loop count
lines(B64, 11335, 11336)                        # generateNumAbs: i128 halves
lines(SCALAR, 10852, 10856)                     # getI128Parts: the value before widening
lines(SCALAR, 13052, 13060)                     # rc helper: discriminant read wide, masked
lines(B64, 13580)                               # discriminant whose layout is u64
lines(SCALAR, 14244)                            # generateTailCall: value loaded at its size
lines(PIECE, 14286)                             # generateTailCall: argument registers
lines(B64, 15355, 15374)                        # moveToReg: i128 low half, F64 bits
lines(SCALAR, 15351)                            # moveToReg: stack value
lines(SCALAR, 16028)                            # ensureOnStack: immediate
lines(B64, 16040, 16042)                        # ensureOnStack: i128 immediate
lines(B64, 16077, 16102)                        # ensureInGeneralReg: i128 low half, F64 bits
lines(SCALAR, 18519)                            # ensureValueOnStackForRc: immediate
lines(B64, 19513, 19515, 19676)                 # freezeCallArg: i128 immediate, F64 bits
lines(SCALAR, 19671, 19680)                     # freezeCallArg: immediate, stack value
lines(B64, 19826, 19827)                        # placeCallArguments: i128 halves
lines(W, 19836, 19837, 19838)                   # placeCallArguments: RocStr/RocList words
lines(B64, 19319, 19320)                        # saveCallReturnValue: i128/Dec return
lines(W, 19340, 19341, 19342, 19355, 19356, 19357, 19396)
lines(W, 20167)                                 # bindProcParams: pointer argument
lines(W, 20265, 20266, 20267, 20290, 20291, 20292)    # RocList/RocStr return words
lines(B64, 20300, 20301, 20304, 20305, 20411, 20412, 20415, 20416, 20454, 20455,
      20469, 20470)                             # i128/Dec return halves
lines(SCALAR, 15539, 15564)                     # spillArgToStack: immediate, other value
lines(B64, 15546, 15548)                        # spillArgToStack: i128 immediate
lines(W, 15518, 15551, 15557)                   # spillArgToStack: one whole register
lines(PIECE, 22887, 22966)                      # C ABI integer pieces

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
print("line\tfunction\tcontext\tkind\tcode")
print("\n".join(out))
