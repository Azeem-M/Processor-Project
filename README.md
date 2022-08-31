# Processor-Project
This project is for a 16-bit processor written in Verilog. The processor supports many different instructions. The processor works by utilising a finite-state machine that contains 6 different states. 

## Visual Representation of Processor
![image](https://user-images.githubusercontent.com/104869723/187580208-12f6e2c3-0d32-463f-a0cc-b469a859c26f.png)



## Instructions Supported
Moving/copying registers (mov), moving top (mvt), adding (add), subtracting (sub), logical and (and), loading registers (ld), storing into registers (st), and conditional branching (b[cond]). 

Conditional branching is supported for the following condtions: 
eq - equal
ne - not equal
cc - carry clear
cs - carry set
pl - positive
mi - negative


