# -- Get path for ca65 and ld65
ifeq ($(OS), Windows_NT)
	CC65_HOME = ..\Tools\cc65
	AS = $(CC65_HOME)\bin\ca65.exe
	LD = $(CC65_HOME)\bin\ld65.exe
	EMU = ../Tools/Mesen_2.1.1/Mesen.exe
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S), Linux)
		CC65_HOME = ../Tools/cc65-linux
		AS = $(CC65_HOME)/bin/ca65
		LD = $(CC65_HOME)/bin/ld65
		EMU = ../Tools/Mesen
	endif
		
endif
# Nom du projet (sans extension)
PROJECT = rainfall

# Chemins
SRC_DIR = ./src
OBJ_DIR = ./obj
BIN_DIR = ./bin

# Fichiers sources 
ASM_SOURCES = $(SRC_DIR)/$(PROJECT).asm

# Fichiers objets
ASM_OBJECTS = $(patsubst $(SRC_DIR)/%.asm,$(OBJ_DIR)/%.o,$(ASM_SOURCES))
OBJECTS     = $(ASM_OBJECTS)

# Fichier final
TARGET = $(BIN_DIR)/$(PROJECT).nes

# Outils
RM = rm -f

# Flags
ASFLAGS = -g --cpu 6502 --verbose
LDFLAGS = -C $(SRC_DIR)/$(PROJECT).cfg -o $(TARGET) --dbgfile $(BIN_DIR)/$(PROJECT).dbg -m $(BIN_DIR)/$(PROJECT).map.txt -Ln $(BIN_DIR)/$(PROJECT).labels.txt


# Règles
all: $(TARGET)

debug:
	echo $(TARGET)
	echo $(OBJECTS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.asm
	@mkdir -p $(@D)
	$(AS) $(ASFLAGS) $< -o $@

$(TARGET): $(OBJECTS)
	@mkdir -p $(@D)
	$(LD) $(LDFLAGS) $(OBJECTS)

clean:
	$(RM) $(OBJ_DIR)/*.o
	$(RM) $(BIN_DIR)/*.nes
	$(RM) $(BIN_DIR)/*.dbg
	$(RM) $(BIN_DIR)/*.map.txt
	$(RM) $(BIN_DIR)/*.labels.txt
	
run:
	$(EMU) $(TARGET)

.PHONY: all clean
	
