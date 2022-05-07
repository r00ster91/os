# os

An experimental "operating system" that runs in user space as a normal program.

It uses [Wasm](https://wiki.osdev.org/WebAssembly) for its executables, has some very basic window graphics, and basic text output.

By default a program is run on startup that prints "hello" every second in a loop in the window. You can find its source code in `hello.zig`.
![image](https://user-images.githubusercontent.com/35064754/167272060-cd20b2bc-1f26-478f-bac2-5e70477d42bd.png)

It can parse the [FONTX](https://www.unifoundry.com/japanese/index.html) and BDF font formats.

It currently uses [raylib](https://github.com/raysan5/raylib/wiki/Working-on-GNU-Linux#build-raylib-using-make) for its graphics but the OS can easily be ported to any other graphics API that supports writing to a framebuffer.
