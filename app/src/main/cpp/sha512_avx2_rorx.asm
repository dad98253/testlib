;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Copyright (c) 2012, Intel Corporation 
; 
; All rights reserved. 
; 
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions are
; met: 
; 
; * Redistributions of source code must retain the above copyright
;   notice, this list of conditions and the following disclaimer.  
; 
; * Redistributions in binary form must reproduce the above copyright
;   notice, this list of conditions and the following disclaimer in the
;   documentation and/or other materials provided with the
;   distribution. 
; 
; * Neither the name of the Intel Corporation nor the names of its
;   contributors may be used to endorse or promote products derived from
;   this software without specific prior written permission. 
; 
; 
; THIS SOFTWARE IS PROVIDED BY INTEL CORPORATION "AS IS" AND ANY
; EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
; PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL INTEL CORPORATION OR
; CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
; PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
; LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Example YASM command lines:
; Windows:  yasm -f x64 -D WINABI sha512_rorx.asm
; Linux:    yasm -f elf64 sha512_rorx.asm
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; This code schedules 1 blocks at a time, with 4 lanes per block
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

BITS 64
section .text

; Virtual Registers
%define Y_0 ymm4
%define Y_1 ymm5
%define Y_2 ymm6
%define Y_3 ymm7

%define YTMP0 ymm0
%define YTMP1 ymm1
%define YTMP2 ymm2
%define YTMP3 ymm3
%define YTMP4 ymm8
%define XFER  YTMP0

%define BYTE_FLIP_MASK  ymm9

%ifdef WINABI
	%define INP         rcx ; 1st arg
	%define CTX         rdx ; 2nd arg
	%define NUM_BLKS    r8  ; 3rd arg
	%define c           rdi 
	%define d           rsi 
	%define e           r8
	%define y3          rcx
%else
	%define INP         rdi ; 1st arg
	%define CTX         rsi ; 2nd arg
	%define NUM_BLKS    rdx ; 3rd arg
	%define c           rcx
	%define d           r8
	%define e           rdx
	%define y3          rdi
%endif

%define TBL   rbp
	      
%define a     rax
%define b     rbx
	      
%define f     r9
%define g     r10
%define h     r11
%define old_h r11

%define T1    r12
%define y0    r13
%define y1    r14
%define y2    r15

%define y4    r12

; Local variables (stack frame)
struc frame
	.XFER:    resq  4
	.SRND:    resq  1
	.INP:     resq  1
	.INPEND:  resq  1
	.RSPSAVE: resq  1

%ifdef WINABI
	.XMMSAVE: resdq 4
	.GPRSAVE: resq  8
%else
	.GPRSAVE: resq  6
%endif
endstruc

%define	VMOVDQ vmovdqu ;; assume buffers not aligned 

; addm [mem], reg
; Add reg to mem using reg-mem add and store
%macro addm 2
	add	%2, %1
	mov	%1, %2
%endm


; COPY_YMM_AND_BSWAP ymm, [mem], byte_flip_mask
; Load ymm with mem and byte swap each dword
%macro COPY_YMM_AND_BSWAP 3
	VMOVDQ %1, %2
	vpshufb %1, %1 ,%3
%endmacro
; rotate_Ys
; Rotate values of symbols Y0...Y3
%macro rotate_Ys 0
	%xdefine %%Y_ Y_0
	%xdefine Y_0 Y_1
	%xdefine Y_1 Y_2
	%xdefine Y_2 Y_3
	%xdefine Y_3 %%Y_
%endm

; RotateState
%macro RotateState 0
	; Rotate symbles a..h right
	%xdefine old_h  h
	%xdefine %%TMP_ h
	%xdefine h      g
	%xdefine g      f
	%xdefine f      e
	%xdefine e      d
	%xdefine d      c
	%xdefine c      b
	%xdefine b      a
	%xdefine a      %%TMP_
%endm

