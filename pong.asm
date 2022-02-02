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
BALL_RADIUS equ 1000

section .data
    fbDir db FRAMEBUFFER, 0
    kbDir db KEYBOARD_DEVICE, 0

    screenW dq SCREEN_RES_X
    screenRowSize dq SCREEN_RES_X * 4
    screenH dq SCREEN_RES_Y
    screenSize dq SCREEN_RES_X * SCREEN_RES_Y * 4

    leftPaddleY dq 50000
    rightPaddleY dq 50000

    pointA dq 0, 0
    pointB dq 0, 0

    worldH dq 100000
    worldW dq 0 ; set at runtime

    randBallYVel dq -200, -150, -100, -60, -50, -40, -30, -15, 200, 150, 100, 60, 50, 40, 30, 15

    paddleHalfSize dq 5000

section .bss
    stagingBuffer resb SCREEN_RES_X * SCREEN_RES_Y * 4
    frameBufFile resb 8
    keyboardFile resb 8

    ballPos resb 16
    ballVel resb 16

    leftPaddleUpKey resb 1
    leftPaddleDownKey resb 1
    rightPaddleUpKey resb 1
    rightPaddleDownKey resb 1
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

; set ballVel
    mov qword [ballVel], -200
    mov qword [ballVel + 8], -10
; set ballPos to middle of screen
    mov rax, [worldW]
    mov rbx, 2
    cqo
    div rbx
    mov [ballPos], rax
    mov rax, [worldH]
    mov rbx, 2
    cqo
    div rbx
    mov [ballPos + 8], rax

_mainloop:
    call _readKeyboardInput

    call _clearStagingBuffer

; handle input
    cmp byte [leftPaddleUpKey], 1
    jne _mainloop_notkeypress_leftpaddle_up
    sub qword [leftPaddleY], PADDLE_SPEED
_mainloop_notkeypress_leftpaddle_up:
    cmp byte [leftPaddleDownKey], 1
    jne _mainloop_notkeypress_leftpaddle_down
    add qword [leftPaddleY], PADDLE_SPEED
_mainloop_notkeypress_leftpaddle_down:
    cmp byte [rightPaddleUpKey], 1
    jne _mainloop_notkeypress_rightpaddle_up
    sub qword [rightPaddleY], PADDLE_SPEED
_mainloop_notkeypress_rightpaddle_up:
    cmp byte [rightPaddleDownKey], 1
    jne _mainloop_notkeypress_rightpaddle_down
    add qword [rightPaddleY], PADDLE_SPEED
_mainloop_notkeypress_rightpaddle_down:

; apply ball vel
    mov rax, [ballVel]
    add [ballPos], rax
    mov rax, [ballVel + 8]
    add [ballPos + 8], rax

; ball paddle collision
    cmp qword [ballVel], 0
    jge _mainloop_ballPositiveXVel
    cmp qword [ballPos], PADDLE_X + BALL_RADIUS
    jg _mainloop_ballPaddleCollisionEnd
    cmp qword [ballPos], PADDLE_X
    jl _mainloop_ballPaddleCollisionEnd
    mov rax, [leftPaddleY]
    add rax, [paddleHalfSize]
    cmp [ballPos + 8], rax
    jg _mainloop_ballPaddleCollisionEnd
    mov rax, [leftPaddleY]
    sub rax, [paddleHalfSize]
    cmp [ballPos + 8], rax
    jl _mainloop_ballPaddleCollisionEnd
    jmp _mainloop_swapBallXDir
_mainloop_ballPositiveXVel:
    mov rax, [worldW]
    sub rax, PADDLE_X + BALL_RADIUS
    cmp [ballPos], rax
    jl _mainloop_ballPaddleCollisionEnd
    mov rax, [worldW]
    sub rax, PADDLE_X
    cmp [ballPos], rax
    jg _mainloop_ballPaddleCollisionEnd
    mov rax, [rightPaddleY]
    add rax, [paddleHalfSize]
    cmp [ballPos + 8], rax
    jg _mainloop_ballPaddleCollisionEnd
    mov rax, [rightPaddleY]
    sub rax, [paddleHalfSize]
    cmp [ballPos + 8], rax
    jl _mainloop_ballPaddleCollisionEnd
_mainloop_swapBallXDir:
    mov rax, 0
    mov rbx, [ballVel]
    sub rax, rbx
    mov [ballVel], rax
    call _randomizeBallYVel
_mainloop_ballPaddleCollisionEnd:

; ball wall collision

    cmp qword [ballVel + 8], 0
    jg _mainloop_ballPositiveYVel
    cmp qword [ballPos + 8], BALL_RADIUS
    jg _mainloop_ballWallCollisionEnd
    jmp _mainloop_swapBallYDir
