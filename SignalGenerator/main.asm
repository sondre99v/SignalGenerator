;
; SignalGenerator.asm
;
; Created: 26.02.2020 10:06:27
; Author : M51321
;

.include "tn817def.inc"
rjmp start

; 256 byte re-configurable wave-table
.dseg
	.align 0x100
	wave_table: .byte 256

; Interrupt Vector Table
.cseg
.org 0x04 rjmp isr_pb5

; PB5 pin interrupt
isr_pb5:
	push r16
	push r17
	ldi r16, 0xFF
	pb_int_loop:
		in r17, VPORTB_IN
		bst r17, 5
		brts pb_int_exit
		dec r16
		brne pb_int_loop

	; Load new wave, and cycle wave index
	cpi r20, 0
	brne pb_int_tmp1
		rcall load_triangle
		ldi r20, 1
		rjmp pb_int_exit
	pb_int_tmp1:

	cpi r20, 1
	brne pb_int_tmp2
		rcall load_pulse
		ldi r20, 2
		rjmp pb_int_exit
	pb_int_tmp2:

	rcall load_sine
	ldi r20, 0
	
	pb_int_exit:
		; Clear interrupt signal
		ser r16
		out VPORTB_INTFLAGS, r16
		pop r17
		pop r16
		reti


start:
	; Set clock source to 20 MHz, with div 2 prescaler
	ldi r16, CPU_CCP_IOREG_gc
	out CPU_CCP, r16
	ldi r16, CLKCTRL_PEN_bm
	sts CLKCTRL_MCLKCTRLB, r16

	; Enable pin-interrupt on falling edge of PB5
	ldi r16, PORT_PULLUPEN_bm | PORT_ISC_FALLING_gc
	sts PORTB_PIN5CTRL, r16

	; Set DACs VREF to 2V5
	ldi r16, VREF_DAC0REFSEL_2V5_gc
	sts VREF_CTRLA, r16

	; Enable DAC
	ldi r16, DAC_OUTEN_bm | DAC_ENABLE_bm
	sts DAC0_CTRLA, r16

	; r20 used as wave index
	; 0 - Sine, 1 - Triangle, 2 - Pulse
	ldi r20, 1

	; Load initial wave table
	rcall load_triangle

	; r19 used as wave shape parameter
	;   Sine:     N/A
	;   Triangle: Symmetry
	;   Pulse:    Duty
	ldi r19, 211

	; Set X = DAC0.DATA
	ldi XH, HIGH(DAC0_DATA)
	ldi XL, LOW(DAC0_DATA)

	; Set Z = wave_table
	ldi ZH, HIGH(wave_table)
	
	; Phase accumulator = ZL:r22:r21
	clr ZL
	clr r22
	clr r21

	; Phase step = r25:r24:r23
	ldi r25, 0
	ldi r24, 0x20
	ldi r23, 0

	; Enable global interrupts
	sei

	; Start main synthesis-loop
	loop:
		; Output sample
		ld r16, Z
		st X, r16

		; Accumulate phase
		add r21, r23
		adc r22, r24
		adc ZL, r25

		rjmp loop


.cseg
	.align 0x100
	sine_table: 
	.db 0x80, 0x83, 0x86, 0x89, 0x8C, 0x8F, 0x92, 0x95, 0x98, 0x9C, 0x9F, 0xA2, 0xA5, 0xA8, 0xAB, 0xAE, \
		0xB0, 0xB3, 0xB6, 0xB9, 0xBC, 0xBF, 0xC1, 0xC4, 0xC7, 0xC9, 0xCC, 0xCE, 0xD1, 0xD3, 0xD5, 0xD8, \
		0xDA, 0xDC, 0xDE, 0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA, 0xEC, 0xED, 0xEF, 0xF0, 0xF2, 0xF3, 0xF5, \
		0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFC, 0xFD, 0xFE, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
	
	; Load the wave table with a sine function
	load_sine:
		push ZH
		push ZL
		push XH
		push XL
		push r16
		push r17
		ldi ZH, HIGH(sine_table << 1)
		ldi XH, HIGH(wave_table)
		clr XL ; Loop variable
		ldi r17, 65
		load_sine_loop:
			mov ZL, XL
			andi ZL, 0x3F
			; Check 2nd MS bit to see if index should be inverted
			bst XL, 6
			brtc ld_sine_dont_inv_index
				com ZL
				add ZL, r17
			ld_sine_dont_inv_index:
			; Load sample to r16
			lpm r16, Z
			; Check MS bit to see if sample should be inverted
			bst XL, 7
			brtc ld_sine_dont_inv_sampl
				com r16
				inc r16
			ld_sine_dont_inv_sampl:

			st X, r16
			inc XL
			brne load_sine_loop
		pop r17
		pop r16
		pop XL
		pop XH
		pop ZL
		pop ZH
		ret

	; Load the wave table with a triangle function
	load_triangle:
		push XH
		push XL
		push r16
		push r17
		ldi XH, HIGH(wave_table)
		clr r17 ; Loop variable
		load_triangle_loop_1:
			mul r19, r17
			mov XL, r1
			st X, r17
			inc r17
			brne load_triangle_loop_1
		ser r17
		load_triangle_loop_2:
			clr r16
			sub r16, r19
			mul r16, r17
			ldi XL, 255
			sub XL, r1
			st X, r17
			dec r17
			brne load_triangle_loop_2
		pop r17
		pop r16
		pop XL
		pop XH
		ret

	; Load the wave table with a pulse function
	load_pulse:
		push XH
		push XL
		push r16
		push r17
		ldi XH, HIGH(wave_table)
		clr XL
		clr r16
		ser r17
		cp r19, r16
		breq load_pulse_loop_2 ; Skip loop 1 if duty-cycle is 0%
		load_pulse_loop_1:
			st X+, r17
			cp XL, r19
			brne load_pulse_loop_1
		cp r19, r17
		breq load_pulse_exit ; Skip loop 2 if duty-cycle is 100%
		load_pulse_loop_2:
			st X+, r16
			cpi XL, 0
			brne load_pulse_loop_2
		load_pulse_exit:
		pop r17
		pop r16
		pop XL
		pop XH
		ret
