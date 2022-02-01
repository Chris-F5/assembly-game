section .data
    fbDir db "/dev/fb0", 0
    kbDir db "/dev/input/by-id/usb-SONiX_USB_DEVICE-event-kbd", 0

    screenW dq 1920
    screenRowSize dq 1920 * 4
    screenH dq 1080
    fbSize dq 1920 * 1080 * 4

    ballPos dq 50000, 500000
    ballVel dq -1, -1

    paddlePos dq 50, 50000

    pointBuf1 dq 50, 1000
    pointBuf2 dq 50, 1000

    pointA dq 500, 500
    pointB dq 900, 800

    vec2Buffer dq 0,0

    keyQ dw 0
    keyUp dw 0
    keyDown dw 0
    keyLeft dw 0
    keyRight dw 0

section .bss
    sb resb 1920 * 1080 * 4 ; staging buffer
    fbfd resb 8 ; frame buffer file descriptor
    kbfd resb 8 ; keyboard file descriptor

section .text
    global _start

_start:
; open framebuffer
    mov rax, 2; sys_open
    mov rdi, fbDir
    mov rsi, 64+1; O_CREAT+O_WRONLY
    mov rdx, 0644o
    syscall
    mov [fbfd], rax

; open keyboard
    mov rax, 2 ; sys_open
    mov rdi, kbDir
    mov rsi, 4000 ; O_RDONLY | O_NOBLOCK
    mov rdx, 0644o 
    syscall
    mov [kbfd], rax

; set graphics mode
;    mov rax, 16 ; sys_ioctl
;    mov rdi, 1 ; std out
;    mov rsi, 0x4B3A ; KDSETMODE
;    mov rdx, 1 ; graphics
;    syscall

_mainloop:
    call readkbinput

    call clearsb

    mov eax, [keyUp]
    cmp eax, 1
    jne _mainloop_notkeydown_up
    sub qword [paddlePos + 8], 50
_mainloop_notkeydown_up:
    mov eax, [keyDown]
    cmp eax, 1
    jne _mainloop_notkeydown_down
    add qword [paddlePos + 8], 50
_mainloop_notkeydown_down:
    mov eax, [keyLeft]
    cmp eax, 1
    jne _mainloop_notkeydown_left
    sub qword [ballVel], 1
_mainloop_notkeydown_left:
    mov eax, [keyRight]
    cmp eax, 1
    jne _mainloop_notkeydown_right
    add qword [ballVel], 1
_mainloop_notkeydown_right:

    mov rax, [ballPos]
    mov rbx, [ballVel]
    add rax, rbx
    mov [ballPos], rax
    mov rax, [ballPos + 8]
    mov rbx, [ballVel + 8]
    add rax, rbx
    mov [ballPos + 8], rax

    ; ball world to screen
    push ballPos
    push pointA
    call worldtoscreenpos
    pop rax
    pop rax

    ; draw ball
    mov rax, pointA
    mov rbx, pointB
    mov ecx, 0x00ff00ff
    call drawline

    ; draw paddle
    mov rax, [paddlePos]
    mov [vec2Buffer], rax
    mov rax, [paddlePos + 8]
    sub rax, 1000; half paddle height
    mov [vec2Buffer + 8], rax
    push vec2Buffer
    push pointBuf1
    call worldtoscreenpos
    pop rax
    pop rax

    mov rax, [paddlePos]
    mov [vec2Buffer], rax
    mov rax, [paddlePos + 8]
    add rax, 1000; half paddle height
    mov [vec2Buffer + 8], rax
    push vec2Buffer
    push pointBuf2
    call worldtoscreenpos
    pop rax
    pop rax

    mov rax, pointBuf1
    mov rbx, pointBuf2
    mov ecx, 0x00ffffff
    call drawline

    call flushsb

    mov eax, [keyQ]
    cmp eax, 1
    jne _mainloop

; unset graphics mode
    mov rax, 16 ; sys_ioctl
    mov rdi, 1 ; std out
    mov rsi, 0x4B3A ; KDSETMODE
    mov rdx, 0 ; text
    syscall

; close files
    mov rax, 3; sys_close
    mov rdi, [fbfd]
    syscall
    mov rax, 3
    mov rdi, [kbfd]
    syscall

; exit
    mov rax, 60
    mov rdi, 0
    syscall