_mainloop_ballPositiveYVel:
    mov rax, [worldH]
    sub rax, BALL_RADIUS
    cmp [ballPos + 8], rax
    jl _mainloop_ballWallCollisionEnd
_mainloop_swapBallYDir:
    mov rax, 0
    mov rbx, [ballVel + 8]
    sub rax, rbx
    mov [ballVel + 8], rax
_mainloop_ballWallCollisionEnd:

    call _drawBall
    call _drawPaddles

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

_randomizeBallYVel:
; generate random 4 bit number
    mov rax, [ballPos]
    mov rbx, 3
    mul rbx
    and rax, 0xf
    add rax, [leftPaddleY]
    sub rax, [rightPaddleY]
    add rax, [ballPos + 8]
    add al, [leftPaddleUpKey]
    add al, [leftPaddleDownKey]
    and rax, 0xf
; get vel
    mov rbx, 8
    mul rbx
    mov rax, [randBallYVel + rax]
    mov [ballVel + 8], rax
    ret

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

    cmp bx, KEY_LEFT_PADDLE_UP
    je _readKeyboardInput_leftpaddle_up
    cmp bx, KEY_LEFT_PADDLE_DOWN
    je _readKeyboardInput_leftpaddle_down
    cmp bx, KEY_RIGHT_PADDLE_UP
    je _readKeyboardInput_rightpaddle_up
    cmp bx, KEY_RIGHT_PADDLE_DOWN
    je _readKeyboardInput_rightpaddle_down
    cmp bx, EXIT_KEY_1
    je _readKeyboardInput_exit
    cmp bx, EXIT_KEY_2
    je _readKeyboardInput_exit
    cmp bx, EXIT_KEY_3
    je _readKeyboardInput_exit
    jmp _readKeyboardInput_end
_readKeyboardInput_leftpaddle_up:
    mov [leftPaddleUpKey], al
    jmp _readKeyboardInput_end
_readKeyboardInput_leftpaddle_down:
    mov [leftPaddleDownKey], al
    jmp _readKeyboardInput_end
_readKeyboardInput_rightpaddle_up:
    mov [rightPaddleUpKey], al
    jmp _readKeyboardInput_end
_readKeyboardInput_rightpaddle_down:
    mov [rightPaddleDownKey], al
    jmp _readKeyboardInput_end
_readKeyboardInput_exit:
    mov byte [exit], 1
    jmp _readKeyboardInput_end
_readKeyboardInput_end:
    mov rsp, rbp
    pop rbp
    ret

; ===RENDERING===

_drawPaddles:
; left paddle
    mov qword [pointA], PADDLE_X
    mov rax, [leftPaddleY]
    sub rax, [paddleHalfSize]
    mov [pointA + 8], rax
    mov rax, pointA
    mov rbx, pointA
    call _worldToScreen

    mov qword [pointB], PADDLE_X
    mov rax, [leftPaddleY]
    add rax, [paddleHalfSize]
    mov [pointB + 8], rax
    mov rax, pointB
    mov rbx, pointB
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, PADDLE_COLOR
    call _drawLine
; right paddle
    mov rax, [worldW]
    sub rax, PADDLE_X
    mov qword [pointA], rax
    mov rax, [rightPaddleY]
    sub rax, [paddleHalfSize]
    mov [pointA + 8], rax
    mov rax, pointA
    mov rbx, pointA
    call _worldToScreen

    mov rax, [worldW]
    sub rax, PADDLE_X
    mov qword [pointB], rax
    mov rax, [rightPaddleY]
    add rax, [paddleHalfSize]
    mov [pointB + 8], rax
    mov rax, pointB
    mov rbx, pointB
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, PADDLE_COLOR
    call _drawLine
    ret

_drawBall:
    mov rax, [ballPos]
    add rax, BALL_RADIUS
    mov [pointA], rax
    mov rax, [ballPos + 8]
    add rax, BALL_RADIUS
    mov [pointA + 8], rax
    mov rax, pointA
    mov rbx, pointA
    call _worldToScreen

    mov rax, [ballPos]
    sub rax, BALL_RADIUS
    mov [pointB], rax
    mov rax, [ballPos + 8]
    add rax, BALL_RADIUS
    mov [pointB + 8], rax
    mov rax, pointB
    mov rbx, pointB
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, BALL_COLOR
    call _drawLine

    mov rax, [ballPos]
    add rax, BALL_RADIUS
    mov [pointB], rax
    mov rax, [ballPos + 8]
    sub rax, BALL_RADIUS
    mov [pointB + 8], rax
    mov rax, pointB
    mov rbx, pointB
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, BALL_COLOR
    call _drawLine

    mov rax, [ballPos]
    sub rax, BALL_RADIUS
    mov [pointA], rax
    mov rax, [ballPos + 8]
    sub rax, BALL_RADIUS
    mov [pointA + 8], rax
    mov rax, pointA
    mov rbx, pointA
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, BALL_COLOR
    call _drawLine

    mov rax, [ballPos]
    sub rax, BALL_RADIUS
    mov [pointB], rax
    mov rax, [ballPos + 8]
    add rax, BALL_RADIUS
    mov [pointB + 8], rax
    mov rax, pointB
    mov rbx, pointB
    call _worldToScreen

    mov rax, pointA
    mov rbx, pointB
    mov rcx, BALL_COLOR
    call _drawLine
    ret

