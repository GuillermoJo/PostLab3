
.include "m328pdef.inc"

; ? Definiciones ?
.def zero      = r1       ; registro cero permanente
.def dig_u     = r20      ; digito unidades
.def dig_d     = r21      ; digito decenas
.def ms_cnt    = r22      ; contador de interrupciones (~10ms c/u)
.def mux_flag  = r23      ; bandera multiplexado: 0=unidades 1=decenas

.org 0x0000
    rjmp inicio

; ? Interrupcion Timer0 CompareA ?
.org OC0Aaddr
    rjmp isr_t0a

inicio:
    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16

    clr zero

; ? Configurar pines de salida ?
    ldi r16, 0b11111100
    out DDRD, r16
    out PORTD, zero

; PB0 = segmento g, PB1 = unidades, PB2 = decenas
    sbi DDRB, 0
    sbi DDRB, 1
    sbi DDRB, 2
    out PORTB, zero

; ? Limpiar variables ?
    clr dig_u
    clr dig_d
    clr ms_cnt
    clr mux_flag

; ? Timer0 en modo CTC ?
; Frecuencia base 16MHz / 1024 = 15625 Hz ? periodo 64us
; OCR0A = 155  ?  (155+1) * 64us ? 9.984ms por interrupcion
    ldi r16, (1<<WGM01)
    out TCCR0A, r16

    ldi r16, (1<<CS02)|(1<<CS00)   ; prescaler /1024
    out TCCR0B, r16

    ldi r16, 155
    out OCR0A, r16

; Habilitar interrupcion OC0A
    ldi r16, (1<<OCIE0A)
    sts TIMSK0, r16

    sei                    ; habilitar interrupciones globales

bucle:
    rjmp bucle             ; todo ocurre en la ISR

; ISR Timer0 Compare Match A
isr_t0a:
    push r16
    push r17
    push r18
    push r19
    push r30
    push r31

; ? Apagar ambos displays ?
    cbi PORTB, 1
    cbi PORTB, 2

; ? Alternar flag de multiplexado ?
    ldi r16, 0x01
    eor mux_flag, r16

; ? Seleccionar digito activo ?
    tst mux_flag
    breq mostrar_unidades
    mov r17, dig_d         ; mux_flag=1 decenas
    rjmp buscar_patron

mostrar_unidades:
    mov r17, dig_u         ; mux_flag=0 unidades

; ? Leer patron de la tabla ?
buscar_patron:
    ldi r30, low(seg_tabla<<1)
    ldi r31, high(seg_tabla<<1)
    add r30, r17
    adc r31, zero
    lpm r18, Z             ; r18 = patron 7seg del digito

; ? Enviar segmentos a-f a PORTD ?
    mov r19, r18
    andi r19, 0x3F         ; conservar bits 0-5 (segmentos a-f)
    lsl r19
    lsl r19                ; desplazar a posicion PD2
    out PORTD, r19

; ? Enviar segmento g a PB0 ?
    sbrs r18, 6
    rjmp seg_g_apagado
    sbi PORTB, 0
    rjmp activar_enable

seg_g_apagado:
    cbi PORTB, 0

; ? Activar enable del display correspondiente ?
activar_enable:
    tst mux_flag
    breq en_unidades
    sbi PORTB, 2           ; decenas activas
    rjmp actualizar_tiempo

en_unidades:
    sbi PORTB, 1           ; unidades activas

; ? Logica de conteo de tiempo ?
actualizar_tiempo:
    inc ms_cnt
    cpi ms_cnt, 100        ; 100 * ~10ms = ~1 segundo
    brlo fin_isr

    clr ms_cnt

; Incrementar unidades
    inc dig_u
    cpi dig_u, 10
    brlo revisar_limite

    clr dig_u
    inc dig_d              ; carry a decenas

; Reinicio al llegar a 60 segundos
revisar_limite:
    cpi dig_d, 6
    brne fin_isr
    clr dig_d
    clr dig_u

; ? Restaurar contexto y retornar ?
fin_isr:
    pop r31
    pop r30
    pop r19
    pop r18
    pop r17
    pop r16
    reti

; Tabla de patrones 7 segmentos
; bit0=a  bit1=b  bit2=c  bit3=d  bit4=e  bit5=f  bit6=g
seg_tabla:
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D
    .db 0x7D, 0x07, 0x7F, 0x6F, 0x77, 0x7C
    .db 0x39, 0x5E, 0x79, 0x71