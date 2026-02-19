# Assembly notes

## Numerical representation

## Registers

## Status flags - Processor Status

The 6502 gives us eight flags that can be used to check whether a required condition has been met.

| Bit | Symbol | Name |
|-----|--------|------|
|  7  |   N    | Negative |
|  6  |   V    | Overflow |
|  5  |   -    | Unused |
|  4  |   B    | Break |
|  3  |   D    | Decimal |
|  2  |   I    | Interrupt Disable |
|  1  |   Z    | Zero |
|  0  |   C    | Cary |

## Maths

### Comparison: CMP

Instruction does the following operation : `N, Z, C = A - M`

This instruction compares the contents of the accumulator with another memory held value and sets the zero and carry flags as appropriate.

Processor Status after use:

| Flag | Name | Result |
|------|------|--------|
|  N   | Negative Flag | Set if bit 7 of the result is set |
|  V   | Overflow Flag | Not affected |
|  -   | - | - |
|  B   | Break Command | Not affected |
|  D   | Decimal Mode Flag | Not affected |
|  I   | Interrupt Disable | Not affected |
|  Z   | Zero Flag | Set if A = M |
|  C   | Carry Flag |  Set if A >= M |


The following command :
```
lda #$02
cmp #$04
```
Produces the following processor status :
| N | V | - | B | D | I | Z | C |
|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 |

Bit **0** (*C*) is not set as A is lower than M, bit **1** (*Z*) is not set as A is not equal to M and bit **7** (*N*) is set as the subtraction produce a negative number (in binary mode bit 7 is not set).


```
lda #$04
cmp #$02
```
Produces the following processor status :
| N | V | - | B | D | I | Z | C |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1 |
Bit **0** (*C*) is set as A is higher than M, bit **1** (*Z*) is not set as A is not equal to M and bit **7** (*N*) is set as the subtraction produce a positive number (in binary mode bit 7 is not set).


```
lda #$04
cmp #$04
```
Produces the following processor status :
| N | V | - | B | D | I | Z | C |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 1 | 1 | 0 | 0 | 1 | 1 |
Bit **0** (*C*) is set as A is higher or equal to M, bit **1** (*Z*) is set as A is equal to M and bit **7** (*N*) is set as the subtraction produce zero (in binary mode bit 7 is not set).

Instructions **CPX** and **CPY** do the same thins bit compare the memroy value with respectively X and Y registers. The processors flags act with the same behavior.

### Comparison: BIT

The BIT instruction is a complex function. Unless any other operation instruction, the BIT instruction does not modify the accumulator value. The operation act as follow :
```
Accumalator        Memory
[76543210]  AND  [76543210] == 0 ?
                  NV           Z
```

```
lda #%11000110
sta $2000

lda #%10000000

bit $2000
```
Produces the following processor status :
| N | V | - | B | D | I | Z | C |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 |
**N** is set to 1 as Memory has bit **7** set, **V** is set to 1 as Memory has bit **6** set and Z is not set as A AND M. Z is not set as the AND result is not equal to 0.

```
lda #%11000111
sta $2000

lda #%00111000

bit $2000
```
Produces the following processor status :
| N | V | - | B | D | I | Z | C |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 1 | 0 | 0 | 1 | 0 |
**N** is set to 1 as Memory has bit **7** set, **V** is set to 1 as Memory has bit **6** set and Z is not set as A AND M. Z is set as the result of the AND operator is equal to 0.

One specific usage of the BIT operator is to test A with itself. Z will be set to 1 obviously but the main aspect is to easily check if bit 7 or bit 6 are set.

### Increment: INC

This instruction add 1 to memory: `INC M = M + 1`.


| Flag | Name | Result |
|------|------|--------|
|  N   | Negative Flag | Set if bit 7 of the result is set |
|  V   | Overflow Flag | Not affected |
|  -   | - | - |
|  B   | Break Command | Not affected |
|  D   | Decimal Mode Flag | Not affected |
|  I   | Interrupt Disable | Not affected |
|  Z   | Zero Flag | Set if result is zero |
|  C   | Carry Flag |  Not affected |

