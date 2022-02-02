%define FRAMEBUFFER "/dev/fb0"
%define KEYBOARD_DEVICE "/dev/input/by-id/usb-SONiX_USB_DEVICE-event-kbd"

; run 'cat /sys/class/graphics/fb0/virtual_size' to check your frame buffer res
SCREEN_RES_X equ 1920
SCREEN_RES_Y equ 1080

; see "/usr/include/linux/input-event-codes.h" for key codes
KEY_LEFT_PADDLE_UP equ 17 ; 17 is 'w' key
KEY_LEFT_PADDLE_DOWN equ 31 ; 31 is 's' key
KEY_RIGHT_PADDLE_UP equ 103 ; 103 is up arrow key
KEY_RIGHT_PADDLE_DOWN equ 108 ; 108 is down arrow key
EXIT_KEY_1 equ 1 ; 1 is escape key
EXIT_KEY_2 equ 16 ; 16 is 'q' key
EXIT_KEY_3 equ 29 ; 29 is left ctrl key

PADDLE_SPEED equ 100

BALL_COLOR equ 0x0000ff00
PADDLE_COLOR equ 0x00ffffff

TOPBOTTOM_COLOR equ 0x00ffffff
SIDES_COLOR equ 0x00ff0000
