typedef unsigned int uint32_t;

static void print (const char* c)
{
    volatile char* out = (char*) 0x10000000;
    while (*c != 0)
        *out = *c++;
}

void printhex (uint32_t num);
int main ()
{
    print("Hello, World!\n");
    for (int i = 0; i < 10; i++)
    {
        printhex(i);
    }
}
