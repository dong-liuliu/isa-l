;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  Private Properties， Contact xiaodong.liu@intel.com for copyright details
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;
;;; gf_2vect_avx512_gfni(len, vec, *matrix, **buffs, **dests);
;;;

%include "reg_sizes.asm"

;;;TODO:
;;;%ifdef HAVE_AS_KNOWS_AVX512_GFNI
%ifdef HAVE_AS_KNOWS_AVX512

%ifidn __OUTPUT_FORMAT__, elf64
 %define arg0  rdi
 %define arg1  rsi
 %define arg2  rdx
 %define arg3  rcx
 %define arg4  r8
 %define arg5  r9

 %define tmp   r11
 %define tmp2  r10
 %define tmp3  r12		; must be saved and restored
 %define tmp4  r13		; must be saved and restored
 %define tmp5  r14		; must be saved and restored
 %define return rax
 %define PS     8
 %define LOG_PS 3

 %define func(x) x: endbranch
 %macro FUNC_SAVE 0
	push	r12
	push	r13
	push	r14
 %endmacro
 %macro FUNC_RESTORE 0
	pop	r14
	pop	r13
	pop	r12
 %endmacro
%endif

%ifidn __OUTPUT_FORMAT__, win64
 %define arg0   rcx
 %define arg1   rdx
 %define arg2   r8
 %define arg3   r9

 %define arg4   r12 		; must be saved, loaded and restored
 %define arg5   r15 		; must be saved and restored
 %define tmp    r11
 %define tmp2   r10
 %define tmp3   r13		; must be saved and restored
 %define tmp4   r14		; must be saved and restored
 %define return rax
 %define PS     8
 %define LOG_PS 3
 %define stack_size  9*16 + 5*8		; must be an odd multiple of 8
 %define arg(x)      [rsp + stack_size + PS + PS*x]

 %define func(x) proc_frame x
 %macro FUNC_SAVE 0
	alloc_stack	stack_size
	vmovdqa	[rsp + 0*16], xmm6
	vmovdqa	[rsp + 1*16], xmm7
	vmovdqa	[rsp + 2*16], xmm8
	vmovdqa	[rsp + 3*16], xmm9
	vmovdqa	[rsp + 4*16], xmm10
	vmovdqa	[rsp + 5*16], xmm11
	vmovdqa	[rsp + 6*16], xmm12
	vmovdqa	[rsp + 7*16], xmm13
	vmovdqa	[rsp + 8*16], xmm14
	save_reg	r12,  9*16 + 0*8
	save_reg	r13,  9*16 + 1*8
	save_reg	r14,  9*16 + 2*8
	save_reg	r15,  9*16 + 3*8
	end_prolog
	mov	arg4, arg(4)
 %endmacro

 %macro FUNC_RESTORE 0
	vmovdqa	xmm6, [rsp + 0*16]
	vmovdqa	xmm7, [rsp + 1*16]
	vmovdqa	xmm8, [rsp + 2*16]
	vmovdqa	xmm9, [rsp + 3*16]
	vmovdqa	xmm10, [rsp + 4*16]
	vmovdqa	xmm11, [rsp + 5*16]
	vmovdqa	xmm12, [rsp + 6*16]
	vmovdqa	xmm13, [rsp + 7*16]
	vmovdqa	xmm14, [rsp + 8*16]
	mov	r12,  [rsp + 9*16 + 0*8]
	mov	r13,  [rsp + 9*16 + 1*8]
	mov	r14,  [rsp + 9*16 + 2*8]
	mov	r15,  [rsp + 9*16 + 3*8]
	add	rsp, stack_size
 %endmacro
%endif


%define len    arg0
%define vec    arg1
%define mul_array arg2
%define src    arg3
%define dest1  arg4
%define ptr    arg5
%define vec_i  tmp2
%define dest2  tmp3
%define mulmtx  tmp5
%define MULMTX  tmp4
%define pos    return


%ifndef EC_ALIGNED_ADDR
;;; Use Un-aligned load/store
 %define XLDR vmovdqu8
 %define XSTR vmovdqu8
%else
;;; Use Non-temporal load/stor
 %ifdef NO_NT_LDST
  %define XLDR vmovdqa
  %define XSTR vmovdqa
 %else
  %define XLDR vmovntdqa
  %define XSTR vmovntdq
 %endif
%endif

%define z0   zmm8
%define z1  zmm7
%define x0  zmm6
%define x1  zmm5
%define x2  zmm4

