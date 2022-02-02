%define FRAMEBUFFER "/dev/fb0"
%define KEYBOARD_DEVICE "/dev/input/by-id/usb-SONiX_USB_DEVICE-event-kbd"

; see "/usr/include/linux/input-event-codes.h" for key codes
KEY_UP equ 103 ; 103 is up arrow key
KEY_DOWN equ 108 ; 108 is down arrow key
EXIT_KEY_1 equ 1 ; 1 is escape key
EXIT_KEY_2 equ 16 ; 16 is 'Q' key
EXIT_KEY_3 equ 29 ; 29 is left ctrl key

PADDLE_SPEED equ 100