; %macro MY_VPALIGNR	YDST, YSRC1, YSRC2, RVAL
; YDST = {YSRC1, YSRC2} >> RVAL*8
%macro MY_VPALIGNR 4
%define %%YDST 	%1
%define %%YSRC1 %2
%define %%YSRC2	%3
%define %%RVAL 	%4
	vperm2f128 	%%YDST, %%YSRC1, %%YSRC2, 0x3	; YDST = {YS1_LO, YS2_HI}
	vpalignr 	%%YDST, %%YDST, %%YSRC2, %%RVAL	; YDST = {YDS1, YS2} >> RVAL*8
%endm

%macro FOUR_ROUNDS_AND_SCHED 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 0 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

		; Extract w[t-7]
		MY_VPALIGNR	YTMP0, Y_3, Y_2, 8		; YTMP0 = W[-7]
		; Calculate w[t-16] + w[t-7]
		vpaddq		YTMP0, YTMP0, Y_0		; YTMP0 = W[-7] + W[-16]
		; Extract w[t-15]
		MY_VPALIGNR	YTMP1, Y_1, Y_0, 8		; YTMP1 = W[-15]

		; Calculate sigma0

		; Calculate w[t-15] ror 1
		vpsrlq		YTMP2, YTMP1, 1
		vpsllq		YTMP3, YTMP1, (64-1)
		vpor		YTMP3, YTMP3, YTMP2		; YTMP3 = W[-15] ror 1
		; Calculate w[t-15] shr 7
		vpsrlq		YTMP4, YTMP1, 7			; YTMP4 = W[-15] >> 7

	mov	y3, a		; y3 = a                                       ; MAJA	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B

	add	h, [rsp+frame.XFER+0*8]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	
	mov	y2, f		; y2 = f                                       ; CH	
	rorx	T1, a, 34	; T1 = a >> 34					; S0B

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	xor	y2, g		; y2 = f^g                                     ; CH	
	rorx	y1, e, 14	; y1 = (e >> 14)					; S1

	and	y2, e		; y2 = (f^g)&e                                 ; CH	
	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	add	d, h		; d = k + w + h + d                            ; --	

	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	
	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	rorx	T1, a, 28	; T1 = (a >> 28)					; S0

	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	
	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	T1, c		; T1 = a&c                                     ; MAJB	

	add	y2, y0		; y2 = S1 + CH                                 ; --	
	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	

	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	

	add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	
	add	h, y3		; h = t1 + S0 + MAJ                            ; --	

RotateState

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 1 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;

		; Calculate w[t-15] ror 8
		vpsrlq		YTMP2, YTMP1, 8
		vpsllq		YTMP1, YTMP1, (64-8)
		vpor		YTMP1, YTMP1, YTMP2		; YTMP1 = W[-15] ror 8
		; XOR the three components
		vpxor		YTMP3, YTMP3, YTMP4		; YTMP3 = W[-15] ror 1 ^ W[-15] >> 7
		vpxor		YTMP1, YTMP3, YTMP1		; YTMP1 = s0


		; Add three components, w[t-16], w[t-7] and sigma0
		vpaddq		YTMP0, YTMP0, YTMP1		; YTMP0 = W[-16] + W[-7] + s0
		; Move to appropriate lanes for calculating w[16] and w[17]
		vperm2f128	Y_0, YTMP0, YTMP0, 0x0		; Y_0 = W[-16] + W[-7] + s0 {BABA}
		; Move to appropriate lanes for calculating w[18] and w[19]
		vpand		YTMP0, YTMP0, [MASK_YMM_LO wrt rip]	; YTMP0 = W[-16] + W[-7] + s0 {DC00}

		; Calculate w[16] and w[17] in both 128 bit lanes

		; Calculate sigma1 for w[16] and w[17] on both 128 bit lanes
		vperm2f128	YTMP2, Y_3, Y_3, 0x11		; YTMP2 = W[-2] {BABA}
		vpsrlq		YTMP4, YTMP2, 6			; YTMP4 = W[-2] >> 6 {BABA}


	mov	y3, a		; y3 = a                                       ; MAJA	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	add	h, [rsp+frame.XFER+1*8]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	


	mov	y2, f		; y2 = f                                       ; CH	
	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	xor	y2, g		; y2 = f^g                                     ; CH	


	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	and	y2, e		; y2 = (f^g)&e                                 ; CH	
	add	d, h		; d = k + w + h + d                            ; --	

	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	
	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0

	rorx	T1, a, 28	; T1 = (a >> 28)					; S0
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	add	y2, y0		; y2 = S1 + CH                                 ; --	

	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	

	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	
	add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	
	add	h, y3		; h = t1 + S0 + MAJ                            ; --	

