.nolist
.include "m328Pdef.inc"
.list

.def temp = R16
.def x0 = R17
.def y4 = R19
.def res = R22
.def tmp = R18 ; for interrupts
.def overflows = R24
.def send = R25

.equ freq = 12000000
.equ baudrate = 9600
.equ bauddivider = freq/(16*baudrate)-1

.dseg
;interrupts
.cseg
	.ORG	$000        ; (RESET) 
	JMP		Reset
	;.ORG	OVF1addr
	;JMP		tim1_ovf
	.org OVF0addr
	jmp overflow_handler
	;.ORG	URXCaddr
	;JMP		RX_ok
	;.ORG	UTXCaddr
	;JMP		TX_ok
	.ORG	ADCCaddr
	JMP		ADC_conversion

	.org   INT_VECTORS_SIZE
;end interrupts

Reset:
;Инициализация стека
	LDI 	R16,Low(RAMEND)	
	OUT 	SPL,R16			
	LDI 	R16,High(RAMEND)
	OUT 	SPH,R16
;---
;Настройка ADC
	LDS		R16, ADMUX
	ORI		R16, 1 << REFS0 ; Выставляю AVCC with external capacitor at AREF pin. Также 0 канал.  ????? 0 или 1???? что лучше
	STS		ADMUX, R16
	LDS		R16, ADCSRA
	ORI		R16, 1 << ADEN | 1 << ADSC | 1 << ADIF | 1 << ADIE | 1 << ADPS2 | 1 << ADPS1 ; включаю и настраиваю
	STS		ADCSRA, R16
;---
;portd
	LDI R16, 0xFF
	OUT	DDRD, R16
;---
;Настройка таймера0
	LDI	temp, 5			; set the Clock Selector Bits CS00, CS01, CS02 to 101
	OUT	TCCR0B, temp		; this puts Timer Counter0, TCNT0 in to FCPU/1024 mode
					; so it ticks at the CPU freq/1024

	LDI	temp, 0b00000001	; set the Timer Overflow Interrupt Enable (TOIE0) bit 
	STS	TIMSK0, temp		; of the Timer Interrupt Mask Register (TIMSK0)

	CLR	temp
	OUT	TCNT0, temp		; initialize the Timer/Counter to 0

;---
	LDI overflows, 0

	RCALL	USART_Init_9600		; initialize the serial communications

	SEI

Main:
	RCALL	delay
	RCALL	delay
	
	MOV x0, R20
	;start adc
	LDS		R16, ADMUX
	ORI		R16, 1 << REFS0 | 0 << ADLAR | 1 << MUX2; выставляю AVCC with external capacitor at AREF pin. Также 4 канал.
	STS		ADMUX, R16
	LDS		R16, ADCSRA
	ORI		R16, 1 << ADEN | 1 << ADSC | 1 << ADIF | 1 << ADIE | 1 << ADPS2 | 1 << ADPS1 ; включаю и настраиваю
	STS		ADCSRA, R16
	
	MOV y4, R20
	;LDI R25, 'G'
	;вариант3
	
	;x*y
	MOV res, x0
	MUL res, y4
	;5*y
	LDI temp, 5
	MUL y4, temp
	;x^2
	MOV temp, x0
	MUL x0, temp
	;x*y+5y
	ADC res, y4
	;x*y+5y+x^2
	ADC res, x0

	MOV send, res

	RCALL USART_Transmit
	;RCALL newline
	;start adc
	LDS		R16, ADMUX
	ORI		R16, 1 << REFS0 | 0 << ADLAR; выставляю AVCC with external capacitor at AREF pin. Также 0 канал.
	STS		ADMUX, R16
	LDS		R16, ADCSRA
	ORI		R16, 1 << ADEN | 1 << ADSC | 1 << ADIF | 1 << ADIE | 1 << ADPS2 | 1 << ADPS1 ; включаю и настраиваю
	STS		ADCSRA, R16
	
	RCALL	delay
	RCALL	delay

	JMP	Main
;functions
USART_Init_9600:
	; these values are for 9600 Baud with a 16MHz clock
	LDI	r16, 103
	CLR	r17

	; Set baud rate
	STS	UBRR0H, r17
	STS	UBRR0L, r16

	; Enable receiver and transmitter
	LDI	r16, (1<<RXEN0)|(1<<TXEN0)
	STS	UCSR0B, r16

	; Set frame format: Async, no parity, 8 data bits, 1 stop bit
	LDI	r16, 0b00001110
	STS	UCSR0C, r16
	RET
USART_Transmit:
	; wait for empty transmit buffer
	LDS	temp, UCSR0A
	SBRS	temp, UDRE0
	RJMP	USART_Transmit

	; Put data (r25) into buffer, sends the data
	STS	UDR0, R25
	RET

newline:
	; send cr to the USART
	LDI	r25, $0D
	RCALL	USART_Transmit

	; send newline to the USART
	LDI	r25, $0A
	RCALL	USART_Transmit

	; wait for a bit
	RCALL	delay
	RET

delay:
	CLR	overflows		; set overflows to 0 
sec_count:
	MOV	temp, overflows		; compare number of overflows and 6
	CPI	temp, 6
	BRNE	sec_count		; branch to back to sec_count if not equal 
	RET				; if 61 overflows have occured return

;---
;interrupts
overflow_handler:
	CLI
	INC	overflows

	SEI
	RETI


ADC_conversion:
	CLI
	LDS R20, ADCL
	LDS R21, ADCH ;use
	;OUT PORTD, R18

	SEI
	RETI	