%include "config.asm"

STDOUT equ 1

SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_LSEEK equ 8
SYS_IOCTL equ 16
SYS_EXIT equ 60

KDSETMODE equ 0x4B3A

PADDLE_X equ 2000

section .data
    fbDir db FRAMEBUFFER, 0
    kbDir db KEYBOARD_DEVICE, 0

    screenW dq 1920
    screenRowSize dq 1920 * 4
    screenH dq 1080
    screenSize dq 1920 * 1080 * 4

    paddleY dq 50000

    pointA dq 100, 200
    pointB dq 500, 700

    worldH dq 100000
    worldW dq 0 ; set at runtime

    paddleHalfSize dq 5000

section .bss
    stagingBuffer resb 1920 * 1080 * 4
    frameBufFile resb 8
    keyboardFile resb 8

    upKey resb 1
    downKey resb 1
    exit resb 1

section .text
    global _start

_start:
; open framebuffer
    mov rax, SYS_OPEN
    mov rdi, fbDir
    mov rsi, 1 ; O_WRONLY
    mov rdx, 0644o
    syscall
    mov [frameBufFile], rax

; open keyboard
    mov rax, SYS_OPEN
    mov rdi, kbDir
    mov rsi, 4000 ; O_RDONLY | O_NOBLOCK
    mov rdx, 0644o 
    syscall
    mov [keyboardFile], rax

; set graphics mode
;    mov rax, SYS_IOCTL 
;    mov rdi, STDOUT
;    mov rsi, KDSETMODE
;    mov rdx, 1 ; graphics mode
;    syscall

; set worldW
    mov rax, [worldH]
    mov rbx, [screenW]
    mul rbx
    mov rbx, [screenH]
    cqo
    div rbx
    mov [worldW], rax

_mainloop:
    call _readKeyboardInput

    call _clearStagingBuffer

; handle input
    cmp byte [upKey], 1
    jne _mainloop_notkeypress_up
    sub qword [paddleY], PADDLE_SPEED
_mainloop_notkeypress_up:
    cmp byte [downKey], 1
    jne _mainloop_notkeypress_down
    add qword [paddleY], PADDLE_SPEED
_mainloop_notkeypress_down:

; draw paddle
    mov qword [pointA], PADDLE_X
    mov rax, [paddleY]
    sub rax, [paddleHalfSize]
    mov [pointA + 8], rax
    mov rax, pointA
    mov rbx, pointA
    call _worldToScreen

    mov qword [pointB], PADDLE_X
    mov rax, [paddleY]
    add rax, [paddleHalfSize]
    mov [pointB + 8], rax
    mov rax, pointB
    mov rbx, pointB
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, 0x00ffffff
    call _drawline

    call _flushStagingBuffer

    mov eax, [exit]
    cmp eax, 1
    jne _mainloop

; unset graphics mode
    mov rax, SYS_IOCTL
    mov rdi, STDOUT
    mov rsi, KDSETMODE
    mov rdx, 0 ; text mode
    syscall

; close files
    mov rax, SYS_CLOSE
    mov rdi, [frameBufFile]
    syscall
    mov rax, SYS_CLOSE
    mov rdi, [keyboardFile]
    syscall

; exit
    mov rax, SYS_EXIT
    mov rdi, 0 ; exit code
    syscall

; input: rax : pointer to input world pos {x1, y1} each 64 bit number
; output: rbx : pointer to output screen pos {x1, y1} each 64 bit number
_worldToScreen:
    push rax

    mov rax, [rax] ; x in
    mov rcx, [screenH]
    imul rcx ; x *= screenH
    mov rcx, [worldH]
    cqo
    idiv rcx ; x /= worldH
    mov [rbx], rax ; x out

    pop rax

    mov rax, [rax + 8] ; y in
    mov rcx, [screenH]
    imul rcx ; y *= screenH
    mov rcx, [worldH]
    cqo
    idiv rcx ; y /= worldH
    mov [rbx + 8], rax ; y out

    ret
    