RotateState




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 2 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;


		vpsrlq		YTMP3, YTMP2, 19		; YTMP3 = W[-2] >> 19 {BABA}
		vpsllq		YTMP1, YTMP2, (64-19)		; YTMP1 = W[-2] << 19 {BABA}
		vpor		YTMP3, YTMP3, YTMP1		; YTMP3 = W[-2] ror 19 {BABA}
		vpxor		YTMP4, YTMP4, YTMP3		; YTMP4 = W[-2] ror 19 ^ W[-2] >> 6 {BABA}
		vpsrlq		YTMP3, YTMP2, 61		; YTMP3 = W[-2] >> 61 {BABA}
		vpsllq		YTMP1, YTMP2, (64-61)		; YTMP1 = W[-2] << 61 {BABA}
		vpor		YTMP3, YTMP3, YTMP1		; YTMP3 = W[-2] ror 61 {BABA}
		vpxor		YTMP4, YTMP4, YTMP3		; YTMP4 = s1 = (W[-2] ror 19) ^ (W[-2] ror 61) ^ (W[-2] >> 6) {BABA}

		; Add sigma1 to the other compunents to get w[16] and w[17]
		vpaddq		Y_0, Y_0, YTMP4			; Y_0 = {W[1], W[0], W[1], W[0]}

		; Calculate sigma1 for w[18] and w[19] for upper 128 bit lane
		vpsrlq		YTMP4, Y_0, 6			; YTMP4 = W[-2] >> 6 {DC--}

	mov	y3, a		; y3 = a                                       ; MAJA	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	add	h, [rsp+frame.XFER+2*8]		; h = k + w + h                                ; --	

	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	or	y3, c		; y3 = a|c                                     ; MAJA	
	mov	y2, f		; y2 = f                                       ; CH	
	xor	y2, g		; y2 = f^g                                     ; CH	

	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	and	y2, e		; y2 = (f^g)&e                                 ; CH	

	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	add	d, h		; d = k + w + h + d                            ; --	
	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	rorx	T1, a, 28	; T1 = (a >> 28)					; S0

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	add	y2, y0		; y2 = S1 + CH                                 ; --	

	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	
	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	
	add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	

	add	h, y3		; h = t1 + S0 + MAJ                            ; --	

RotateState

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 3 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;

		vpsrlq		YTMP3, Y_0, 19			; YTMP3 = W[-2] >> 19 {DC--}
		vpsllq		YTMP1, Y_0, (64-19)		; YTMP1 = W[-2] << 19 {DC--}
		vpor		YTMP3, YTMP3, YTMP1		; YTMP3 = W[-2] ror 19 {DC--}
		vpxor		YTMP4, YTMP4, YTMP3		; YTMP4 = W[-2] ror 19 ^ W[-2] >> 6 {DC--}
		vpsrlq		YTMP3, Y_0, 61			; YTMP3 = W[-2] >> 61 {DC--}
		vpsllq		YTMP1, Y_0, (64-61)		; YTMP1 = W[-2] << 61 {DC--}
		vpor		YTMP3, YTMP3, YTMP1		; YTMP3 = W[-2] ror 61 {DC--}
		vpxor		YTMP4, YTMP4, YTMP3		; YTMP4 = s1 = (W[-2] ror 19) ^ (W[-2] ror 61) ^ (W[-2] >> 6) {DC--}

		; Add the sigma0 + w[t-7] + w[t-16] for w[18] and w[19] to newly calculated sigma1 to get w[18] and w[19]
		vpaddq		YTMP2, YTMP0, YTMP4		; YTMP2 = {W[3], W[2], --, --}

		; Form w[19, w[18], w17], w[16]
		vpblendd		Y_0, Y_0, YTMP2, 0xF0		; Y_0 = {W[3], W[2], W[1], W[0]}
