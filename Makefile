TARGET = datamonitor
LIBS = user32.dll kernel32.dll shell32.dll gdi32.dll ws2_32.dll

AFLAGS = -f win32 $(TARGET).asm -o $(TARGET).obj
LFLAGS = /entry start /mix  $(TARGET).obj $(LIBS)


all: $(TARGET)

$(TARGET): $(TARGET).asm
	nasm $(AFLAGS)
	golink $(LFLAGS)

recompile:
	make clean
	make all

clean:
	rm -f *.exe
	rm -f *.obj