; ===USER INPUT===

_readKeyboardInput:
    push rbp
    mov rbp, rsp

    sub rsp, 24
    ; [rbp - 4] 4byte uint value (0 key release, 1 key press)
    ; [rbp - 6] 2byte uint code
    ; [rbp - 8] 2byte uint type
    ; [rbp - 24] 16byte time info
    ; see "/usr/include/linux/input-event-codes.h"

    mov rax, SYS_READ
    mov rdi, [keyboardFile]
    mov rsi, rsp ; buffer
    mov rdx, 24 ; read size
    syscall

    cmp rax, 24
    jne _readKeyboardInput_end ; if no events end

    mov eax, [rbp - 4] ; key value
    cmp eax, 1 ; keypress
    je _readKeyboardInput_allowedvalue
    cmp eax, 0 ; keyrelease
    je _readKeyboardInput_allowedvalue
    jmp _readKeyboardInput_end
_readKeyboardInput_allowedvalue:
    mov bx, [rbp - 6] ; key code
    ; al is key up or down
    ; bx is key code

    cmp bx, KEY_UP
    je _readKeyboardInput_up
    cmp bx, KEY_DOWN 
    je _readKeyboardInput_down
    cmp bx, EXIT_KEY_1
    je _readKeyboardInput_exit
    cmp bx, EXIT_KEY_2
    je _readKeyboardInput_exit
    cmp bx, EXIT_KEY_3
    je _readKeyboardInput_exit
    jmp _readKeyboardInput_end
_readKeyboardInput_up:
    mov [upKey], al
    jmp _readKeyboardInput_end
_readKeyboardInput_down:
    mov [downKey], al
    jmp _readKeyboardInput_end
_readKeyboardInput_exit:
    mov byte [exit], 1
    jmp _readKeyboardInput_end
_readKeyboardInput_end:
    mov rsp, rbp
    pop rbp
    ret

; ===RENDERING===

; input: rax : pointer to point 1 {x1, y1} each 64 bit number
; input: rbx : pointer to point 2 {x2, y2} each 64 bit number
; input: ecx : color
_drawline:
    push rbp
    mov rbp, rsp

    sub rsp, 60
    ; [rbp - 8] 8byte : target px
    ; [rbp - 16] 8byte : x inc
    ; [rbp - 24] 8byte : x diff
    ; [rbp - 32] 8byte : y inc
    ; [rbp - 40] 8byte : y diff
    ; [rbp - 48] 8byte : x diff * 2
    ; [rbp - 52] 4byte : col
    ; [rbp - 60] 8byte : x coord

    mov [rbp - 52], ecx
    mov rcx, [rax] ; x1
    mov [rbp - 60], rcx ; x coord
; find diffs
    mov rcx, [rbx] ; x2
    cmp rcx, [rax] ; x1
    jge _drawline_x2larger
; x1 larger
    mov qword [rbp - 16], -1 ; x inc
    mov rcx, [rax] ; x1
    sub rcx, [rbx] ; rcx = x1 - x2
    jmp _drawline_finishxcheck
_drawline_x2larger:
    mov qword [rbp - 16], 1 ; x inc
    mov rcx, [rbx] ; x2
    sub rcx, [rax] ; rcx = x2 - x1
_drawline_finishxcheck:
    add rcx, 1
    mov [rbp - 24], rcx ; xdiff = rcx
    mov rcx, [rbx + 8] ; y2
    cmp rcx, [rax + 8] ; y1
    jge _drawline_y2larger
; y1 larger
    mov qword [rbp - 32], -1 ; y inc
    mov rcx, [rax + 8] ; y1
    sub rcx, [rbx + 8] ; rcx = y1 - y2
    jmp _drawline_finishycheck
_drawline_y2larger:
    mov qword [rbp - 32], 1 ; y inc
    mov rcx, [rbx + 8] ; y2
    sub rcx, [rax + 8] ; rcx = y2 - y1