;		vperm2f128		Y_0, Y_0, YTMP2, 0x30

	mov	y3, a		; y3 = a                                       ; MAJA	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	add	h, [rsp+frame.XFER+3*8]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	


	mov	y2, f		; y2 = f                                       ; CH	
	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	xor	y2, g		; y2 = f^g                                     ; CH	


	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	and	y2, e		; y2 = (f^g)&e                                 ; CH	
	add	d, h		; d = k + w + h + d                            ; --	
	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	

	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	add	y2, y0		; y2 = S1 + CH                                 ; --	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	

	rorx	T1, a, 28	; T1 = (a >> 28)					; S0

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	

	add	h, y1		; h = k + w + h + S0                           ; --	
	add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	
	add	h, y3		; h = t1 + S0 + MAJ                            ; --	

RotateState

rotate_Ys
%endm

%macro DO_4ROUNDS 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 0 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	mov	y2, f		; y2 = f                                       ; CH	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	xor	y2, g		; y2 = f^g                                     ; CH	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	and	y2, e		; y2 = (f^g)&e                                 ; CH	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	mov	y3, a		; y3 = a                                       ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	rorx	T1, a, 28	; T1 = (a >> 28)					; S0
	add	h, [rsp + frame.XFER + 8*0]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	add	y2, y0		; y2 = S1 + CH                                 ; --	


	add	d, h		; d = k + w + h + d                            ; --	
	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	

	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	


	;add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	

	;add	h, y3		; h = t1 + S0 + MAJ                            ; --	

	RotateState

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 1 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	add	old_h, y2	; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	
	mov	y2, f		; y2 = f                                       ; CH	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	xor	y2, g		; y2 = f^g                                     ; CH	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	and	y2, e		; y2 = (f^g)&e                                 ; CH	
	add	old_h, y3	; h = t1 + S0 + MAJ                            ; --	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	mov	y3, a		; y3 = a                                       ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	rorx	T1, a, 28	; T1 = (a >> 28)					; S0
	add	h, [rsp + frame.XFER + 8*1]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	add	y2, y0		; y2 = S1 + CH                                 ; --	


	add	d, h		; d = k + w + h + d                            ; --	
	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	

	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	


	;add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	

	;add	h, y3		; h = t1 + S0 + MAJ                            ; --	

	RotateState

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 2 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	add	old_h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	
	mov	y2, f		; y2 = f                                       ; CH	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	xor	y2, g		; y2 = f^g                                     ; CH	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	and	y2, e		; y2 = (f^g)&e                                 ; CH	
	add	old_h, y3	; h = t1 + S0 + MAJ                            ; --	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	mov	y3, a		; y3 = a                                       ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	rorx	T1, a, 28	; T1 = (a >> 28)					; S0
	add	h, [rsp + frame.XFER + 8*2]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	add	y2, y0		; y2 = S1 + CH                                 ; --	


	add	d, h		; d = k + w + h + d                            ; --	
	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	

	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	


	;add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	

	;add	h, y3		; h = t1 + S0 + MAJ                            ; --	

	RotateState

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RND N + 3 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	add	old_h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	
	mov	y2, f		; y2 = f                                       ; CH	
	rorx	y0, e, 41	; y0 = e >> 41					; S1A
	rorx	y1, e, 18	; y1 = e >> 18					; S1B
	xor	y2, g		; y2 = f^g                                     ; CH	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18)			; S1
	rorx	y1, e, 14	; y1 = (e >> 14)					; S1
	and	y2, e		; y2 = (f^g)&e                                 ; CH	
	add	old_h, y3	; h = t1 + S0 + MAJ                            ; --	

	xor	y0, y1		; y0 = (e>>41) ^ (e>>18) ^ (e>>14)		; S1
	rorx	T1, a, 34	; T1 = a >> 34					; S0B
	xor	y2, g		; y2 = CH = ((f^g)&e)^g                        ; CH	
	rorx	y1, a, 39	; y1 = a >> 39					; S0A
	mov	y3, a		; y3 = a                                       ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34)			; S0
	rorx	T1, a, 28	; T1 = (a >> 28)					; S0
	add	h, [rsp + frame.XFER + 8*3]		; h = k + w + h                                ; --	
	or	y3, c		; y3 = a|c                                     ; MAJA	

	xor	y1, T1		; y1 = (a>>39) ^ (a>>34) ^ (a>>28)		; S0
	mov	T1, a		; T1 = a                                       ; MAJB	
	and	y3, b		; y3 = (a|c)&b                                 ; MAJA	
	and	T1, c		; T1 = a&c                                     ; MAJB	
	add	y2, y0		; y2 = S1 + CH                                 ; --	


	add	d, h		; d = k + w + h + d                            ; --	
	or	y3, T1		; y3 = MAJ = (a|c)&b)|(a&c)                    ; MAJ	
	add	h, y1		; h = k + w + h + S0                           ; --	

	add	d, y2		; d = k + w + h + d + S1 + CH = d + t1         ; --	


	add	h, y2		; h = k + w + h + S0 + S1 + CH = t1 + S0       ; --	

	add	h, y3		; h = t1 + S0 + MAJ                            ; --	

	RotateState