readkbinput:
    push rbp
    mov rbp, rsp

    sub rsp, 24
    ; [rbp - 4] 4byte uint value (0 key release, 1 key press)
    ; [rbp - 6] 2byte uint code
    ; [rbp - 8] 2byte uint type
    ; [rbp - 24] 16byte time info
    ; see "/usr/include/linux/input-event-codes.h"

    mov rax, 0 ; sys_read
    mov rdi, [kbfd]
    mov rsi, rsp ; buffer
    mov rdx, 24 ; read size
    syscall

    cmp rax, 24
    jne _readkbinput_end ; if no events end

    mov eax, [rbp - 4] ; key value
    cmp eax, 1 ; keypress
    je _readkbinput_allowedvalue
    cmp eax, 0 ; keyrelease
    je _readkbinput_allowedvalue
    jmp _readkbinput_end
_readkbinput_allowedvalue:
    mov bx, [rbp - 6] ; key code
    ; eax is key up or down
    ; bx is key code

    cmp bx, 103 ; KEY_UP
    je _readkbinput_key_up
    cmp bx, 108 ; KEY_DOWN
    je _readkbinput_key_down
    cmp bx, 105 ; KEY_LEFT
    je _readkbinput_key_left
    cmp bx, 106 ; KEY_RIGHT
    je _readkbinput_key_right
    cmp bx, 16 ; KEY_Q
    je _readkbinput_key_q
    jmp _readkbinput_end
_readkbinput_key_up:
    mov [keyUp], eax
    jmp _readkbinput_end
_readkbinput_key_down:
    mov [keyDown], eax
    jmp _readkbinput_end
_readkbinput_key_left:
    mov [keyLeft], eax
    jmp _readkbinput_end
_readkbinput_key_right:
    mov [keyRight], eax
    jmp _readkbinput_end
_readkbinput_key_q:
    mov [keyQ], eax
    jmp _readkbinput_end
_readkbinput_end:
    mov rsp, rbp
    pop rbp
    ret

; input: top 4bytes stack [rsp + 8] : output pos pointer
; input: next 4bytes stack [rsp + 16] : input pos pointer
worldtoscreenpos:
    mov rbx, [rsp + 16] ; input pos pointer
    mov rax, [rbx] ; x in
    mov rcx, 1080
    imul rcx
    mov rcx, 100000 ; screen is 100000 world coordinates tall
    cqo
    idiv rcx
    mov rbx, [rsp + 8] ; output pos pointer
    mov [rbx], rax ; x out

    mov rbx, [rsp + 16] ; input pos pointer
    mov rax, [rbx + 8] ; y in
    mov rcx, 1080
    imul rcx
    mov rcx, 100000
    cqo
    idiv rcx
    mov rbx, [rsp + 8] ; output pos pointer
    mov [rbx + 8], rax ; y out

    ret

; input: rax : pointer to point 1 {x1, y1} each 64 bit number
; input: rbx : pointer to point 2 {x2, y2} each 64 bit number
; input: ecx : color
drawline:
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

; FIND DIFFS
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

; FIND START PIXEL
    mov rcx, [rax] ; x1
    mov rax, [rax + 8] ; y1
    mul qword [screenW]
    add rax, rcx
    mov rcx,  4
    mul rcx
    mov rcx, rax
    ; rcx is start px

; FIND END PIXEL
    mov rax, [rbx + 8] ; y2
    mul qword [screenW]
    add rax, [rbx] ; x2
    mov rbx, 4
    mul rbx
    mov [rbp - 8], rax ; targetpx

; XDIFF * 2
    mov rax, [rbp - 24] ; xdiff
    mov rbx, 2
    mul rbx
    mov [rbp - 48], rax ; xdiff * 2

; DRAW LINE
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
    cmp rcx, [fbSize]
    jge _drawline_drawpx_nodraw
    mov rax, [rbp - 60] ; xcoord
    cmp rax, 0
    jl _drawline_drawpx_nodraw
    cmp rax, [screenW]
    jge _drawline_drawpx_nodraw
    mov [sb + rcx], edx ; draw
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

clearsb:
    mov rax, 0
_clearsb_next:
    mov dword [sb + rax],  0
    add rax, 4
    cmp rax, [fbSize]
    jne _clearsb_next
    ret

flushsb:
    mov rdi, [fbfd]
    mov rax, 8 ; sys_lseek
    mov rsi, 0
    mov rdx, 0
    syscall

    mov rax, 1 ; sys_write
    mov rsi, sb
    mov rdx, 4 * 1920 * 1080
    syscall
    ret
