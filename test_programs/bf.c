typedef unsigned char uint8_t;
typedef unsigned int uint32_t;
typedef unsigned int size_t;
typedef enum uint8_t
{
    ADD,
    SUB,
    OPEN,
    CLOSE,
    LEFT,
    RIGHT,
    PUTC,
    GETC,
} Instr;

Instr instrs[128];
uint8_t tape[128];
uint32_t size = 0;

void translate (const char* prog)
{
    size_t i = 0;
    
    while (*prog && i < 128)
    {
        switch (*prog++)
        {
            case '+': instrs[i++] = ADD; break;
            case '-': instrs[i++] = SUB; break;
            case '[': instrs[i++] = OPEN; break;
            case ']': instrs[i++] = CLOSE; break;
            case '<': instrs[i++] = LEFT; break;
            case '>': instrs[i++] = RIGHT; break;
            case '.': instrs[i++] = PUTC; break;
            case ',': instrs[i++] = GETC; break;
        }
        size++;
    }
}

void run ()
{
    size_t pc = 0;
    size_t i = 0;
    uint8_t cur;
    while (pc < size)
        switch (instrs[pc])
        {
            case ADD: cur++; pc++; break;
            case SUB: cur--; pc++; break;
            case OPEN: 
                if (cur == 0)
                {
                    int cnt = 0;
                    do
                    {
                        switch(instrs[pc])
                        {
                            case OPEN: cnt++; break;
                            case CLOSE: cnt--; break;
                            default: break;
                        }
                        pc++;
                    } while (cnt != 0);
                } else pc++;
                break;
            case CLOSE:
                if (cur != 0)
                {
                    int cnt = 0;
                    do
                    {
                        switch(instrs[pc])
                        {
                            case OPEN: cnt++; break;
                            case CLOSE: cnt--; break;
                            default: break;
                        }
                        pc--;
                    } while (cnt != 0);
                    
                    pc += 2;
                } else pc++;
                break;
                
            case LEFT: tape[i] = cur; i--; cur = tape[i]; pc++; break;
            case RIGHT: tape[i] = cur; i++; cur = tape[i]; pc++; break;
            case PUTC: *(volatile uint8_t*)0xfe000000 = cur; pc++; break;
            case GETC: cur = 0; pc++; break;
        }
}

int main ()
{
    translate("++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.>+.>.");
    run();
}