%endm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void sha512_rorx(const void* M, void* D, uint64_t L);
; Purpose: Updates the SHA512 digest stored at D with the message stored in M.
; The size of the message pointed to by M must be an integer multiple of SHA512
;   message blocks.
; L is the message length in SHA512 blocks
extern sha512_k
global sha512_rorx:function
sha512_rorx:

	; Allocate Stack Space
	mov	rax, rsp
	sub	rsp, frame_size
	and	rsp, ~(0x20 - 1)
	mov	[rsp + frame.RSPSAVE], rax

	; Save GPRs
	mov	[rsp + frame.GPRSAVE + 8 * 0], rbp
	mov	[rsp + frame.GPRSAVE + 8 * 1], rbx
	mov	[rsp + frame.GPRSAVE + 8 * 2], r12
	mov	[rsp + frame.GPRSAVE + 8 * 3], r13
	mov	[rsp + frame.GPRSAVE + 8 * 4], r14
	mov	[rsp + frame.GPRSAVE + 8 * 5], r15
%ifdef WINABI
	mov	[rsp + frame.GPRSAVE + 8 * 6], rsi
	mov	[rsp + frame.GPRSAVE + 8 * 7], rdi
%endif

%ifdef WINABI
	vmovdqa	[rsp + frame.XMMSAVE + 0*16], xmm6
	vmovdqa	[rsp + frame.XMMSAVE + 1*16], xmm7
	vmovdqa	[rsp + frame.XMMSAVE + 2*16], xmm8	
	vmovdqa	[rsp + frame.XMMSAVE + 3*16], xmm9	
%endif

	vpblendd	xmm0, xmm0, xmm1, 0xf0
	vpblendd	ymm0, ymm0, ymm1, 0xf0

	shl	NUM_BLKS, 7	; convert to bytes
	jz	done_hash
	add	NUM_BLKS, INP	; pointer to end of data
	mov	[rsp + frame.INPEND], NUM_BLKS

	;; load initial digest
	mov	a,[8*0 + CTX]
	mov	b,[8*1 + CTX]
	mov	c,[8*2 + CTX]
	mov	d,[8*3 + CTX]
	mov	e,[8*4 + CTX]
	mov	f,[8*5 + CTX]
	mov	g,[8*6 + CTX]
	mov	h,[8*7 + CTX]

	vmovdqa	BYTE_FLIP_MASK, [PSHUFFLE_BYTE_FLIP_MASK wrt rip]

