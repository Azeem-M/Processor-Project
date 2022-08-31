# Processor-Project
This project is for a 16-bit processor written in Verilog. The processor supports many different instructions. The processor works by utilising a finite-state machine (FSM) that contains 6 different states. 

## Visual Representation of Processor
Below is a visual representation of the processor showing its many components such as the arithmetic logic unit (ALU), 16 bit buswires, and control unit (FSM). 

![image](https://user-images.githubusercontent.com/104869723/187580323-68d0ad20-fb25-4951-a00f-4beeaa544f4d.png)



## Instructions Supported
Moving/copying registers (mov), moving top (mvt), adding (add), subtracting (sub), logical and (and), loading registers (ld), storing into registers (st), and conditional branching (b[cond]). 

Conditional branching is supported for the following condtions: 


eq - equal


ne - not equal


cc - carry clear


cs - carry set


pl - positive


mi - negative