Two other instruction *INX* and *INY* do the same thing for respectively X and Y registers.

### AND

A logical AND is performed, bit by bit: `A,Z,N = A & M`. the *AND* instruction perform a bit by bit logical AND operation and store the result in A.

| Flag | Name | Result |
|------|------|--------|
|  N   | Negative Flag | Set if bit 7 of the result is set |
|  V   | Overflow Flag | Not affected |
|  -   | - | - |
|  B   | Break Command | Not affected |
|  D   | Decimal Mode Flag | Not affected |
|  I   | Interrupt Disable | Not affected |
|  Z   | Zero Flag | Set if result is zero |
|  C   | Carry Flag |  Not affected |

```
lda #$F0
AND #$0F
```
At the end,the register **A** is equal to *0*, zero flag (bit **1** *Z*) is set and negative flag is not set (bit **7** *N*).

```
lda #$F0
AND #$80
```
At the end,the register **A** is equal to *$80*, zero flag (bit **1** *Z*) is not and negative flag is set (bit **7** *N*).

## Conditions - Branches

### Branch on plus: BPL

If the negative flag (bit **7** *N*) is clear then add the relative displacement to the program counter to cause a branch to a new location.

```
ldx #$00
lda #%01000111

BPL skip
ldx #$FF
skip:
```
At the end, X is equal to $00. The branch condition is set (BPL is active if *N* is not set) and the code jump to section *skip*.

```
ldx #$00
lda #%11000111

BPL skip
ldx #$FF
skip:
```
At the end, X is equal to $FF. The branch condition is not set (BPL is active if *N* is not set, not the case here) and the code continue.

### Branch on minus: BMI

### Branch on overflow clear: BVC

### Branch on overflow set: BVS

### Branch on carry clear: BCC

If the carry flag (bit **0** *C*) is clear then add the relative displacement to the program counter to cause a branch to a new location.

```
ldx #$00
lda #04
cmp #32
bcc skip
  ldx #$FF
skip:
```
After the **CMP** instruction, the bit **0** of the processor flag is not set (A is lower than M). The branch condition is set (BCC is active if *C* bit is not set) and then the code jump to section *skip*. The register **X** equal `$00`.

```
ldx #$00
lda #34
cmp #32
bcc skip
  ldx #$FF
skip:
```
After the **CMP** instruction, the bit **0** of the processor flag is set (A is greater to M). The branch condition is not set (BCC is active if *C* bit is not set) and then the code continue. The register **X** equal `$FF`.

### Branch on carry set: BCS

### Branch on not equal: BNE

If the zero flag (bit **1** *Z*) is clear then add the relative displacement to the program counter to cause a branch to a new location.

```
lda #$02
cmp #$04
bne skip
lda #$FF
skip:
```
After the **CMP** instruction, the bit **1** of the processor flag is not set (not equal). The branch condition is set (BNE is active if *Z* bit is not set) and then the code jump to section *skip*. The accumulator **A** equal `$02`.

```
lda #$06
cmp #$04
bne skip
lda #$FF
skip:
```
After the **CMP** instruction, the bit **1** of the processor flag is not set (not equal). The branch condition is set (BNE is active if *Z* bit is not set) and then the code jump to section *skip*. The accumulator **A** equal `$06`.

```
lda #$04
cmp #$04
bne skip
lda #$FF
skip:
```
After the **CMP** instruction, the bit **1** of the processor flag is set (equal). The branch condition is not set (BNE is active if *Z* bit is not set) and then the code continue and modify the accumulator. The accumulator **A** equal `$FF`.

### Branch on equal: BEQ

If the zero flag (bit **1** *Z*) is set then add the relative displacement to the program counter to cause a branch to a new location.