%define xp1       zmm2
%define xp2       zmm3

default rel
[bits 64]

section .text

align 16
mk_global gf_2vect_avx512_gfni, function
func(gf_2vect_avx512_gfni)
	FUNC_SAVE
	sub	len, 64
	jl	.return_fail

	xor	pos, pos
	;sal	vec, LOG_PS		;vec *= PS. Make vec_i count by PS
	mov	dest2, [dest1+PS]
	mov	dest1, [dest1]


.loop64:
	vpxorq	xp1, xp1, xp1
	vpxorq	xp2, xp2, xp2
	mov	tmp, mul_array
	xor	vec_i, vec_i

.next_vect:
	;mov	ptr, [src+vec_i]
	mov	ptr, [src+vec_i * PS]
	XLDR	x0, [ptr+pos]		;Get next source vector
	;add	vec_i, PS
	add	vec_i, 1

	lea	MULMTX, [MulMatrices]
	mov	mulmtx, [tmp]
	and	mulmtx, 0xff
	sal	mulmtx, LOG_PS
	add	mulmtx, MULMTX

	VBROADCASTF32X2 z0, [mulmtx]
	
	mov	mulmtx, [tmp + vec]
	and	mulmtx, 0xff
	sal	mulmtx, LOG_PS
	add	mulmtx, MULMTX
	VBROADCASTF32X2 z1, [mulmtx]

	add	tmp, 1

	VGF2P8AFFINEQB x1, x0, z0, 0
	VGF2P8AFFINEQB x2, x0, z1, 0

	VXORPD         xp1, xp1, x1
	VXORPD         xp2, xp2, x2

	cmp	vec_i, vec
	jl	.next_vect

	XSTR	[dest1+pos], xp1
	XSTR	[dest2+pos], xp2

	add	pos, 64			;Loop on 64 bytes at a time
	cmp	pos, len
	jle	.loop64

	lea	tmp, [len + 64]
	cmp	pos, tmp
	je	.return_pass

	;; Tail len
	mov	pos, len	;Overlapped offset length-64
	jmp	.loop64		;Do one more overlap pass

.return_pass:
	mov	return, 0
	FUNC_RESTORE
	ret

.return_fail:
	mov	return, 1
	FUNC_RESTORE
	ret

endproc_frame
section .data

; precomputed constants
align 16

