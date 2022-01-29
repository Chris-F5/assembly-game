section .data
    fbDir db "/dev/fb0", 0
    kbDir db "/dev/input/by-id/usb-SONiX_USB_DEVICE-event-kbd", 0
    screenW dq 1920
    screenRowSize dq 1920 * 4
    screenH dq 1080
    fbSize dq 1920 * 1080 * 4
    pointA dq 500, 500
    pointB dq 900, 800

section .bss
    sb resb 4 * 1920 * 1080 ; staging buffer
    fbfd resb 8 ; frame buffer file descriptor

section .text
    global _start

_start:
; open file
    mov rax, 2; sys_open
    mov rdi, fbDir
    mov rsi, 64+1; O_CREAT+O_WRONLY
    mov rdx, 0644o; 
    syscall
    mov [fbfd], rax

    mov rax, pointA
    mov rbx, pointB
    mov rcx, 0x0000000000ff00ff
    call drawline

    call flushsb

; close file
    mov rax, 3; sys_close
    mov rdi, [fbfd]
    syscall

; exit
    mov rax, 60
    mov rdi, 0
    syscall

; input: rax : pointer to point 1 {x1, y1} each 64 bit number
; input: rbx : pointer to point 2 {x2, y2} each 64 bit number
; input: rcx : color
drawline:
    push rbp
    mov rbp, rsp

    sub rsp, 70o
    ; [rbp - 10o] : col
    ; [rbp - 20o] : target px
    ; [rbp - 30o] : x inc
    ; [rbp - 40o] : x diff
    ; [rbp - 50o] : y inc
    ; [rbp - 60o] : y diff
    ; [rbp - 70o] : x diff * 2

    mov [rbp - 10o], rcx

; FIND DIFFS
    mov rcx, [rbx] ; x1
    cmp rcx, [rax] ; x2
    jge _drawline_x2larger
; x1 larger
    mov qword [rbp - 30o], -1 ; x inc
    mov rcx, [rax] ; x1
    sub rcx, [rbx] ; rcx = x1 - x2
    jmp _drawline_finishxcheck
_drawline_x2larger:
    mov qword [rbp - 30o], 1 ; x inc
    mov rcx, [rbx] ; x2
    sub rcx, [rax] ; rcx = x2 - x1
_drawline_finishxcheck:
    add rcx, 1
    mov [rbp - 40o], rcx ; xdiff = rcx

    mov rcx, [rbx + 8] ; y1
    cmp rcx, [rax + 8] ; y2
    jge _drawline_y2larger
; y1 larger
    mov qword [rbp - 50o], -1 ; y inc
    mov rcx, [rax + 8] ; y1
    sub rcx, [rbx + 8] ; rcx = y1 - y2
    jmp _drawline_finishycheck
_drawline_y2larger:
    mov qword [rbp - 50o], 1 ; y inc
    mov rcx, [rbx + 8] ; y2
    sub rcx, [rax + 8] ; rcx = y2 - y1
_drawline_finishycheck:
    add rcx, 1
    mov [rbp - 60o], rcx ; ydiff = rcx

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
    mov [rbp - 20o], rax ; targetpx

; XDIFF * 2
    mov rax, [rbp - 40o] ; xdiff
    mov rbx, 2
    mul rbx
    mov [rbp - 70o], rax ; xdiff * 2

; DRAW LINE
    ; rcx is current px
    mov rbx, 0 ; rbx is i
    mov rdx, [rbp - 10o] ; rdx is color
_drawline_next:
    mov [sb + rcx], rdx ; draw
    add rbx, [rbp - 60o] ; i += ydiff
_drawline_yfaraboverepeat:
    cmp rbx, [rbp - 70o] ; xdiff * 2
    jl _drawline_ynotfarabove ; i < xdiff*2
    sub rbx, [rbp - 40o] ; i -= xdiff
    call _drawline_incy
    mov [sb + rcx], rdx ; draw
    cmp rcx, [rbp - 20o]
    je _drawline_endline ; currentpx == targetpx
    jmp _drawline_yfaraboverepeat
_drawline_ynotfarabove:
    cmp rbx, [rbp - 40o] ; xdiff
    jl _drawline_nextx ; i < xdiff
    sub rbx, [rbp - 40o] ; i -= xdiff
    call _drawline_incy
_drawline_nextx:
    call _drawline_incx
    cmp rcx, [rbp - 20o]
    jne _drawline_next ; currentpx == targetpx
_drawline_endline:
    mov rsp, rbp
    pop rbp
    ret

_drawline_incx:
    push rax
    mov rax, [rbp - 30o] ; y inc
    cmp rax, 1
    je _drawline_incx_add
    sub rcx, 4 ; x -= 1
    jmp _drawline_incx_end
_drawline_incx_add:
    add rcx, 4 ; x += 1
_drawline_incx_end:
    pop rax
    ret

_drawline_incy:
    push rax
    mov rax, [rbp - 50o] ; y inc
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