_drawline_finishycheck:
    add rcx, 1
    mov [rbp - 40], rcx ; ydiff = rcx
; find start pixel
    mov rcx, [rax] ; x1
    mov rax, [rax + 8] ; y1
    mul qword [screenW]
    add rax, rcx
    mov rcx,  4
    mul rcx
    mov rcx, rax
    ; rcx is start px
; find end pixel
    mov rax, [rbx + 8] ; y2
    mul qword [screenW]
    add rax, [rbx] ; x2
    mov rbx, 4
    mul rbx
    mov [rbp - 8], rax ; targetpx
; xdiff * 2
    mov rax, [rbp - 24] ; xdiff
    mov rbx, 2
    mul rbx
    mov [rbp - 48], rax ; xdiff * 2
; draw line
    ; rcx is current px
    mov rbx, 0 ; rbx is i
    mov edx, [rbp - 52] ; edx is color
_drawline_next:
    call _drawline_drawpx
    add rbx, [rbp - 40] ; i += ydiff
_drawline_yfaraboverepeat:
    cmp rbx, [rbp - 48] ; xdiff * 2
    jl _drawline_ynotfarabove ; i < xdiff*2
    sub rbx, [rbp - 24] ; i -= xdiff
    call _drawline_incy
    call _drawline_drawpx
    cmp rcx, [rbp - 8]
    je _drawline_endline ; currentpx == targetpx
    jmp _drawline_yfaraboverepeat
_drawline_ynotfarabove:
    cmp rbx, [rbp - 24] ; xdiff
    jl _drawline_nextx ; i < xdiff
    sub rbx, [rbp - 24] ; i -= xdiff
    call _drawline_incy
_drawline_nextx:
    call _drawline_incx
    cmp rcx, [rbp - 8]
    jne _drawline_next ; currentpx != targetpx
_drawline_endline:
    mov rsp, rbp
    pop rbp
    ret

_drawline_drawpx:
    cmp rcx, 0
    jl _drawline_drawpx_nodraw
    cmp rcx, [screenSize]
    jge _drawline_drawpx_nodraw
    mov rax, [rbp - 60] ; xcoord
    cmp rax, 0
    jl _drawline_drawpx_nodraw
    cmp rax, [screenW]
    jge _drawline_drawpx_nodraw
    mov [stagingBuffer + rcx], edx ; draw
_drawline_drawpx_nodraw:
    ret
_drawline_incx:
    push rax
    mov rax, [rbp - 16] ; x inc
    cmp rax, 1
    je _drawline_incx_add
    sub rcx, 4 ; x -= 1
    sub qword [rbp - 60], 1 ; xcoord -= 1
    jmp _drawline_incx_end
_drawline_incx_add:
    add rcx, 4 ; x += 1
    add qword [rbp - 60], 1 ; xcoord -= 1
_drawline_incx_end:
    pop rax
    ret
_drawline_incy:
    push rax
    mov rax, [rbp - 32] ; y inc
    cmp rax, 1
    je _drawline_incy_add
    sub rcx, [screenRowSize] ; y -= 1
    jmp _drawline_incy_end
_drawline_incy_add:
    add rcx, [screenRowSize] ; y += 1
_drawline_incy_end:
    pop rax
    ret

_clearStagingBuffer:
    push rax

    mov rax, 0
_clearStagingBuffer_loop:
    mov dword [stagingBuffer + rax],  0
    add rax, 4
    cmp rax, [screenSize]
    jne _clearStagingBuffer_loop

    pop rax
    ret

_flushStagingBuffer:
    push rax
    push rdx

    mov rdi, [frameBufFile]
    mov rax, SYS_LSEEK
    mov rsi, 0
    mov rdx, 0
    syscall

    mov rax, SYS_WRITE
    mov rsi, stagingBuffer
    mov rdx, [screenSize]
    syscall

    pop rdx
    pop rax
    ret