loop0:
	lea	TBL,[sha512_k wrt rip]

	;; byte swap first 16 dwords
	COPY_YMM_AND_BSWAP	Y_0, [INP + 0*32], BYTE_FLIP_MASK
	COPY_YMM_AND_BSWAP	Y_1, [INP + 1*32], BYTE_FLIP_MASK
	COPY_YMM_AND_BSWAP	Y_2, [INP + 2*32], BYTE_FLIP_MASK
	COPY_YMM_AND_BSWAP	Y_3, [INP + 3*32], BYTE_FLIP_MASK
	
	mov	[rsp + frame.INP], INP

	;; schedule 64 input dwords, by doing 12 rounds of 4 each
	mov	qword[rsp + frame.SRND],4

align 16
loop1:
	vpaddq	XFER, Y_0, [TBL + 0*32]
	vmovdqa [rsp + frame.XFER], XFER
	FOUR_ROUNDS_AND_SCHED

	vpaddq	XFER, Y_0, [TBL + 1*32]
	vmovdqa [rsp + frame.XFER], XFER
	FOUR_ROUNDS_AND_SCHED

	vpaddq	XFER, Y_0, [TBL + 2*32]
	vmovdqa [rsp + frame.XFER], XFER
	FOUR_ROUNDS_AND_SCHED

	vpaddq	XFER, Y_0, [TBL + 3*32]
	vmovdqa [rsp + frame.XFER], XFER
	add	TBL, 4*32
	FOUR_ROUNDS_AND_SCHED

	sub	qword[rsp + frame.SRND], 1
	jne	loop1

	mov	qword[rsp + frame.SRND], 2
loop2:
	vpaddq	XFER, Y_0, [TBL + 0*32]
	vmovdqa [rsp + frame.XFER], XFER
	DO_4ROUNDS
	vpaddq	XFER, Y_1, [TBL + 1*32]
	vmovdqa [rsp + frame.XFER], XFER
	add	TBL, 2*32
	DO_4ROUNDS

	vmovdqa	Y_0, Y_2
	vmovdqa	Y_1, Y_3

	sub	qword[rsp + frame.SRND], 1
	jne	loop2

	addm	[8*0 + CTX],a
	addm	[8*1 + CTX],b
	addm	[8*2 + CTX],c
	addm	[8*3 + CTX],d
	addm	[8*4 + CTX],e
	addm	[8*5 + CTX],f
	addm	[8*6 + CTX],g
	addm	[8*7 + CTX],h

	mov	INP, [rsp + frame.INP]
	add	INP, 128
	cmp	INP, [rsp + frame.INPEND]
	jne	loop0

    done_hash:
%ifdef WINABI
	vmovdqa	xmm6, [rsp + frame.XMMSAVE + 0*16]
	vmovdqa	xmm7, [rsp + frame.XMMSAVE + 1*16]
	vmovdqa	xmm8, [rsp + frame.XMMSAVE + 2*16]
	vmovdqa	xmm9, [rsp + frame.XMMSAVE + 3*16]
%endif

; Restore GPRs
	mov	rbp, [rsp + frame.GPRSAVE + 8 * 0]
	mov	rbx, [rsp + frame.GPRSAVE + 8 * 1]
	mov	r12, [rsp + frame.GPRSAVE + 8 * 2]
	mov	r13, [rsp + frame.GPRSAVE + 8 * 3]
	mov	r14, [rsp + frame.GPRSAVE + 8 * 4]
	mov	r15, [rsp + frame.GPRSAVE + 8 * 5]
%ifdef WINABI
	mov	rsi, [rsp + frame.GPRSAVE + 8 * 6]
	mov	rdi, [rsp + frame.GPRSAVE + 8 * 7]
%endif
	; Restore Stack Pointer
	mov	rsp, [rsp + frame.RSPSAVE]

	ret	
	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Binary Data

section .data

align 32

; Mask for byte-swapping a couple of qwords in an XMM register using (v)pshufb.
PSHUFFLE_BYTE_FLIP_MASK: ddq 0x08090a0b0c0d0e0f0001020304050607
                         ddq 0x18191a1b1c1d1e1f1011121314151617

MASK_YMM_LO: 		 ddq 0x00000000000000000000000000000000
             		 ddq 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
