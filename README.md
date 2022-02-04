# x86_64 assmebly pong
I wanted to learn assembly so I made this simple game. It draws graphics
directly to the linux framebuffer so that I dont need to worry about
communication with a display server. Keyboard input is read directly from the
keyboard device file located in `/dev/input`.

![image](image.png)

# How to run
1. Ensure you are on a x86_64 linux system.
2. Find your keyboard device file in `/dev/input`. It may look something like
`/dev/input/by-id/usb-SONiX_USB_DEVICE-event-kbd`
3. Edit config.asm and change the line 
`%define KEYBOARD_DEVICE "/dev/input/by-id/usb-SONiX_USB_DEVICE-event-kbd"`
to use your keyboard device.
4. Check your framebuffer size with `cat /sys/class/graphics/fb0/virtual_size`.
If framebuffer size is greater than the size of your screen then you wont be
able to see the one pixel wide graphics in the game. When I tried running the
game in my virtual machine my framebuffer size was 2048x2048 but my screen size
was 800x600 so it did not work.
5. Edit config.asm to use your framebuffer size.
```
SCREEN_RES_X equ 1920
SCREEN_RES_Y equ 1080
```
6. Exit your window manager / desktop enviroment or switch to a tty without one
running (try alt+ctrl+F2). This is required because if the window manager /
desktop enviroment is running then it may try to write to the framebuffer at the
same time as the game.

7. Run `make run` with root privileges.

