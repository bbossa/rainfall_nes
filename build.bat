@del rainfall.o
@del rainfall.nes
@del rainfall.map.txt
@del rainfall.labels.txt
@del rainfall.nes.dbg
@echo.
@echo Compiling...
.\cc65\bin\ca65 rainfall.asm -g -o rainfall.o
@IF ERRORLEVEL 1 GOTO failure
@echo.
@echo Linking...
.\cc65\bin\ld65 -o rainfall.nes -C memory.cfg rainfall.o -m rainfall.map.txt -Ln rainfall.labels.txt --dbgfile rainfall.nes.dbg
@IF ERRORLEVEL 1 GOTO failure
@echo.
@echo Success!
@GOTO endbuild
:failure
@echo.
@echo Build error!
:endbuild
pause