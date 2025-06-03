# BrainF*ck CPU
**VUT FIT 2024/25 - INP Project 1**

A simple 8-bit CPU implementation in VHDL that interprets BrainFuck programs.

## Overview
This project implements a BrainFuck interpreter as a hardware CPU using VHDL. The CPU can execute BrainFuck programs stored in memory and interact with input/output devices.

## Files
- `cpu.vhd` - Main CPU implementation with BrainFuck interpreter
- `login.b` - BrainFuck program that prints the login "xlucnyj00" 

## BrainFuck Instructions Supported
- `>` - Increment data pointer
- `<` - Decrement data pointer  
- `+` - Increment value at data pointer
- `-` - Decrement value at data pointer
- `[` - Jump forward past matching `]` if value at pointer is zero
- `]` - Jump back to matching `[` if value at pointer is non-zero
- `$` - Store current value to temporary register
- `!` - Load value from temporary register
- `.` - Output character at data pointer
- `,` - Input character to data pointer
- `@` - Halt program execution

## Architecture
The CPU consists of:
- Program Counter (PC) register
- Data Pointer (PTR) register  
- Temporary (TMP) register
- Counter (CNT) register for loop handling
- Two multiplexers for data routing
- FSM controller with 25+ states

Total points: 18/23