MulMatrices:
dq 0
dq 0x102040810204080
dq 0x8001828488102040
dq 0x8103868c983060c0
dq 0x408041c2c4881020
dq 0x418245cad4a850a0
dq 0xc081c3464c983060
dq 0xc183c74e5cb870e0
dq 0x2040a061e2c48810
dq 0x2142a469f2e4c890
dq 0xa04122e56ad4a850
dq 0xa14326ed7af4e8d0
dq 0x60c0e1a3264c9830
dq 0x61c2e5ab366cd8b0
dq 0xe0c16327ae5cb870
dq 0xe1c3672fbe7cf8f0
dq 0x102050b071e2c488
dq 0x112254b861c28408
dq 0x9021d234f9f2e4c8
dq 0x9123d63ce9d2a448
dq 0x50a01172b56ad4a8
dq 0x51a2157aa54a9428
dq 0xd0a193f63d7af4e8
dq 0xd1a397fe2d5ab468
dq 0x3060f0d193264c98
dq 0x3162f4d983060c18
dq 0xb06172551b366cd8
dq 0xb163765d0b162c58
dq 0x70e0b11357ae5cb8
dq 0x71e2b51b478e1c38
dq 0xf0e13397dfbe7cf8
dq 0xf1e3379fcf9e3c78
dq 0x8810a8d83871e2c4
dq 0x8912acd02851a244
dq 0x8112a5cb061c284
dq 0x9132e54a0418204
dq 0xc890e91afcf9f2e4
dq 0xc992ed12ecd9b264
dq 0x48916b9e74e9d2a4
dq 0x49936f9664c99224
dq 0xa85008b9dab56ad4
dq 0xa9520cb1ca952a54
dq 0x28518a3d52a54a94
dq 0x29538e3542850a14
dq 0xe8d0497b1e3d7af4
dq 0xe9d24d730e1d3a74
dq 0x68d1cbff962d5ab4
dq 0x69d3cff7860d1a34
dq 0x9830f8684993264c
dq 0x9932fc6059b366cc
dq 0x18317aecc183060c
dq 0x19337ee4d1a3468c
dq 0xd8b0b9aa8d1b366c
dq 0xd9b2bda29d3b76ec
dq 0x58b13b2e050b162c
dq 0x59b33f26152b56ac
dq 0xb8705809ab57ae5c
dq 0xb9725c01bb77eedc
dq 0x3871da8d23478e1c
dq 0x3973de853367ce9c
dq 0xf8f019cb6fdfbe7c
dq 0xf9f21dc37ffffefc
dq 0x78f19b4fe7cf9e3c
dq 0x79f39f47f7efdebc
dq 0xc488d46c1c3871e2
dq 0xc58ad0640c183162
dq 0x448956e8942851a2
dq 0x458b52e084081122
dq 0x840895aed8b061c2
dq 0x850a91a6c8902142
dq 0x409172a50a04182
dq 0x50b132240800102
dq 0xe4c8740dfefcf9f2
dq 0xe5ca7005eedcb972
dq 0x64c9f68976ecd9b2
dq 0x65cbf28166cc9932
dq 0xa44835cf3a74e9d2
dq 0xa54a31c72a54a952
dq 0x2449b74bb264c992
dq 0x254bb343a2448912
dq 0xd4a884dc6ddab56a
dq 0xd5aa80d47dfaf5ea
dq 0x54a90658e5ca952a
dq 0x55ab0250f5ead5aa
dq 0x9428c51ea952a54a
dq 0x952ac116b972e5ca
dq 0x1429479a2142850a
dq 0x152b43923162c58a
dq 0xf4e824bd8f1e3d7a
dq 0xf5ea20b59f3e7dfa
dq 0x74e9a639070e1d3a
dq 0x75eba231172e5dba
dq 0xb468657f4b962d5a
dq 0xb56a61775bb66dda
dq 0x3469e7fbc3860d1a
dq 0x356be3f3d3a64d9a
dq 0x4c987cb424499326
dq 0x4d9a78bc3469d3a6
dq 0xcc99fe30ac59b366
dq 0xcd9bfa38bc79f3e6
dq 0xc183d76e0c18306
dq 0xd1a397ef0e1c386
dq 0x8c19bff268d1a346
dq 0x8d1bbbfa78f1e3c6
dq 0x6cd8dcd5c68d1b36
dq 0x6ddad8ddd6ad5bb6
dq 0xecd95e514e9d3b76
dq 0xeddb5a595ebd7bf6
dq 0x2c589d1702050b16
dq 0x2d5a991f12254b96
dq 0xac591f938a152b56
dq 0xad5b1b9b9a356bd6
dq 0x5cb82c0455ab57ae
dq 0x5dba280c458b172e
dq 0xdcb9ae80ddbb77ee
dq 0xddbbaa88cd9b376e
dq 0x1c386dc69123478e
dq 0x1d3a69ce8103070e
dq 0x9c39ef42193367ce
dq 0x9d3beb4a0913274e
dq 0x7cf88c65b76fdfbe
dq 0x7dfa886da74f9f3e
dq 0xfcf90ee13f7ffffe
dq 0xfdfb0ae92f5fbf7e
dq 0x3c78cda773e7cf9e
dq 0x3d7ac9af63c78f1e
dq 0xbc794f23fbf7efde
dq 0xbd7b4b2bebd7af5e
dq 0xe2c46a368e1c3871
dq 0xe3c66e3e9e3c78f1
dq 0x62c5e8b2060c1831
dq 0x63c7ecba162c58b1
dq 0xa2442bf44a942851
dq 0xa3462ffc5ab468d1
dq 0x2245a970c2840811
dq 0x2347ad78d2a44891
dq 0xc284ca576cd8b061
dq 0xc386ce5f7cf8f0e1
dq 0x428548d3e4c89021
dq 0x43874cdbf4e8d0a1
dq 0x82048b95a850a041
dq 0x83068f9db870e0c1
dq 0x205091120408001
dq 0x3070d193060c081
dq 0xf2e43a86fffefcf9
dq 0xf3e63e8eefdebc79
dq 0x72e5b80277eedcb9
dq 0x73e7bc0a67ce9c39
dq 0xb2647b443b76ecd9
dq 0xb3667f4c2b56ac59
dq 0x3265f9c0b366cc99
dq 0x3367fdc8a3468c19
dq 0xd2a49ae71d3a74e9
dq 0xd3a69eef0d1a3469
dq 0x52a51863952a54a9
dq 0x53a71c6b850a1429
dq 0x9224db25d9b264c9
dq 0x9326df2dc9922449
dq 0x122559a151a24489
dq 0x13275da941820409
dq 0x6ad4c2eeb66ddab5
dq 0x6bd6c6e6a64d9a35
dq 0xead5406a3e7dfaf5
dq 0xebd744622e5dba75
dq 0x2a54832c72e5ca95
dq 0x2b56872462c58a15
dq 0xaa5501a8faf5ead5
dq 0xab5705a0ead5aa55
dq 0x4a94628f54a952a5
dq 0x4b96668744891225
dq 0xca95e00bdcb972e5
dq 0xcb97e403cc993265
dq 0xa14234d90214285
dq 0xb16274580010205
dq 0x8a15a1c9183162c5
dq 0x8b17a5c108112245
dq 0x7af4925ec78f1e3d
dq 0x7bf69656d7af5ebd
dq 0xfaf510da4f9f3e7d
dq 0xfbf714d25fbf7efd
dq 0x3a74d39c03070e1d
dq 0x3b76d79413274e9d
dq 0xba7551188b172e5d
dq 0xbb7755109b376edd
dq 0x5ab4323f254b962d
dq 0x5bb63637356bd6ad
dq 0xdab5b0bbad5bb66d
dq 0xdbb7b4b3bd7bf6ed
dq 0x1a3473fde1c3860d
dq 0x1b3677f5f1e3c68d
dq 0x9a35f17969d3a64d
dq 0x9b37f57179f3e6cd
dq 0x264cbe5a92244993
dq 0x274eba5282040913
dq 0xa64d3cde1a3469d3
dq 0xa74f38d60a142953
dq 0x66ccff9856ac59b3
dq 0x67cefb90468c1933
dq 0xe6cd7d1cdebc79f3
dq 0xe7cf7914ce9c3973
dq 0x60c1e3b70e0c183
dq 0x70e1a3360c08103
dq 0x860d9cbff8f0e1c3
dq 0x870f98b7e8d0a143
dq 0x468c5ff9b468d1a3
dq 0x478e5bf1a4489123
dq 0xc68ddd7d3c78f1e3
dq 0xc78fd9752c58b163
dq 0x366ceeeae3c68d1b
dq 0x376eeae2f3e6cd9b
dq 0xb66d6c6e6bd6ad5b
dq 0xb76f68667bf6eddb
dq 0x76ecaf28274e9d3b
dq 0x77eeab20376eddbb
dq 0xf6ed2dacaf5ebd7b
dq 0xf7ef29a4bf7efdfb
dq 0x162c4e8b0102050b
dq 0x172e4a831122458b
dq 0x962dcc0f8912254b
dq 0x972fc807993265cb
dq 0x56ac0f49c58a152b
dq 0x57ae0b41d5aa55ab
dq 0xd6ad8dcd4d9a356b
dq 0xd7af89c55dba75eb
dq 0xae5c1682aa55ab57
dq 0xaf5e128aba75ebd7
dq 0x2e5d940622458b17
dq 0x2f5f900e3265cb97
dq 0xeedc57406eddbb77
dq 0xefde53487efdfbf7
dq 0x6eddd5c4e6cd9b37
dq 0x6fdfd1ccf6eddbb7
dq 0x8e1cb6e348912347
dq 0x8f1eb2eb58b163c7
dq 0xe1d3467c0810307
dq 0xf1f306fd0a14387
dq 0xce9cf7218c193367
dq 0xcf9ef3299c3973e7
dq 0x4e9d75a504091327
dq 0x4f9f71ad142953a7
dq 0xbe7c4632dbb76fdf
dq 0xbf7e423acb972f5f
dq 0x3e7dc4b653a74f9f
dq 0x3f7fc0be43870f1f
dq 0xfefc07f01f3f7fff
dq 0xfffe03f80f1f3f7f
dq 0x7efd8574972f5fbf
dq 0x7fff817c870f1f3f
dq 0x9e3ce6533973e7cf
dq 0x9f3ee25b2953a74f
dq 0x1e3d64d7b163c78f
dq 0x1f3f60dfa143870f
dq 0xdebca791fdfbf7ef
dq 0xdfbea399eddbb76f
dq 0x5ebd251575ebd7af
dq 0x5fbf211d65cb972f

%else
%ifidn __OUTPUT_FORMAT__, win64
global no_gf_2vect_avx512_gfni
no_gf_2vect_avx512_gfni:
%endif
%endif  ; ifdef HAVE_AS_KNOWS_AVX512