; input: rax : pointer to point 1 {x1, y1} each 64 bit number
; input: rbx : pointer to point 2 {x2, y2} each 64 bit number
; input: ecx : color
_drawLine:
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
    jge _drawLine_x2larger
; x1 larger
    mov qword [rbp - 16], -1 ; x inc
    mov rcx, [rax] ; x1
    sub rcx, [rbx] ; rcx = x1 - x2
    jmp _drawLine_finishxcheck
_drawLine_x2larger:
    mov qword [rbp - 16], 1 ; x inc
    mov rcx, [rbx] ; x2
    sub rcx, [rax] ; rcx = x2 - x1
_drawLine_finishxcheck:
    add rcx, 1
    mov [rbp - 24], rcx ; xdiff = rcx
    mov rcx, [rbx + 8] ; y2
    cmp rcx, [rax + 8] ; y1
    jge _drawLine_y2larger
; y1 larger
    mov qword [rbp - 32], -1 ; y inc
    mov rcx, [rax + 8] ; y1
    sub rcx, [rbx + 8] ; rcx = y1 - y2
    jmp _drawLine_finishycheck
_drawLine_y2larger:
    mov qword [rbp - 32], 1 ; y inc
    mov rcx, [rbx + 8] ; y2
    sub rcx, [rax + 8] ; rcx = y2 - y1
_drawLine_finishycheck:
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
; if end pixel == start pixel
    cmp rax, rcx
    jne _drawLine_notEqual
    mov edx, [rbp - 52]
    call _drawLine_drawpx
    jmp _drawLine_endline
_drawLine_notEqual:
; xdiff * 2
    mov rax, [rbp - 24] ; xdiff
    mov rbx, 2
    mul rbx
    mov [rbp - 48], rax ; xdiff * 2
; draw line
    ; rcx is current px
    mov rbx, 0 ; rbx is i
    mov edx, [rbp - 52] ; edx is color
_drawLine_next:
    call _drawLine_drawpx
    add rbx, [rbp - 40] ; i += ydiff
_drawLine_yfaraboverepeat:
    cmp rbx, [rbp - 48] ; xdiff * 2
    jl _drawLine_ynotfarabove ; i < xdiff*2
    sub rbx, [rbp - 24] ; i -= xdiff
    call _drawLine_incy
    call _drawLine_drawpx
    cmp rcx, [rbp - 8]
    je _drawLine_endline ; currentpx == targetpx
    jmp _drawLine_yfaraboverepeat
_drawLine_ynotfarabove:
    cmp rbx, [rbp - 24] ; xdiff
    jl _drawLine_nextx ; i < xdiff
    sub rbx, [rbp - 24] ; i -= xdiff
    call _drawLine_incy
_drawLine_nextx:
    call _drawLine_incx
    cmp rcx, [rbp - 8]
    jne _drawLine_next ; currentpx != targetpx
_drawLine_endline:
    mov rsp, rbp
    pop rbp
    ret

_drawLine_drawpx:
    cmp rcx, 0
    jl _drawLine_drawpx_nodraw
    cmp rcx, [screenSize]
    jge _drawLine_drawpx_nodraw
    mov rax, [rbp - 60] ; xcoord
    cmp rax, 0
    jl _drawLine_drawpx_nodraw
    cmp rax, [screenW]
    jge _drawLine_drawpx_nodraw
    mov [stagingBuffer + rcx], edx ; draw
_drawLine_drawpx_nodraw:
    ret
_drawLine_incx:
    push rax
    mov rax, [rbp - 16] ; x inc
    cmp rax, 1
    je _drawLine_incx_add
    sub rcx, 4 ; x -= 1
    sub qword [rbp - 60], 1 ; xcoord -= 1
    jmp _drawLine_incx_end
_drawLine_incx_add:
    add rcx, 4 ; x += 1
    add qword [rbp - 60], 1 ; xcoord -= 1
_drawLine_incx_end:
    pop rax
    ret
_drawLine_incy:
    push rax
    mov rax, [rbp - 32] ; y inc
    cmp rax, 1
    je _drawLine_incy_add
    sub rcx, [screenRowSize] ; y -= 1
    jmp _drawLine_incy_end
_drawLine_incy_add:
    add rcx, [screenRowSize] ; y += 1
_drawLine_incy_end:
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
